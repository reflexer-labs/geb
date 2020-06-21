// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.5.15;

import "./Logging.sol";
import "./LinkedList.sol";

contract CDPEngineLike {
    function collateralTypes(bytes32) external view returns (
        uint256 debtAmount,       // wad
        uint256 accumulatedRates  // ray
    );
    function updateAccumulatedRate(bytes32,address,int) external;
    function coinBalance(address) external view returns (uint);
}

contract TaxCollector is Logging {
    using LinkedList for LinkedList.List;

    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "TaxCollector/account-not-authorized");
        _;
    }

    // --- Events ---
    event Taxed(bytes32 collateralType, uint latestAccumulatedRate, int deltaRate);
    event UpdatedAccumulatedRate(bytes32 collateralType, address target, int taxCut);

    // --- Data ---
    struct CollateralType {
        // Per second borrow rate for this specific collateral type
        uint256 stabilityFee;
        // When SF was last collected for this collateral type
        uint256 updateTime;
    }
    // SF receiver (not AccountingEngine)
    struct TaxReceiver {
        // Whether this receiver can accept a negative rate (taking SF from it)
        uint256 canTakeBackTax;
        // Percentage of SF allocated to this receiver
        uint256 taxPercentage;
    }

    // Data about each collateral type
    mapping (bytes32 => CollateralType)                  public collateralTypes;
    // Percentage of each collateral's SF that goes to other addresses apart from AccountingEngine
    mapping (bytes32 => uint)                            public receiverAllotedTax;
    // Whether an address is already used for a tax receiver
    mapping (address => uint256)                         public usedTaxReceiver;
    // Address associated to each tax receiver index
    mapping (uint256 => address)                         public taxReceiverAccounts;
    // How many collateral types send SF to a specific tax receiver
    mapping (address => uint256)                         public taxReceiverRevenueSources;
    // Tax receiver data
    mapping (bytes32 => mapping(uint256 => TaxReceiver)) public taxReceivers;

    address    public accountingEngine;
    // Base stability fee charged by all collateral types
    uint256    public globalStabilityFee;
    // Total amount of secondary tax receivers ever added
    uint256    public taxReceiverNonce;
    // How many tax receivers a collateral type can have
    uint256    public maxSecondaryReceivers;
    // Latest tax receiver that still has at least one revenue source
    uint256    public latestTaxReceiver;

    // All collateral types
    bytes32[]        public   collateralList;
    // Linked list with tax receiver data
    LinkedList.List  internal taxReceiverList;

    CDPEngineLike public cdpEngine;

    // --- Init ---
    constructor(address cdpEngine_) public {
        authorizedAccounts[msg.sender] = 1;
        cdpEngine = CDPEngineLike(cdpEngine_);
    }

    // --- Math ---
    function rpow(uint x, uint n, uint b) internal pure returns (uint z) {
      assembly {
        switch x case 0 {switch n case 0 {z := b} default {z := 0}}
        default {
          switch mod(n, 2) case 0 { z := b } default { z := x }
          let half := div(b, 2)  // for rounding.
          for { n := div(n, 2) } n { n := div(n,2) } {
            let xx := mul(x, x)
            if iszero(eq(div(xx, x), x)) { revert(0,0) }
            let xxRound := add(xx, half)
            if lt(xxRound, xx) { revert(0,0) }
            x := div(xxRound, b)
            if mod(n,2) {
              let zx := mul(z, x)
              if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
              let zxRound := add(zx, half)
              if lt(zxRound, zx) { revert(0,0) }
              z := div(zxRound, b)
            }
          }
        }
      }
    }
    uint256 constant RAY     = 10 ** 27;
    uint256 constant HUNDRED = 10 ** 29;
    uint256 constant ONE     = 1;

    function add(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x);
    }
    function add(int x, int y) internal pure returns (int z) {
        z = x + y;
        if (y <= 0) require(z <= x);
        if (y  > 0) require(z > x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function sub(int x, int y) internal pure returns (int z) {
        z = x - y;
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }
    function diff(uint x, uint y) internal pure returns (int z) {
        z = int(x) - int(y);
        require(int(x) >= 0 && int(y) >= 0);
    }
    function mul(uint x, int y) internal pure returns (int z) {
        z = int(x) * y;
        require(int(x) >= 0);
        require(y == 0 || z / y == int(x));
    }
    function mul(int x, int y) internal pure returns (int z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / RAY;
    }

    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    // --- Administration ---
    /**
     * @notice Initialize a brand new collateral type
     * @param collateralType Collateral type name (e.g ETH-A, TBTC-B)
     */
    function initializeCollateralType(bytes32 collateralType) external emitLog isAuthorized {
        CollateralType storage collateralType_ = collateralTypes[collateralType];
        require(collateralType_.stabilityFee == 0, "TaxCollector/collateral-type-already-init");
        collateralType_.stabilityFee = RAY;
        collateralType_.updateTime   = now;
        collateralList.push(collateralType);
    }
    /**
     * @notice Modify collateral specific uint params
     * @param collateralType Collateral type who's parameter is modified
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(
        bytes32 collateralType,
        bytes32 parameter,
        uint data
    ) external emitLog isAuthorized {
        require(now == collateralTypes[collateralType].updateTime, "TaxCollector/update-time-not-now");
        if (parameter == "stabilityFee") collateralTypes[collateralType].stabilityFee = data;
        else revert("TaxCollector/modify-unrecognized-param");
    }
    /**
     * @notice Modify general uint params
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(bytes32 parameter, uint data) external emitLog isAuthorized {
        if (parameter == "globalStabilityFee") globalStabilityFee = data;
        else if (parameter == "maxSecondaryReceivers") maxSecondaryReceivers = data;
        else revert("TaxCollector/modify-unrecognized-param");
    }
    /**
     * @notice Modify general uint params
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(bytes32 parameter, address data) external emitLog isAuthorized {
        require(data != address(0), "TaxCollector/null-data");
        if (parameter == "accountingEngine") accountingEngine = data;
        else revert("TaxCollector/modify-unrecognized-param");
    }
    /**
     * @notice Set whether a tax receiver can incur negative fees
     * @param collateralType Collateral type giving fees to the tax receiver
     * @param position Receiver position in the list
     * @param val Value that specifies whether a tax receiver can incur negative rates
     */
    function modifyParameters(
        bytes32 collateralType,
        uint256 position,
        uint256 val
    ) external emitLog isAuthorized {
        if (both(taxReceiverList.isNode(position), taxReceivers[collateralType][position].taxPercentage > 0)) {
            taxReceivers[collateralType][position].canTakeBackTax = val;
        }
        else revert("TaxCollector/unknown-tax-receiver");
    }
    /**
     * @notice Create or modify a tax receiver's data
     * @param collateralType Collateral type that will give SF to the tax receiver
     * @param position Receiver position in the list. Used to determine whether a new tax receiver is
              created or an existing one is edited
     * @param taxPercentage Percentage of SF offered to the tax receiver
     * @param receiverAccount Receiver address
     */
    function modifyParameters(
      bytes32 collateralType,
      uint256 position,
      uint256 taxPercentage,
      address receiverAccount
    ) external emitLog isAuthorized {
        (!taxReceiverList.isNode(position)) ?
          createTaxReceiver(collateralType, taxPercentage, receiverAccount) :
          modifyTaxReceiver(collateralType, position, taxPercentage);
    }

    // --- Tax Receiver Utils ---
    /**
     * @notice Create a new tax receiver
     * @param collateralType Collateral type that will give SF to the tax receiver
     * @param taxPercentage Percentage of SF offered to the tax receiver
     * @param receiverAccount Tax receiver address
     */
    function createTaxReceiver(bytes32 collateralType, uint256 taxPercentage, address receiverAccount) internal {
        require(receiverAccount != address(0), "TaxCollector/null-account");
        require(receiverAccount != accountingEngine, "TaxCollector/accounting-engine-cannot-be-secondary-tax-receiver");
        require(taxPercentage > 0, "TaxCollector/null-sf");
        require(usedTaxReceiver[receiverAccount] == 0, "TaxCollector/account-already-used");
        require(add(taxReceiverListLength(), ONE) <= maxSecondaryReceivers, "TaxCollector/exceeds-max-receiver-limit");
        require(add(receiverAllotedTax[collateralType], taxPercentage) < HUNDRED, "TaxCollector/tax-cut-exceeds-hundred");
        taxReceiverNonce                                                      = add(taxReceiverNonce, 1);
        latestTaxReceiver                                                     = taxReceiverNonce;
        usedTaxReceiver[receiverAccount]                                      = ONE;
        receiverAllotedTax[collateralType]                                    = add(receiverAllotedTax[collateralType], taxPercentage);
        taxReceivers[collateralType][latestTaxReceiver].taxPercentage = taxPercentage;
        taxReceiverAccounts[latestTaxReceiver]                                = receiverAccount;
        taxReceiverRevenueSources[receiverAccount]                            = ONE;
        taxReceiverList.push(latestTaxReceiver, false);
    }
    /**
     * @notice Update a tax receiver's data (add a new SF source or modify % of SF taken from a collateral type)
     * @param collateralType Collateral type that will give SF to the tax receiver
     * @param position Receiver's position in the tax receiver list
     * @param taxPercentage Percentage of SF offered to the tax receiver
     */
    function modifyTaxReceiver(bytes32 collateralType, uint256 position, uint256 taxPercentage) internal {
        if (taxPercentage == 0) {
          receiverAllotedTax[collateralType] = sub(
            receiverAllotedTax[collateralType],
            taxReceivers[collateralType][position].taxPercentage
          );

          if (taxReceiverRevenueSources[taxReceiverAccounts[position]] == 1) {
            if (position == latestTaxReceiver) {
              (, uint256 prevReceiver) = taxReceiverList.prev(latestTaxReceiver);
              latestTaxReceiver = prevReceiver;
            }
            taxReceiverList.del(position);
            delete(usedTaxReceiver[taxReceiverAccounts[position]]);
            delete(taxReceivers[collateralType][position]);
            delete(taxReceiverRevenueSources[taxReceiverAccounts[position]]);
            delete(taxReceiverAccounts[position]);
          } else if (taxReceivers[collateralType][position].taxPercentage > 0) {
            taxReceiverRevenueSources[taxReceiverAccounts[position]] = sub(taxReceiverRevenueSources[taxReceiverAccounts[position]], 1);
            delete(taxReceivers[collateralType][position]);
          }
        } else {
          uint256 receiverAllotedTax_ = add(
            sub(receiverAllotedTax[collateralType], taxReceivers[collateralType][position].taxPercentage),
            taxPercentage
          );
          require(receiverAllotedTax_ < HUNDRED, "TaxCollector/tax-cut-too-big");
          if (taxReceivers[collateralType][position].taxPercentage == 0) {
            taxReceiverRevenueSources[taxReceiverAccounts[position]] = add(
              taxReceiverRevenueSources[taxReceiverAccounts[position]],
              1
            );
          }
          receiverAllotedTax[collateralType]                    = receiverAllotedTax_;
          taxReceivers[collateralType][position].taxPercentage = taxPercentage;
        }
    }

    // --- Tax Collection Utils ---
    /**
     * @notice Check if all collateral types are up to date with taxation
     */
    function collectedAllTax() public view returns (bool ko) {
        for (uint i = 0; i < collateralList.length; i++) {
          if (now > collateralTypes[collateralList[i]].updateTime) {
            ko = true;
            break;
          }
        }
    }
    /**
     * @notice Check how much SF will be distributed (from all collateral types) during the next taxation
     */
    function nextTaxationOutcome() public view returns (bool ok, int rad) {
        int  accountingEngineCoinBalance_ = -int(cdpEngine.coinBalance(accountingEngine));
        int  deltaRate;
        uint debtAmount;
        for (uint i = 0; i < collateralList.length; i++) {
          if (now > collateralTypes[collateralList[i]].updateTime) {
            (debtAmount, ) = cdpEngine.collateralTypes(collateralList[i]);
            (, deltaRate) = taxationOutcome(collateralList[i]);
            rad = add(rad, mul(debtAmount, deltaRate));
          }
        }
        if (rad < 0) {
          ok = (rad < accountingEngineCoinBalance_) ? false : true;
        } else {
          ok = true;
        }
    }
    /**
     * @notice Get the average taxation rate across all collateral types
     */
    function averageTaxationRate(uint globalStabilityFee_) public view returns (uint256 z) {
        if (collateralList.length == 0) return globalStabilityFee_;
        for (uint i = 0; i < collateralList.length; i++) {
          z = add(z, add(globalStabilityFee_, collateralTypes[collateralList[i]].stabilityFee));
        }
        z = z / collateralList.length;
    }

    // --- Gifts Utils ---
    /**
     * @notice Get the tax receiver list length
     */
    function taxReceiverListLength() public view returns (uint) {
        return taxReceiverList.range();
    }
    /**
     * @notice Check if a tax receiver is at a certain position in the list
     */
    function isTaxReceiver(uint256 _receiver) public view returns (bool) {
        return taxReceiverList.isNode(_receiver);
    }

    // --- Tax (Stability Fee) Collection ---
    /**
     * @notice Get how much SF will be distributed after taxing a specific collateral type
     * @param collateralType Collateral type to compute the taxation outcome for
     */
    function taxationOutcome(bytes32 collateralType) public view returns (uint, int) {
        (, uint lastAccumulatedRate) = cdpEngine.collateralTypes(collateralType);
        uint newlyAccumulatedRate =
          rmul(
            rpow(
              add(
                globalStabilityFee,
                collateralTypes[collateralType].stabilityFee
              ),
              sub(
                now,
                collateralTypes[collateralType].updateTime
              ),
            RAY),
          lastAccumulatedRate);
        return (newlyAccumulatedRate, diff(newlyAccumulatedRate, lastAccumulatedRate));
    }
    /**
     * @notice Collect tax from all collateral types
     */
    function taxAll() external emitLog {
        for (uint i = 0; i < collateralList.length; i++) {
            taxSingle(collateralList[i]);
        }
    }
    /**
     * @notice Collect tax from a single collateral type
     * @param collateralType Collateral type to tax
     */
    function taxSingle(bytes32 collateralType) public emitLog returns (uint) {
        uint latestAccumulatedRate;
        if (now <= collateralTypes[collateralType].updateTime) {
          (, latestAccumulatedRate) = cdpEngine.collateralTypes(collateralType);
          return latestAccumulatedRate;
        }
        (, int deltaRate) = taxationOutcome(collateralType);
        splitTaxIncome(collateralType, deltaRate);
        (, latestAccumulatedRate) = cdpEngine.collateralTypes(collateralType);
        collateralTypes[collateralType].updateTime = now;
        emit Taxed(collateralType, latestAccumulatedRate, deltaRate);
        return latestAccumulatedRate;
    }
    /**
     * @notice Distribute SF to tax receivers and to the AccountingEngine
     * @param collateralType Collateral type to distribute SF for
     * @param deltaRate Difference between the last and the latest accumulate rates for the collateralType
     */
    function splitTaxIncome(bytes32 collateralType, int deltaRate) internal {
        // Check how much debt has been generated for collateralType
        (uint debtAmount, ) = cdpEngine.collateralTypes(collateralType);
        // Start looping from the latest tax receiver
        uint256 currentTaxReceiver = latestTaxReceiver;
        // While we still haven't gone through the entire tax receiver list
        while (currentTaxReceiver > 0) {
          // If the current tax receiver should receive SF from collateralType
          if (taxReceivers[collateralType][currentTaxReceiver].taxPercentage > 0) {
            distributeSecondaryTaxReceiverIncome(collateralType, currentTaxReceiver, debtAmount, deltaRate);
          }
          // Continue looping
          (, currentTaxReceiver) = taxReceiverList.prev(currentTaxReceiver);
        }
        // Repeat the exact process for AccountingEngine but do not check if it accepts negative rates
        distributeAccountingEngineIncome(collateralType, debtAmount, deltaRate);
    }
    function distributeAccountingEngineIncome(
        bytes32 collateralType,
        uint256 debtAmount,
        int256 deltaRate
    ) internal {
        int256 coinBalance   = -int(cdpEngine.coinBalance(accountingEngine));
        int256 currentTaxCut = mul(sub(HUNDRED, receiverAllotedTax[collateralType]), deltaRate) / int(HUNDRED);
        currentTaxCut  = (
          both(mul(debtAmount, currentTaxCut) < 0, coinBalance > mul(debtAmount, currentTaxCut))
        ) ? coinBalance / int(debtAmount) : currentTaxCut;
        if (currentTaxCut != 0) {
          cdpEngine.updateAccumulatedRate(collateralType, accountingEngine, currentTaxCut);
          emit UpdatedAccumulatedRate(collateralType, accountingEngine, currentTaxCut);
        }
    }
    function distributeSecondaryTaxReceiverIncome(
        bytes32 collateralType,
        uint256 receiver,
        uint256 debtAmount,
        int256 deltaRate
    ) internal {
        // Check how many coins the receiver has and negate the value
        int256 coinBalance   = -int(cdpEngine.coinBalance(taxReceiverAccounts[receiver]));
        // Compute the % out of deltaRate that should be allocated to the current tax receiver
        int256 currentTaxCut = mul(int(taxReceivers[collateralType][receiver].taxPercentage), deltaRate) / int(HUNDRED);
        /**
            If SF is negative and the tax receiver doesn't have enough coins to absorb the loss,
            compute a new tax cut that can be absorbed
        **/
        currentTaxCut  = (
          both(mul(debtAmount, currentTaxCut) < 0, coinBalance > mul(debtAmount, currentTaxCut))
        ) ? coinBalance / int(debtAmount) : currentTaxCut;
        /**
          If the tax receiver's tax cut is not null and if the receiver accepts negative SF
          (in case currentTaxCut is negative), offer/subtract SF from them
        **/
        if (
          both(
            currentTaxCut != 0,
            either(
              deltaRate >= 0,
              both(currentTaxCut < 0, taxReceivers[collateralType][receiver].canTakeBackTax > 0)
            )
          )
        ) {
          cdpEngine.updateAccumulatedRate(collateralType, taxReceiverAccounts[receiver], currentTaxCut);
          emit UpdatedAccumulatedRate(collateralType, taxReceiverAccounts[receiver], currentTaxCut);
        }
    }
}
