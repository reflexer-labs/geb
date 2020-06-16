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
    struct TaxBucket {
        // Whether this bucket can accept a negative rate (taking SF from it)
        uint256 canTakeBackTax;
        // Percentage of SF allocated to this bucket
        uint256 taxPercentage;
    }

    // Data about each collateral type
    mapping (bytes32 => CollateralType)                public collateralTypes;
    // Percentage of each collateral's SF that goes to other addresses apart from AccountingEngine
    mapping (bytes32 => uint)                          public bucketTaxCut;
    // Whether an address is already used for a bucket
    mapping (address => uint256)                       public usedBucket;
    // Address associated for each bucket index
    mapping (uint256 => address)                       public bucketAccounts;
    // How many collateral types send SF to a specific bucket
    mapping (address => uint256)                       public bucketRevenueSources;
    // Bucket data
    mapping (bytes32 => mapping(uint256 => TaxBucket)) public buckets;

    address    public accountingEngine;
    // Base stability fee charged by all collateral types
    uint256    public globalStabilityFee;
    uint256    public bucketNonce;
    // How many buckets a collateral type can have
    uint256    public maxBuckets;
    // Latest bucket that still has at least one revenue source
    uint256    public latestBucket;

    // All collateral types
    bytes32[]        public   collateralList;
    // Linked list with bucket data
    LinkedList.List  internal bucketList;

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
        else if (parameter == "maxBuckets") maxBuckets = data;
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
     * @notice Set whether a bucket can incur negative fees
     * @param collateralType Collateral type giving fees to the bucket
     * @param position Bucket position in the bucket list
     * @param val Value that specifies whether a bucket can incur negative rates
     */
    function modifyParameters(
        bytes32 collateralType,
        uint256 position,
        uint256 val
    ) external emitLog isAuthorized {
        if (both(bucketList.isNode(position), buckets[collateralType][position].taxPercentage > 0)) {
            buckets[collateralType][position].canTakeBackTax = val;
        }
        else revert("TaxCollector/unknown-bucket");
    }
    /**
     * @notice Create or modify a bucket's data
     * @param collateralType Collateral type that will give SF to the bucket
     * @param position Bucket position in the bucket list. Used to determine whether a new bucket is
              created or an existing one is edited
     * @param taxPercentage Percentage of SF offered to the bucket
     * @param bucketAccount Bucket address
     */
    function modifyParameters(
      bytes32 collateralType,
      uint256 position,
      uint256 taxPercentage,
      address bucketAccount
    ) external emitLog isAuthorized {
        (!bucketList.isNode(position)) ?
          createBucket(collateralType, taxPercentage, bucketAccount) :
          fixBucket(collateralType, position, taxPercentage);
    }

    // --- Bucket Utils ---
    /**
     * @notice Create a new bucket
     * @param collateralType Collateral type that will give SF to the bucket
     * @param taxPercentage Percentage of SF offered to the bucket
     * @param bucketAccount Bucket address
     */
    function createBucket(bytes32 collateralType, uint256 taxPercentage, address bucketAccount) internal {
        require(bucketAccount != address(0), "TaxCollector/null-account");
        require(bucketAccount != accountingEngine, "TaxCollector/accounting-engine-cannot-be-bucket");
        require(taxPercentage > 0, "TaxCollector/null-sf");
        require(usedBucket[bucketAccount] == 0, "TaxCollector/account-already-used");
        require(add(bucketListLength(), ONE) <= maxBuckets, "TaxCollector/exceeds-max-buckets");
        require(add(bucketTaxCut[collateralType], taxPercentage) < HUNDRED, "TaxCollector/tax-cut-exceeds-hundred");
        bucketNonce                                         = add(bucketNonce, 1);
        latestBucket                                        = bucketNonce;
        usedBucket[bucketAccount]                           = ONE;
        bucketTaxCut[collateralType]                        = add(bucketTaxCut[collateralType], taxPercentage);
        buckets[collateralType][latestBucket].taxPercentage = taxPercentage;
        bucketAccounts[latestBucket]                        = bucketAccount;
        bucketRevenueSources[bucketAccount]                 = ONE;
        bucketList.push(latestBucket, false);
    }
    /**
     * @notice Update a bucket's data (add a new SF source or modify % of SF taken from a collateral type)
     * @param collateralType Collateral type that will give SF to the bucket
     * @param position Bucket's position in the bucket list
     * @param taxPercentage Percentage of SF offered to the bucket
     */
    function fixBucket(bytes32 collateralType, uint256 position, uint256 taxPercentage) internal {
        if (taxPercentage == 0) {
          bucketTaxCut[collateralType] = sub(
            bucketTaxCut[collateralType],
            buckets[collateralType][position].taxPercentage
          );

          if (bucketRevenueSources[bucketAccounts[position]] == 1) {
            if (position == latestBucket) {
              (, uint256 prevBucket) = bucketList.prev(latestBucket);
              latestBucket = prevBucket;
            }
            bucketList.del(position);
            delete(usedBucket[bucketAccounts[position]]);
            delete(buckets[collateralType][position]);
            delete(bucketRevenueSources[bucketAccounts[position]]);
            delete(bucketAccounts[position]);
          } else if (buckets[collateralType][position].taxPercentage > 0) {
            bucketRevenueSources[bucketAccounts[position]] = sub(bucketRevenueSources[bucketAccounts[position]], 1);
            delete(buckets[collateralType][position]);
          }
        } else {
          uint256 bucketTaxCut_ = add(
            sub(bucketTaxCut[collateralType], buckets[collateralType][position].taxPercentage),
            taxPercentage
          );
          require(bucketTaxCut_ < HUNDRED, "TaxCollector/tax-cut-too-big");
          if (buckets[collateralType][position].taxPercentage == 0) {
            bucketRevenueSources[bucketAccounts[position]] = add(
              bucketRevenueSources[bucketAccounts[position]],
              1
            );
          }
          bucketTaxCut[collateralType]                    = bucketTaxCut_;
          buckets[collateralType][position].taxPercentage = taxPercentage;
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
     * @notice Get the bucket list length
     */
    function bucketListLength() public view returns (uint) {
        return bucketList.range();
    }
    /**
     * @notice Check if a bucket is at a certain position in the list
     */
    function isBucket(uint256 _bucket) public view returns (bool) {
        return bucketList.isNode(_bucket);
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
     * @notice Distribute SF to tax buckets and to the AccountingEngine
     * @param collateralType Collateral type to distribute SF for
     * @param deltaRate Difference between the last and the latest accumulate rates for the collateralType
     */
    function splitTaxIncome(bytes32 collateralType, int deltaRate) internal {
        // Check how much debt has been generated for collateralType
        (uint debtAmount, ) = cdpEngine.collateralTypes(collateralType);
        // Start looping from the latest bucket
        uint256 currentBucket = latestBucket;
        int256  currentTaxCut;
        int256  coinBalance;
        // While we still haven't gone through the entire bucket list
        while (currentBucket > 0) {
          // If the current bucket should receive SF from collateralType
          if (buckets[collateralType][currentBucket].taxPercentage > 0) {
            // Check how many coins are in the bucket and negate the value
            coinBalance    = -int(cdpEngine.coinBalance(bucketAccounts[currentBucket]));
            // Compute the % out of deltaRate that should be allocated to the current bucket
            currentTaxCut  = mul(int(buckets[collateralType][currentBucket].taxPercentage), deltaRate) / int(HUNDRED);
            /**
                If SF is negative and the bucket doesn't have enough coins to absorb the loss,
                compute a new tax cut that can be absorbed
            **/
            currentTaxCut  = (
              both(mul(debtAmount, currentTaxCut) < 0, coinBalance > mul(debtAmount, currentTaxCut))
            ) ? coinBalance / int(debtAmount) : currentTaxCut;
            /**
              If the bucket's tax cut is not null and if the bucket accepts negative SF
              (in case currentTaxCut is negative), offer/subtract SF from the bucket
            **/
            if (
              both(
                currentTaxCut != 0,
                either(
                  deltaRate >= 0,
                  both(currentTaxCut < 0, buckets[collateralType][currentBucket].canTakeBackTax > 0)
                )
              )
            ) {
              cdpEngine.updateAccumulatedRate(collateralType, bucketAccounts[currentBucket], currentTaxCut);
              emit UpdatedAccumulatedRate(collateralType, bucketAccounts[currentBucket], currentTaxCut);
            }
          }
          // Continue looping
          (, currentBucket) = bucketList.prev(currentBucket);
        }
        // Repeat the exact process for AccountingEngine but do not check if it accepts negative rates
        coinBalance = -int(cdpEngine.coinBalance(accountingEngine));
        currentTaxCut  = mul(sub(HUNDRED, bucketTaxCut[collateralType]), deltaRate) / int(HUNDRED);
        currentTaxCut  = (
          both(mul(debtAmount, currentTaxCut) < 0, coinBalance > mul(debtAmount, currentTaxCut))
        ) ? coinBalance / int(debtAmount) : currentTaxCut;
        if (currentTaxCut != 0) {
          cdpEngine.updateAccumulatedRate(collateralType, accountingEngine, currentTaxCut);
          emit UpdatedAccumulatedRate(collateralType, accountingEngine, currentTaxCut);
        }
    }
}
