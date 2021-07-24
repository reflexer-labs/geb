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

import "../shared/LinkedList.sol";

abstract contract SAFEEngineLike {
    function collateralTypes(bytes32,bytes32) virtual public view returns (
        uint256 debtAmount,       // [wad]
        uint256 accumulatedRate   // [ray]
    );
    function updateAccumulatedRate(bytes32,bytes32,address,int256) virtual external;
    function coinBalance(bytes32,address) virtual public view returns (uint256);
}

contract MultiTaxCollector {
    using LinkedList for LinkedList.List;

    // --- Auth ---
    mapping (bytes32 => mapping(address => uint256)) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(bytes32 coinName, address account) external isAuthorized(coinName) {
        authorizedAccounts[coinName][account] = 1;
        emit AddAuthorization(coinName, account);
    }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(bytes32 coinName, address account) external isAuthorized(coinName) {
        authorizedAccounts[coinName][account] = 0;
        emit RemoveAuthorization(coinName, account);
    }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized(bytes32 coinName) {
        require(authorizedAccounts[coinName][msg.sender] == 1, "MultiTaxCollector/account-not-authorized");
        _;
    }

    /**
     * @notice Checks whether a coin is initialized
     */
    modifier coinIsInitialized(bytes32 coinName) {
        require(coinInitialized[coinName] == 1, "MultiTaxCollector/coin-not-init");

        _;
    }

    // --- Events ---
    event AddAuthorization(bytes32 indexed coinName, address account);
    event RemoveAuthorization(bytes32 indexed coinName, address account);
    event InitializeCollateralType(bytes32 indexed coinName, bytes32 collateralType);
    event ModifyParameters(
      bytes32 indexed coinName,
      bytes32 collateralType,
      bytes32 parameter,
      uint256 data
    );
    event ModifyParameters(bytes32 indexed coinName, bytes32 parameter, uint256 data);
    event ModifyParameters(bytes32 parameter, address data);
    event ModifyParameters(
      bytes32 indexed coinName,
      bytes32 collateralType,
      uint256 position,
      uint256 val
    );
    event ModifyParameters(
      bytes32 indexed coinName,
      bytes32 collateralType,
      uint256 position,
      uint256 taxPercentage,
      address receiverAccount
    );
    event AddSecondaryReceiver(
      bytes32 indexed coinName,
      bytes32 indexed collateralType,
      uint256 secondaryReceiverNonce,
      uint256 latestSecondaryReceiver,
      uint256 secondaryReceiverAllotedTax,
      uint256 secondaryReceiverRevenueSources
    );
    event ModifySecondaryReceiver(
      bytes32 indexed coinName,
      bytes32 indexed collateralType,
      uint256 secondaryReceiverNonce,
      uint256 latestSecondaryReceiver,
      uint256 secondaryReceiverAllotedTax,
      uint256 secondaryReceiverRevenueSources
    );
    event CollectTax(bytes32 indexed coinName, bytes32 indexed collateralType, uint256 latestAccumulatedRate, int256 deltaRate);
    event DistributeTax(bytes32 indexed coinName, bytes32 indexed collateralType, address indexed target, int256 taxCut);
    event InitializeCoin(bytes32 indexed coinName);

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
    mapping (bytes32 => mapping(bytes32 => CollateralType))                  public collateralTypes;
    // Percentage of each collateral's SF that goes to other addresses apart from the primary receiver
    mapping (bytes32 => mapping(bytes32 => uint256))                         public secondaryReceiverAllotedTax; // [%ray]
    // Whether an address is already used for a tax receiver
    mapping (bytes32 => mapping(address => uint256))                         public usedSecondaryReceiver;       // [bool]
    // Address associated to each tax receiver index
    mapping (bytes32 => mapping(uint256 => address))                         public secondaryReceiverAccounts;
    // How many collateral types send SF to a specific tax receiver
    mapping (bytes32 => mapping(address => uint256))                         public secondaryReceiverRevenueSources;
    // Tax receiver data
    mapping (bytes32 => mapping(bytes32 => mapping(uint256 => TaxReceiver))) public secondaryTaxReceivers;

    // Base stability fee charged to all collateral types
    mapping(bytes32 => uint256) public globalStabilityFee;                      // [ray%]
    // Number of secondary tax receivers ever added
    mapping(bytes32 => uint256) public secondaryReceiverNonce;
    // Max number of secondarytax receivers a collateral type can have
    mapping(bytes32 => uint256) public maxSecondaryReceivers;
    // Latest secondary tax receiver that still has at least one revenue source
    mapping(bytes32 => uint256) public latestSecondaryReceiver;

    // Whether a coin has been initialized or not
    mapping (bytes32 => uint256)        public coinInitialized;

    // All collateral types
    mapping(bytes32 => bytes32[])       public collateralList;
    // Linked list with tax receiver data
    mapping(bytes32 => LinkedList.List) internal secondaryReceiverList;

    // Portion of tax that goes to the core receiver
    uint256        public coreReceiverTaxCut;
    // Manager address
    address        public manager;
    // Address of the deployer
    address        public deployer;
    // The address that always receives some SF
    address        public primaryTaxReceiver;
    // The core receiver that gets a portion of all (positive) tax
    address        public coreReceiver;
    // SAFE database
    SAFEEngineLike public safeEngine;

    // --- Init ---
    constructor(address safeEngine_, address coreReceiver_, uint256 coreReceiverTaxCut_) public {
        require(both(coreReceiverTaxCut_ > 0, coreReceiverTaxCut_ < WHOLE_TAX_CUT - 1), "MultiTaxCollector/invalid-core-receiver-cut");
        require(coreReceiver_ != address(0), "MultiTaxCollector/null-core-receiver");
        manager            = msg.sender;
        deployer           = msg.sender;
        coreReceiver       = coreReceiver_;
        coreReceiverTaxCut = coreReceiverTaxCut_;
        safeEngine         = SAFEEngineLike(safeEngine_);
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
        require(z >= x, "MultiTaxCollector/add-uint-uint-overflow");
    }
    function addition(int256 x, int256 y) internal pure returns (int256 z) {
        z = x + y;
        if (y <= 0) require(z <= x, "MultiTaxCollector/add-int-int-underflow");
        if (y  > 0) require(z > x, "MultiTaxCollector/add-int-int-overflow");
    }
    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "MultiTaxCollector/sub-uint-uint-underflow");
    }
    function subtract(int256 x, int256 y) internal pure returns (int256 z) {
        z = x - y;
        require(y <= 0 || z <= x, "MultiTaxCollector/sub-int-int-underflow");
        require(y >= 0 || z >= x, "MultiTaxCollector/sub-int-int-overflow");
    }
    function deduct(uint256 x, uint256 y) internal pure returns (int256 z) {
        z = int256(x) - int256(y);
        require(int256(x) >= 0 && int256(y) >= 0, "MultiTaxCollector/ded-invalid-numbers");
    }
    function multiply(uint256 x, int256 y) internal pure returns (int256 z) {
        z = int256(x) * y;
        require(int256(x) >= 0, "MultiTaxCollector/mul-uint-int-invalid-x");
        require(y == 0 || z / y == int256(x), "MultiTaxCollector/mul-uint-int-overflow");
    }
    function multiply(int256 x, int256 y) internal pure returns (int256 z) {
        require(!both(x == -1, y == INT256_MIN), "MultiTaxCollector/mul-int-int-overflow");
        require(y == 0 || (z = x * y) / y == x, "MultiTaxCollector/mul-int-int-invalid");
    }
    function rmultiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y;
        require(y == 0 || z / y == x, "MultiTaxCollector/rmul-overflow");
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
     * @notice Initialize a new coin
     * @param coinName The name of the coin to initialize
     */
    function initializeCoin(bytes32 coinName) external {
        require(deployer == msg.sender, "MultiTaxCollector/caller-not-deployer");
        require(coinInitialized[coinName] == 0, "MultiTaxCollector/already-init");

        authorizedAccounts[coinName][msg.sender] = 1;
        coinInitialized[coinName]                = 1;

        emit InitializeCoin(coinName);
        emit AddAuthorization(coinName, msg.sender);
    }
    /**
     * @notice Initialize a brand new collateral type for a specific coin
     * @param coinName The name of the coin to initialize the collateral for
     * @param collateralType Collateral type name (e.g ETH-A, TBTC-B)
     */
    function initializeCollateralType(bytes32 coinName, bytes32 collateralType) external isAuthorized(coinName) {
        CollateralType storage collateralType_ = collateralTypes[coinName][collateralType];
        require(collateralType_.stabilityFee == 0, "MultiTaxCollector/collateral-type-already-init");
        collateralType_.stabilityFee = RAY;
        collateralType_.updateTime   = now;
        collateralList[coinName].push(collateralType);
        emit InitializeCollateralType(coinName, collateralType);
    }
    /**
     * @notice Modify collateral specific uint256 params
     * @param coinName The name of the coin
     * @param collateralType Collateral type who's parameter is modified
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(
        bytes32 coinName,
        bytes32 collateralType,
        bytes32 parameter,
        uint256 data
    ) external isAuthorized(coinName) {
        require(now == collateralTypes[coinName][collateralType].updateTime, "MultiTaxCollector/update-time-not-now");
        if (parameter == "stabilityFee") collateralTypes[coinName][collateralType].stabilityFee = data;
        else if (parameter == "updateTime") {
          require(both(data >= collateralTypes[coinName][collateralType].updateTime, data <= now), "MultiTaxCollector/invalid-update-time");
          collateralTypes[coinName][collateralType].updateTime = data;
        }
        else revert("MultiTaxCollector/modify-unrecognized-param");
        emit ModifyParameters(
          coinName,
          collateralType,
          parameter,
          data
        );
    }
    /**
     * @notice Modify general uint256 params
     * @param coinName The name of the coin
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(bytes32 coinName, bytes32 parameter, uint256 data) external isAuthorized(coinName) {
        if (parameter == "globalStabilityFee") globalStabilityFee[coinName] = data;
        else if (parameter == "maxSecondaryReceivers") maxSecondaryReceivers[coinName] = data;
        else revert("MultiTaxCollector/modify-unrecognized-param");
        emit ModifyParameters(coinName, parameter, data);
    }
    /**
     * @notice Modify general address params
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(bytes32 parameter, address data) external {
        require(manager == msg.sender, "MultiTaxCollector/invalid-manager");
        if (parameter == "primaryTaxReceiver") {
          require(data != address(0), "MultiTaxCollector/null-primary-tax-receiver");
          primaryTaxReceiver = data;
        } else if (parameter == "manager") {
          manager = data;
        } else if (parameter == "deployer") {
          require(data != address(0), "MultiTaxCollector/null-deployer");
          deployer = data;
        } else if (parameter == "coreReceiver") {
          require(data != address(0), "MultiTaxCollector/null-core-receiver");
          coreReceiver = data;
        }
        else revert("MultiTaxCollector/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }
    /**
     * @notice Set whether a tax receiver can incur negative fees
     * @param coinName The name of the coin
     * @param collateralType Collateral type giving fees to the tax receiver
     * @param position Receiver position in the list
     * @param val Value that specifies whether a tax receiver can incur negative rates
     */
    function modifyParameters(
        bytes32 coinName,
        bytes32 collateralType,
        uint256 position,
        uint256 val
    ) external isAuthorized(coinName) {
        if (both(
          secondaryReceiverList[coinName].isNode(position),
          secondaryTaxReceivers[coinName][collateralType][position].taxPercentage > 0
        )) {
          secondaryTaxReceivers[coinName][collateralType][position].canTakeBackTax = val;
        }
        else revert("MultiTaxCollector/unknown-tax-receiver");
        emit ModifyParameters(
          coinName,
          collateralType,
          position,
          val
        );
    }
    /**
     * @notice Create or modify a secondary tax receiver's data
     * @param coinName The name of the coin
     * @param collateralType Collateral type that will give SF to the tax receiver
     * @param position Receiver position in the list. Used to determine whether a new tax receiver is
              created or an existing one is edited
     * @param taxPercentage Percentage of SF offered to the tax receiver
     * @param receiverAccount Receiver address
     */
    function modifyParameters(
      bytes32 coinName,
      bytes32 collateralType,
      uint256 position,
      uint256 taxPercentage,
      address receiverAccount
    ) external isAuthorized(coinName) {
        (!secondaryReceiverList[coinName].isNode(position)) ?
          addSecondaryReceiver(coinName, collateralType, taxPercentage, receiverAccount) :
          modifySecondaryReceiver(coinName, collateralType, position, taxPercentage);
        emit ModifyParameters(
          coinName,
          collateralType,
          position,
          taxPercentage,
          receiverAccount
        );
    }

    // --- Tax Receiver Utils ---
    /**
     * @notice Add a new secondary tax receiver
     * @param coinName The name of the coin
     * @param collateralType Collateral type that will give SF to the tax receiver
     * @param taxPercentage Percentage of SF offered to the tax receiver
     * @param receiverAccount Tax receiver address
     */
    function addSecondaryReceiver(
      bytes32 coinName, bytes32 collateralType, uint256 taxPercentage, address receiverAccount
    ) internal coinIsInitialized(coinName) {
        require(receiverAccount != address(0), "MultiTaxCollector/null-account");
        require(receiverAccount != primaryTaxReceiver, "MultiTaxCollector/primary-receiver-cannot-be-secondary");
        require(receiverAccount != coreReceiver, "MultiTaxCollector/primary-receiver-cannot-be-core-receiver");
        require(taxPercentage > 0, "MultiTaxCollector/null-sf");
        require(usedSecondaryReceiver[coinName][receiverAccount] == 0, "MultiTaxCollector/account-already-used");
        require(addition(secondaryReceiversAmount(coinName), ONE) <= maxSecondaryReceivers[coinName], "MultiTaxCollector/exceeds-max-receiver-limit");
        require(
          addition(coreReceiverTaxCut, addition(secondaryReceiverAllotedTax[coinName][collateralType], taxPercentage)) < WHOLE_TAX_CUT,
          "MultiTaxCollector/tax-cut-exceeds-hundred"
        );

        secondaryReceiverNonce[coinName]                                                                 = addition(secondaryReceiverNonce[coinName], 1);
        latestSecondaryReceiver[coinName]                                                                = secondaryReceiverNonce[coinName];
        usedSecondaryReceiver[coinName][receiverAccount]                                                 = ONE;
        secondaryReceiverAllotedTax[coinName][collateralType]                                            = addition(secondaryReceiverAllotedTax[coinName][collateralType], taxPercentage);
        secondaryTaxReceivers[coinName][collateralType][latestSecondaryReceiver[coinName]].taxPercentage = taxPercentage;
        secondaryReceiverAccounts[coinName][latestSecondaryReceiver[coinName]]                           = receiverAccount;
        secondaryReceiverRevenueSources[coinName][receiverAccount]                                       = ONE;
        secondaryReceiverList[coinName].push(latestSecondaryReceiver[coinName], false);
        emit AddSecondaryReceiver(
          coinName,
          collateralType,
          secondaryReceiverNonce[coinName],
          latestSecondaryReceiver[coinName],
          secondaryReceiverAllotedTax[coinName][collateralType],
          secondaryReceiverRevenueSources[coinName][receiverAccount]
        );
    }
    /**
     * @notice Update a secondary tax receiver's data (add a new SF source or modify % of SF taken from a collateral type)
     * @param coinName The name of the coin
     * @param collateralType Collateral type that will give SF to the tax receiver
     * @param position Receiver's position in the tax receiver list
     * @param taxPercentage Percentage of SF offered to the tax receiver (ray%)
     */
    function modifySecondaryReceiver(bytes32 coinName, bytes32 collateralType, uint256 position, uint256 taxPercentage)
      internal coinIsInitialized(coinName) {
        if (taxPercentage == 0) {
          secondaryReceiverAllotedTax[coinName][collateralType] = subtract(
            secondaryReceiverAllotedTax[coinName][collateralType],
            secondaryTaxReceivers[coinName][collateralType][position].taxPercentage
          );

          if (secondaryReceiverRevenueSources[coinName][secondaryReceiverAccounts[coinName][position]] == 1) {
            if (position == latestSecondaryReceiver[coinName]) {
              (, uint256 prevReceiver) = secondaryReceiverList[coinName].prev(latestSecondaryReceiver[coinName]);
              latestSecondaryReceiver[coinName] = prevReceiver;
            }
            secondaryReceiverList[coinName].del(position);
            delete(usedSecondaryReceiver[coinName][secondaryReceiverAccounts[coinName][position]]);
            delete(secondaryTaxReceivers[coinName][collateralType][position]);
            delete(secondaryReceiverRevenueSources[coinName][secondaryReceiverAccounts[coinName][position]]);
            delete(secondaryReceiverAccounts[coinName][position]);
          } else if (secondaryTaxReceivers[coinName][collateralType][position].taxPercentage > 0) {
            secondaryReceiverRevenueSources[coinName][secondaryReceiverAccounts[coinName][position]] =
              subtract(secondaryReceiverRevenueSources[coinName][secondaryReceiverAccounts[coinName][position]], 1);
            delete(secondaryTaxReceivers[coinName][collateralType][position]);
          }
        } else {
          uint256 secondaryReceiverAllotedTax_ = addition(
            subtract(secondaryReceiverAllotedTax[coinName][collateralType], secondaryTaxReceivers[coinName][collateralType][position].taxPercentage),
            taxPercentage
          );
          require(addition(coreReceiverTaxCut, secondaryReceiverAllotedTax_) < WHOLE_TAX_CUT, "MultiTaxCollector/tax-cut-too-big");
          if (secondaryTaxReceivers[coinName][collateralType][position].taxPercentage == 0) {
            secondaryReceiverRevenueSources[coinName][secondaryReceiverAccounts[coinName][position]] = addition(
              secondaryReceiverRevenueSources[coinName][secondaryReceiverAccounts[coinName][position]],
              1
            );
          }
          secondaryReceiverAllotedTax[coinName][collateralType]                   = secondaryReceiverAllotedTax_;
          secondaryTaxReceivers[coinName][collateralType][position].taxPercentage = taxPercentage;
        }
        emit ModifySecondaryReceiver(
          coinName,
          collateralType,
          secondaryReceiverNonce[coinName],
          latestSecondaryReceiver[coinName],
          secondaryReceiverAllotedTax[coinName][collateralType],
          secondaryReceiverRevenueSources[coinName][secondaryReceiverAccounts[coinName][position]]
        );
    }

    // --- Tax Collection Utils ---
    /**
     * @notice Check if multiple collateral types are up to date with taxation
     * @param coinName The name of the coin
     */
    function collectedManyTax(bytes32 coinName, uint256 start, uint256 end) public view returns (bool ok) {
        require(both(start <= end, end < collateralList[coinName].length), "MultiTaxCollector/invalid-indexes");
        for (uint256 i = start; i <= end; i++) {
          if (now > collateralTypes[coinName][collateralList[coinName][i]].updateTime) {
            ok = false;
            return ok;
          }
        }
        ok = true;
    }
    /**
     * @notice Check how much SF will be charged (to collateral types between indexes 'start' and 'end'
     *         in the collateralList) during the next taxation
     * @param coinName The name of the coin
     * @param start Index in collateralList from which to start looping and calculating the tax outcome
     * @param end Index in collateralList at which we stop looping and calculating the tax outcome
     */
    function taxManyOutcome(bytes32 coinName, uint256 start, uint256 end) public view returns (bool ok, int256 rad) {
        require(both(start <= end, end < collateralList[coinName].length), "MultiTaxCollector/invalid-indexes");
        int256  primaryReceiverBalance = -int256(safeEngine.coinBalance(coinName, primaryTaxReceiver));
        int256  deltaRate;
        uint256 debtAmount;
        for (uint256 i = start; i <= end; i++) {
          if (now > collateralTypes[coinName][collateralList[coinName][i]].updateTime) {
            (debtAmount, ) = safeEngine.collateralTypes(coinName, collateralList[coinName][i]);
            (, deltaRate)  = taxSingleOutcome(coinName, collateralList[coinName][i]);
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
     * @param coinName The name of the coin
     * @param collateralType Collateral type to compute the taxation outcome for
     * @return The newly accumulated rate as well as the delta between the new and the last accumulated rates
     */
    function taxSingleOutcome(bytes32 coinName, bytes32 collateralType) public view returns (uint256, int256) {
        (, uint256 lastAccumulatedRate) = safeEngine.collateralTypes(coinName, collateralType);
        uint256 newlyAccumulatedRate =
          rmultiply(
            rpow(
              addition(
                uint256(globalStabilityFee[coinName]),
                uint256(collateralTypes[coinName][collateralType].stabilityFee)
              ),
              subtract(
                now,
                collateralTypes[coinName][collateralType].updateTime
              ),
            RAY),
          lastAccumulatedRate);
        return (newlyAccumulatedRate, deduct(newlyAccumulatedRate, lastAccumulatedRate));
    }

    // --- Tax Receiver Utils ---
    /**
     * @notice Get the secondary tax receiver list length
     * @param coinName The name of the coin
     */
    function secondaryReceiversAmount(bytes32 coinName) public view returns (uint256) {
        return secondaryReceiverList[coinName].range();
    }
    /**
     * @notice Get the collateralList length
     * @param coinName The name of the coin
     */
    function collateralListLength(bytes32 coinName) public view returns (uint256) {
        return collateralList[coinName].length;
    }
    /**
     * @notice Check if a tax receiver is at a certain position in the list
     * @param coinName The name of the coin
     */
    function isSecondaryReceiver(bytes32 coinName, uint256 _receiver) public view returns (bool) {
        if (_receiver == 0) return false;
        return secondaryReceiverList[coinName].isNode(_receiver);
    }

    // --- Tax (Stability Fee) Collection ---
    /**
     * @notice Collect tax from multiple collateral types at once
     * @param coinName The name of the coin
     * @param start Index in collateralList from which to start looping and calculating the tax outcome
     * @param end Index in collateralList at which we stop looping and calculating the tax outcome
     */
    function taxMany(bytes32 coinName, uint256 start, uint256 end) external coinIsInitialized(coinName) {
        require(both(start <= end, end < collateralList[coinName].length), "MultiTaxCollector/invalid-indexes");
        for (uint256 i = start; i <= end; i++) {
            taxSingle(coinName, collateralList[coinName][i]);
        }
    }
    /**
     * @notice Collect tax from a single collateral type
     * @param coinName The name of the coin
     * @param collateralType Collateral type to tax
     */
    function taxSingle(bytes32 coinName, bytes32 collateralType) public coinIsInitialized(coinName) returns (uint256) {
        uint256 latestAccumulatedRate;
        if (now <= collateralTypes[coinName][collateralType].updateTime) {
          (, latestAccumulatedRate) = safeEngine.collateralTypes(coinName, collateralType);
          return latestAccumulatedRate;
        }
        (, int256 deltaRate) = taxSingleOutcome(coinName, collateralType);
        // Check how much debt has been generated for collateralType
        (uint256 debtAmount, ) = safeEngine.collateralTypes(coinName, collateralType);
        splitTaxIncome(coinName, collateralType, debtAmount, deltaRate);
        (, latestAccumulatedRate) = safeEngine.collateralTypes(coinName, collateralType);
        collateralTypes[coinName][collateralType].updateTime = now;
        emit CollectTax(coinName, collateralType, latestAccumulatedRate, deltaRate);
        return latestAccumulatedRate;
    }
    /**
     * @notice Split SF between all tax receivers
     * @param coinName The name of the coin
     * @param collateralType Collateral type to distribute SF for
     * @param deltaRate Difference between the last and the latest accumulate rates for the collateralType
     */
    function splitTaxIncome(bytes32 coinName, bytes32 collateralType, uint256 debtAmount, int256 deltaRate) internal {
        // Start looping from the latest tax receiver
        uint256 currentSecondaryReceiver = latestSecondaryReceiver[coinName];
        // While we still haven't gone through the entire tax receiver list
        while (currentSecondaryReceiver > 0) {
          // If the current tax receiver should receive SF from collateralType
          if (secondaryTaxReceivers[coinName][collateralType][currentSecondaryReceiver].taxPercentage > 0) {
            distributeTax(
              coinName,
              collateralType,
              secondaryReceiverAccounts[coinName][currentSecondaryReceiver],
              currentSecondaryReceiver,
              debtAmount,
              deltaRate
            );
          }
          // Continue looping
          (, currentSecondaryReceiver) = secondaryReceiverList[coinName].prev(currentSecondaryReceiver);
        }
        // Distribute to the core receiver
        distributeTax(coinName, collateralType, coreReceiver, uint256(-1) - 1, debtAmount, deltaRate);
        // Distribute to primary receiver
        distributeTax(coinName, collateralType, primaryTaxReceiver, uint256(-1), debtAmount, deltaRate);
    }

    /**
     * @notice Give/withdraw SF from a tax receiver
     * @param coinName The name of the coin
     * @param collateralType Collateral type to distribute SF for
     * @param receiver Tax receiver address
     * @param receiverListPosition Position of receiver in the secondaryReceiverList (if the receiver is secondary)
     * @param debtAmount Total debt currently issued
     * @param deltaRate Difference between the latest and the last accumulated rates for the collateralType
     */
    function distributeTax(
        bytes32 coinName,
        bytes32 collateralType,
        address receiver,
        uint256 receiverListPosition,
        uint256 debtAmount,
        int256 deltaRate
    ) internal {
        require(safeEngine.coinBalance(coinName, receiver) < 2**255, "MultiTaxCollector/coin-balance-does-not-fit-into-int256");
        // Check how many coins the receiver has and negate the value
        int256 coinBalance   = -int256(safeEngine.coinBalance(coinName, receiver));
        // Compute the % out of SF that should be allocated to the receiver
        int256 currentTaxCut;
        if (receiver == primaryTaxReceiver) {
          uint256 deltaAllotedTax = subtract(WHOLE_TAX_CUT, secondaryReceiverAllotedTax[coinName][collateralType]);

          if (deltaRate > 0) {
            deltaAllotedTax = subtract(deltaAllotedTax, coreReceiverTaxCut);
          }

          currentTaxCut = multiply(deltaAllotedTax, deltaRate) / int256(WHOLE_TAX_CUT);
        } else if (receiver == coreReceiver) {
          if (deltaRate < 0) return;
          currentTaxCut = multiply(int256(coreReceiverTaxCut), deltaRate) / int256(WHOLE_TAX_CUT);
        } else {
          currentTaxCut = multiply(int256(secondaryTaxReceivers[coinName][collateralType][receiverListPosition].taxPercentage), deltaRate) / int256(WHOLE_TAX_CUT);
        }
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
          bool validForNegativeRate = both(currentTaxCut < 0, secondaryTaxReceivers[coinName][collateralType][receiverListPosition].canTakeBackTax > 0);

          if (
            either(
              receiver == primaryTaxReceiver,
              either(
                deltaRate >= 0,
                validForNegativeRate
              )
            )
          ) {
            safeEngine.updateAccumulatedRate(coinName, collateralType, receiver, currentTaxCut);
            emit DistributeTax(coinName, collateralType, receiver, currentTaxCut);
          }
       }
    }
}
