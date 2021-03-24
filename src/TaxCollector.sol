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

pragma solidity 0.6.7;

import "./LinkedList.sol";

abstract contract SAFEEngineLike {
    function collateralTypes(bytes32) virtual public view returns (
        uint256 debtAmount,       // [wad]
        uint256 accumulatedRate   // [ray]
    );
    function updateAccumulatedRate(bytes32,address,int256) virtual external;
    function coinBalance(address) virtual public view returns (uint256);
}

contract TaxCollector {
    using LinkedList for LinkedList.List;

    // --- Auth ---
    mapping (address => uint256) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 1;
        emit AddAuthorization(account);
    }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 0;
        emit RemoveAuthorization(account);
    }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "TaxCollector/account-not-authorized");
        _;
    }

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event InitializeCollateralType(bytes32 collateralType);
    event ModifyParameters(
      bytes32 collateralType,
      bytes32 parameter,
      uint256 data
    );
    event ModifyParameters(bytes32 parameter, uint256 data);
    event ModifyParameters(bytes32 parameter, address data);
    event ModifyParameters(
      bytes32 collateralType,
      uint256 position,
      uint256 val
    );
    event ModifyParameters(
      bytes32 collateralType,
      uint256 position,
      uint256 taxPercentage,
      address receiverAccount
    );
    event AddSecondaryReceiver(
      bytes32 indexed collateralType,
      uint256 secondaryReceiverNonce,
      uint256 latestSecondaryReceiver,
      uint256 secondaryReceiverAllotedTax,
      uint256 secondaryReceiverRevenueSources
    );
    event ModifySecondaryReceiver(
      bytes32 indexed collateralType,
      uint256 secondaryReceiverNonce,
      uint256 latestSecondaryReceiver,
      uint256 secondaryReceiverAllotedTax,
      uint256 secondaryReceiverRevenueSources
    );
    event CollectTax(bytes32 indexed collateralType, uint256 latestAccumulatedRate, int256 deltaRate);
    event DistributeTax(bytes32 indexed collateralType, address indexed target, int256 taxCut);

    // --- Data ---
    struct CollateralType {
        // Per second borrow rate for this specific collateral type
        uint256 stabilityFee;
        // When SF was last collected for this collateral type
        uint256 updateTime;
    }
    // SF receiver
    struct TaxReceiver {
        // Whether this receiver can accept a negative rate (taking SF from it)
        uint256 canTakeBackTax;                                                 // [bool]
        // Percentage of SF allocated to this receiver
        uint256 taxPercentage;                                                  // [ray%]
    }

    // Data about each collateral type
    mapping (bytes32 => CollateralType)                  public collateralTypes;
    // Percentage of each collateral's SF that goes to other addresses apart from the primary receiver
    mapping (bytes32 => uint256)                         public secondaryReceiverAllotedTax;              // [%ray]
    // Whether an address is already used for a tax receiver
    mapping (address => uint256)                         public usedSecondaryReceiver;                    // [bool]
    // Address associated to each tax receiver index
    mapping (uint256 => address)                         public secondaryReceiverAccounts;
    // How many collateral types send SF to a specific tax receiver
    mapping (address => uint256)                         public secondaryReceiverRevenueSources;
    // Tax receiver data
    mapping (bytes32 => mapping(uint256 => TaxReceiver)) public secondaryTaxReceivers;

    // The address that always receives some SF
    address    public primaryTaxReceiver;
    // Base stability fee charged to all collateral types
    uint256    public globalStabilityFee;                                                                 // [ray%]
    // Number of secondary tax receivers ever added
    uint256    public secondaryReceiverNonce;
    // Max number of secondarytax receivers a collateral type can have
    uint256    public maxSecondaryReceivers;
    // Latest secondary tax receiver that still has at least one revenue source
    uint256    public latestSecondaryReceiver;

    // All collateral types
    bytes32[]        public   collateralList;
    // Linked list with tax receiver data
    LinkedList.List  internal secondaryReceiverList;

    SAFEEngineLike public safeEngine;

    // --- Init ---
    constructor(address safeEngine_) public {
        authorizedAccounts[msg.sender] = 1;
        safeEngine = SAFEEngineLike(safeEngine_);
        emit AddAuthorization(msg.sender);
    }

    // --- Math ---
    uint256 public constant RAY           = 10 ** 27;
    uint256 public constant WHOLE_TAX_CUT = 10 ** 29;
    uint256 public constant ONE           = 1;
    int256  public constant INT256_MIN    = -2**255;

    function rpow(uint256 x, uint256 n, uint256 b) internal pure returns (uint256 z) {
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
    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x + y;
        require(z >= x, "TaxCollector/add-uint-uint-overflow");
    }
    function addition(int256 x, int256 y) internal pure returns (int256 z) {
        z = x + y;
        if (y <= 0) require(z <= x, "TaxCollector/add-int-int-underflow");
        if (y  > 0) require(z > x, "TaxCollector/add-int-int-overflow");
    }
    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "TaxCollector/sub-uint-uint-underflow");
    }
    function subtract(int256 x, int256 y) internal pure returns (int256 z) {
        z = x - y;
        require(y <= 0 || z <= x, "TaxCollector/sub-int-int-underflow");
        require(y >= 0 || z >= x, "TaxCollector/sub-int-int-overflow");
    }
    function deduct(uint256 x, uint256 y) internal pure returns (int256 z) {
        z = int256(x) - int256(y);
        require(int256(x) >= 0 && int256(y) >= 0, "TaxCollector/ded-invalid-numbers");
    }
    function multiply(uint256 x, int256 y) internal pure returns (int256 z) {
        z = int256(x) * y;
        require(int256(x) >= 0, "TaxCollector/mul-uint-int-invalid-x");
        require(y == 0 || z / y == int256(x), "TaxCollector/mul-uint-int-overflow");
    }
    function multiply(int256 x, int256 y) internal pure returns (int256 z) {
        require(!both(x == -1, y == INT256_MIN), "TaxCollector/mul-int-int-overflow");
        require(y == 0 || (z = x * y) / y == x, "TaxCollector/mul-int-int-invalid");
    }
    function rmultiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y;
        require(y == 0 || z / y == x, "TaxCollector/rmul-overflow");
        z = z / RAY;
    }

    // --- Boolean Logic ---
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
    function initializeCollateralType(bytes32 collateralType) external isAuthorized {
        CollateralType storage collateralType_ = collateralTypes[collateralType];
        require(collateralType_.stabilityFee == 0, "TaxCollector/collateral-type-already-init");
        collateralType_.stabilityFee = RAY;
        collateralType_.updateTime   = now;
        collateralList.push(collateralType);
        emit InitializeCollateralType(collateralType);
    }
    /**
     * @notice Modify collateral specific uint256 params
     * @param collateralType Collateral type who's parameter is modified
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(
        bytes32 collateralType,
        bytes32 parameter,
        uint256 data
    ) external isAuthorized {
        require(now == collateralTypes[collateralType].updateTime, "TaxCollector/update-time-not-now");
        if (parameter == "stabilityFee") collateralTypes[collateralType].stabilityFee = data;
        else revert("TaxCollector/modify-unrecognized-param");
        emit ModifyParameters(
          collateralType,
          parameter,
          data
        );
    }
    /**
     * @notice Modify general uint256 params
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(bytes32 parameter, uint256 data) external isAuthorized {
        if (parameter == "globalStabilityFee") globalStabilityFee = data;
        else if (parameter == "maxSecondaryReceivers") maxSecondaryReceivers = data;
        else revert("TaxCollector/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }
    /**
     * @notice Modify general address params
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(bytes32 parameter, address data) external isAuthorized {
        require(data != address(0), "TaxCollector/null-data");
        if (parameter == "primaryTaxReceiver") primaryTaxReceiver = data;
        else revert("TaxCollector/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
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
    ) external isAuthorized {
        if (both(secondaryReceiverList.isNode(position), secondaryTaxReceivers[collateralType][position].taxPercentage > 0)) {
            secondaryTaxReceivers[collateralType][position].canTakeBackTax = val;
        }
        else revert("TaxCollector/unknown-tax-receiver");
        emit ModifyParameters(
          collateralType,
          position,
          val
        );
    }
    /**
     * @notice Create or modify a secondary tax receiver's data
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
    ) external isAuthorized {
        (!secondaryReceiverList.isNode(position)) ?
          addSecondaryReceiver(collateralType, taxPercentage, receiverAccount) :
          modifySecondaryReceiver(collateralType, position, taxPercentage);
        emit ModifyParameters(
          collateralType,
          position,
          taxPercentage,
          receiverAccount
        );
    }

    // --- Tax Receiver Utils ---
    /**
     * @notice Add a new secondary tax receiver
     * @param collateralType Collateral type that will give SF to the tax receiver
     * @param taxPercentage Percentage of SF offered to the tax receiver
     * @param receiverAccount Tax receiver address
     */
    function addSecondaryReceiver(bytes32 collateralType, uint256 taxPercentage, address receiverAccount) internal {
        require(receiverAccount != address(0), "TaxCollector/null-account");
        require(receiverAccount != primaryTaxReceiver, "TaxCollector/primary-receiver-cannot-be-secondary");
        require(taxPercentage > 0, "TaxCollector/null-sf");
        require(usedSecondaryReceiver[receiverAccount] == 0, "TaxCollector/account-already-used");
        require(addition(secondaryReceiversAmount(), ONE) <= maxSecondaryReceivers, "TaxCollector/exceeds-max-receiver-limit");
        require(addition(secondaryReceiverAllotedTax[collateralType], taxPercentage) < WHOLE_TAX_CUT, "TaxCollector/tax-cut-exceeds-hundred");
        secondaryReceiverNonce                                                       = addition(secondaryReceiverNonce, 1);
        latestSecondaryReceiver                                                      = secondaryReceiverNonce;
        usedSecondaryReceiver[receiverAccount]                                       = ONE;
        secondaryReceiverAllotedTax[collateralType]                                  = addition(secondaryReceiverAllotedTax[collateralType], taxPercentage);
        secondaryTaxReceivers[collateralType][latestSecondaryReceiver].taxPercentage = taxPercentage;
        secondaryReceiverAccounts[latestSecondaryReceiver]                           = receiverAccount;
        secondaryReceiverRevenueSources[receiverAccount]                             = ONE;
        secondaryReceiverList.push(latestSecondaryReceiver, false);
        emit AddSecondaryReceiver(
          collateralType,
          secondaryReceiverNonce,
          latestSecondaryReceiver,
          secondaryReceiverAllotedTax[collateralType],
          secondaryReceiverRevenueSources[receiverAccount]
        );
    }
    /**
     * @notice Update a secondary tax receiver's data (add a new SF source or modify % of SF taken from a collateral type)
     * @param collateralType Collateral type that will give SF to the tax receiver
     * @param position Receiver's position in the tax receiver list
     * @param taxPercentage Percentage of SF offered to the tax receiver (ray%)
     */
    function modifySecondaryReceiver(bytes32 collateralType, uint256 position, uint256 taxPercentage) internal {
        if (taxPercentage == 0) {
          secondaryReceiverAllotedTax[collateralType] = subtract(
            secondaryReceiverAllotedTax[collateralType],
            secondaryTaxReceivers[collateralType][position].taxPercentage
          );

          if (secondaryReceiverRevenueSources[secondaryReceiverAccounts[position]] == 1) {
            if (position == latestSecondaryReceiver) {
              (, uint256 prevReceiver) = secondaryReceiverList.prev(latestSecondaryReceiver);
              latestSecondaryReceiver = prevReceiver;
            }
            secondaryReceiverList.del(position);
            delete(usedSecondaryReceiver[secondaryReceiverAccounts[position]]);
            delete(secondaryTaxReceivers[collateralType][position]);
            delete(secondaryReceiverRevenueSources[secondaryReceiverAccounts[position]]);
            delete(secondaryReceiverAccounts[position]);
          } else if (secondaryTaxReceivers[collateralType][position].taxPercentage > 0) {
            secondaryReceiverRevenueSources[secondaryReceiverAccounts[position]] = subtract(secondaryReceiverRevenueSources[secondaryReceiverAccounts[position]], 1);
            delete(secondaryTaxReceivers[collateralType][position]);
          }
        } else {
          uint256 secondaryReceiverAllotedTax_ = addition(
            subtract(secondaryReceiverAllotedTax[collateralType], secondaryTaxReceivers[collateralType][position].taxPercentage),
            taxPercentage
          );
          require(secondaryReceiverAllotedTax_ < WHOLE_TAX_CUT, "TaxCollector/tax-cut-too-big");
          if (secondaryTaxReceivers[collateralType][position].taxPercentage == 0) {
            secondaryReceiverRevenueSources[secondaryReceiverAccounts[position]] = addition(
              secondaryReceiverRevenueSources[secondaryReceiverAccounts[position]],
              1
            );
          }
          secondaryReceiverAllotedTax[collateralType]                   = secondaryReceiverAllotedTax_;
          secondaryTaxReceivers[collateralType][position].taxPercentage = taxPercentage;
        }
        emit ModifySecondaryReceiver(
          collateralType,
          secondaryReceiverNonce,
          latestSecondaryReceiver,
          secondaryReceiverAllotedTax[collateralType],
          secondaryReceiverRevenueSources[secondaryReceiverAccounts[position]]
        );
    }

    // --- Tax Collection Utils ---
    /**
     * @notice Check if multiple collateral types are up to date with taxation
     */
    function collectedManyTax(uint256 start, uint256 end) public view returns (bool ok) {
        require(both(start <= end, end < collateralList.length), "TaxCollector/invalid-indexes");
        for (uint256 i = start; i <= end; i++) {
          if (now > collateralTypes[collateralList[i]].updateTime) {
            ok = false;
            return ok;
          }
        }
        ok = true;
    }
    /**
     * @notice Check how much SF will be charged (to collateral types between indexes 'start' and 'end'
     *         in the collateralList) during the next taxation
     * @param start Index in collateralList from which to start looping and calculating the tax outcome
     * @param end Index in collateralList at which we stop looping and calculating the tax outcome
     */
    function taxManyOutcome(uint256 start, uint256 end) public view returns (bool ok, int256 rad) {
        require(both(start <= end, end < collateralList.length), "TaxCollector/invalid-indexes");
        int256  primaryReceiverBalance = -int256(safeEngine.coinBalance(primaryTaxReceiver));
        int256  deltaRate;
        uint256 debtAmount;
        for (uint256 i = start; i <= end; i++) {
          if (now > collateralTypes[collateralList[i]].updateTime) {
            (debtAmount, ) = safeEngine.collateralTypes(collateralList[i]);
            (, deltaRate)  = taxSingleOutcome(collateralList[i]);
            rad = addition(rad, multiply(debtAmount, deltaRate));
          }
        }
        if (rad < 0) {
          ok = (rad < primaryReceiverBalance) ? false : true;
        } else {
          ok = true;
        }
    }
    /**
     * @notice Get how much SF will be distributed after taxing a specific collateral type
     * @param collateralType Collateral type to compute the taxation outcome for
     * @return The newly accumulated rate as well as the delta between the new and the last accumulated rates
     */
    function taxSingleOutcome(bytes32 collateralType) public view returns (uint256, int256) {
        (, uint256 lastAccumulatedRate) = safeEngine.collateralTypes(collateralType);
        uint256 newlyAccumulatedRate =
          rmultiply(
            rpow(
              addition(
                globalStabilityFee,
                collateralTypes[collateralType].stabilityFee
              ),
              subtract(
                now,
                collateralTypes[collateralType].updateTime
              ),
            RAY),
          lastAccumulatedRate);
        return (newlyAccumulatedRate, deduct(newlyAccumulatedRate, lastAccumulatedRate));
    }

    // --- Tax Receiver Utils ---
    /**
     * @notice Get the secondary tax receiver list length
     */
    function secondaryReceiversAmount() public view returns (uint256) {
        return secondaryReceiverList.range();
    }
    /**
     * @notice Get the collateralList length
     */
    function collateralListLength() public view returns (uint256) {
        return collateralList.length;
    }
    /**
     * @notice Check if a tax receiver is at a certain position in the list
     */
    function isSecondaryReceiver(uint256 _receiver) public view returns (bool) {
        if (_receiver == 0) return false;
        return secondaryReceiverList.isNode(_receiver);
    }

    // --- Tax (Stability Fee) Collection ---
    /**
     * @notice Collect tax from multiple collateral types at once
     * @param start Index in collateralList from which to start looping and calculating the tax outcome
     * @param end Index in collateralList at which we stop looping and calculating the tax outcome
     */
    function taxMany(uint256 start, uint256 end) external {
        require(both(start <= end, end < collateralList.length), "TaxCollector/invalid-indexes");
        for (uint256 i = start; i <= end; i++) {
            taxSingle(collateralList[i]);
        }
    }
    /**
     * @notice Collect tax from a single collateral type
     * @param collateralType Collateral type to tax
     */
    function taxSingle(bytes32 collateralType) public returns (uint256) {
        uint256 latestAccumulatedRate;
        if (now <= collateralTypes[collateralType].updateTime) {
          (, latestAccumulatedRate) = safeEngine.collateralTypes(collateralType);
          return latestAccumulatedRate;
        }
        (, int256 deltaRate) = taxSingleOutcome(collateralType);
        // Check how much debt has been generated for collateralType
        (uint256 debtAmount, ) = safeEngine.collateralTypes(collateralType);
        splitTaxIncome(collateralType, debtAmount, deltaRate);
        (, latestAccumulatedRate) = safeEngine.collateralTypes(collateralType);
        collateralTypes[collateralType].updateTime = now;
        emit CollectTax(collateralType, latestAccumulatedRate, deltaRate);
        return latestAccumulatedRate;
    }
    /**
     * @notice Split SF between all tax receivers
     * @param collateralType Collateral type to distribute SF for
     * @param deltaRate Difference between the last and the latest accumulate rates for the collateralType
     */
    function splitTaxIncome(bytes32 collateralType, uint256 debtAmount, int256 deltaRate) internal {
        // Start looping from the latest tax receiver
        uint256 currentSecondaryReceiver = latestSecondaryReceiver;
        // While we still haven't gone through the entire tax receiver list
        while (currentSecondaryReceiver > 0) {
          // If the current tax receiver should receive SF from collateralType
          if (secondaryTaxReceivers[collateralType][currentSecondaryReceiver].taxPercentage > 0) {
            distributeTax(
              collateralType,
              secondaryReceiverAccounts[currentSecondaryReceiver],
              currentSecondaryReceiver,
              debtAmount,
              deltaRate
            );
          }
          // Continue looping
          (, currentSecondaryReceiver) = secondaryReceiverList.prev(currentSecondaryReceiver);
        }
        // Distribute to primary receiver
        distributeTax(collateralType, primaryTaxReceiver, uint256(-1), debtAmount, deltaRate);
    }

    /**
     * @notice Give/withdraw SF from a tax receiver
     * @param collateralType Collateral type to distribute SF for
     * @param receiver Tax receiver address
     * @param receiverListPosition Position of receiver in the secondaryReceiverList (if the receiver is secondary)
     * @param debtAmount Total debt currently issued
     * @param deltaRate Difference between the latest and the last accumulated rates for the collateralType
     */
    function distributeTax(
        bytes32 collateralType,
        address receiver,
        uint256 receiverListPosition,
        uint256 debtAmount,
        int256 deltaRate
    ) internal {
        require(safeEngine.coinBalance(receiver) < 2**255, "TaxCollector/coin-balance-does-not-fit-into-int256");
        // Check how many coins the receiver has and negate the value
        int256 coinBalance   = -int256(safeEngine.coinBalance(receiver));
        // Compute the % out of SF that should be allocated to the receiver
        int256 currentTaxCut = (receiver == primaryTaxReceiver) ?
          multiply(subtract(WHOLE_TAX_CUT, secondaryReceiverAllotedTax[collateralType]), deltaRate) / int256(WHOLE_TAX_CUT) :
          multiply(int256(secondaryTaxReceivers[collateralType][receiverListPosition].taxPercentage), deltaRate) / int256(WHOLE_TAX_CUT);
        /**
            If SF is negative and a tax receiver doesn't have enough coins to absorb the loss,
            compute a new tax cut that can be absorbed
        **/
        currentTaxCut  = (
          both(multiply(debtAmount, currentTaxCut) < 0, coinBalance > multiply(debtAmount, currentTaxCut))
        ) ? coinBalance / int256(debtAmount) : currentTaxCut;
        /**
          If the tax receiver's tax cut is not null and if the receiver accepts negative SF
          offer/take SF to/from them
        **/
        if (currentTaxCut != 0) {
          if (
            either(
              receiver == primaryTaxReceiver,
              either(
                deltaRate >= 0,
                both(currentTaxCut < 0, secondaryTaxReceivers[collateralType][receiverListPosition].canTakeBackTax > 0)
              )
            )
          ) {
            safeEngine.updateAccumulatedRate(collateralType, receiver, currentTaxCut);
            emit DistributeTax(collateralType, receiver, currentTaxCut);
          }
       }
    }
}
