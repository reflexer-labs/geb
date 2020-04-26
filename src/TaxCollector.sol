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
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "TaxCollector/account-not-authorized");
        _;
    }

    // --- Data ---
    struct CollateralType {
        uint256 stabilityFee;
        uint256 updateTime;
    }
    struct TaxBucket {
        uint256 canTakeBackTax;
        uint256 taxPercentage;
    }

    mapping (bytes32 => CollateralType)           public collateralTypes;
    mapping (bytes32 => uint)                     public bucketTaxCut;
    mapping (address => uint256)                  public usedBucket;
    mapping (uint256 => address)                  public bucketAccounts;
    mapping (address => uint256)                  public bucketRevenueSources;
    mapping (bytes32 => mapping(uint256 => Heir)) public buckets;

    address    public accountingEngine;
    uint256    public globalStabilityFee;
    uint256    public bucketNonce;
    uint256    public maxBuckets;
    uint256    public latestBucket;

    bytes32[]  public   collateralList;
    Link.List  internal bucketList;

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
    function initializeCollateralType(bytes32 collateralType) external emitLog isAuthorized {
        CollateralType storage collateralType_ = collateralTypes[collateralType];
        require(collateralType_.stabilityFee == 0, "TaxCollector/collateral-type-already-init");
        collateralType_.stabilityFee = RAY;
        collateralType_.updateTime   = now;
        collateralList.push(collateralType);
    }
    function modifyParameters(bytes32 collateralType, bytes32 parameter, uint data) external emitLog isAuthorized {
        require(now == collateralTypes[collateralType].updateTime, "TaxCollector/update-time-not-now");
        if (what == "stabilityFee") collateralTypes[collateralType].stabilityFee = data;
        else revert("TaxCollector/modify-unrecognized-param");
    }
    function modifyParameters(bytes32 parameter, uint data) external emitLog isAuthorized {
        if (what == "globalStabilityFee") globalStabilityFee = data;
        else if (what == "maxBuckets") maxBuckets = data;
        else revert("TaxCollector/modify-unrecognized-param");
    }
    function modifyParameters(bytes32 parameter, address data) external emitLog isAuthorized {
        require(data != address(0), "TaxCollector/null-data");
        if (parameter == "accountingEngine") accountingEngine = data;
        else revert("TaxCollector/modify-unrecognized-param");
    }
    function modifyParameters(bytes32 collateralType, uint256 position, uint256 val) external emitLog isAuthorized {
        if (both(bucketList.isNode(position), buckets[collateralType][position].stabilityFee > 0)) {
            buckets[collateralType][position].canTakeBackTax = val;
        }
        else revert("TaxCollector/unknown-bucket");
    }
    function modifyParameters(
      bytes32 collateralType,
      uint256 position,
      uint256 stabilityFee,
      address bucketAccount
    ) external emitLog isAuthorized {
        (!bucketList.isNode(position)) ?
          createBucket(collateralType, stabilityFee, bucketAccount) : fixBucket(collateralType, position, stabilityFee);
    }

    // --- Bucket Utils ---
    function createBucket(bytes32 collateralType, uint256 stabilityFee, address bucketAccount) internal {
        require(bucketAccount != address(0), "TaxCollector/null-account");
        require(bucketAccount != accountingEngine, "TaxCollector/accounting-engine-cannot-be-bucket");
        require(stabilityFee > 0, "TaxCollector/null-sf");
        require(usedBucket[bucketAccount] == 0, "TaxCollector/account-already-used");
        require(add(bucketListLength(), ONE) <= maxBuckets, "TaxCollector/exceeds-max-buckets");
        require(add(bucketTaxCut[collateralType], stabilityFee) < HUNDRED, "TaxCollector/tax-cut-exceeds-hundred");
        bucketNonce                                         = add(bucketNonce, 1);
        latestBucket                                        = bucketNonce;
        usedBucket[bucketAccount]                           = ONE;
        bucketTaxCut[collateralType]                        = add(bucketTaxCut[collateralType], stabilityFee);
        buckets[collateralType][latestBucket].stabilityFee  = stabilityFee;
        bucketAccounts[latestBucket]                        = bucketAccount;
        bucketRevenueSources[bucketAccount]                 = ONE;
        bucketList.push(latestBucket, false);
    }
    function fixBucket(bytes32 collateralType, uint256 position, uint256 stabilityFee) internal {
        if (stabilityFee == 0) {
          bucketTaxCut[collateralType] = sub(
            bucketTaxCut[collateralType],
            buckets[collateralType][position].stabilityFee
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
          } else if (buckets[ilk][position].stabilityFee > 0) {
            bucketRevenueSources[bucketAccounts[position]] = sub(bucketRevenueSources[bucketAccounts[position]], 1);
            delete(buckets[collateralType][position]);
          }
        } else {
          uint256 bucketTaxCut_ = add(
            sub(bucketTaxCut[collateralType], buckets[collateralType][position].stabilityFee),
            stabilityFee
          );
          require(bucketTaxCut_ < HUNDRED, "TaxCollector/tax-cut-too-big");
          if (buckets[collateralType][position].stabilityFee == 0) {
            bucketRevenueSources[bucketAccounts[position]] = add(
              bucketRevenueSources[bucketAccounts[position]],
              1
            );
          }
          bucketTaxCut[collateralType]                   = bucketTaxCut_;
          buckets[collateralType][position].stabilityFee = stabilityFee;
        }
    }

    // --- Tax Collection Utils ---
    function collectedAllTax() public view returns (bool ko) {
        for (uint i = 0; i < collateralList.length; i++) {
          if (now > collateralTypes[collateralList[i]].updateTime) {
            ko = true;
            break;
          }
        }
    }
    function nextTaxationOutcome() public view returns (bool ok, int rad) {
        int  accountingEngineCoinBalance_ = -int(cdpEngine.coinBalance(accountingEngine));
        int  deltaRate;
        uint debtAmount;
        for (uint i = 0; i < collateralList.length; i++) {
          if (now > collateralType[collateralList[i]].updateTime) {
            (debtAmount, ) = cdpEngine.collateralTypes(collateralList[i]);
            (, deltaRate) = drop(collateralList[i]);
            rad = add(rad, mul(debtAmount, deltaRate));
          }
        }
        if (rad < 0) {
          ok = (rad < accountingEngineCoinBalance_) ? false : true;
        } else {
          ok = true;
        }
    }
    function averageTaxationRate(uint globalStabilityFee_) public view returns (uint256 z) {
        if (collateralList.length == 0) return globalStabilityFee_;
        for (uint i = 0; i < collateralList.length; i++) {
          z = add(z, add(globalStabilityFee_, collateralTypes[collateralList[i]].stabilityFee));
        }
        z = z / collateralList.length;
    }

    // --- Gifts Utils ---
    function bucketListLength() public view returns (uint) {
        return bucketList.range();
    }
    function isBucket(uint256 _bucket) public view returns (bool) {
        return bucketList.isNode(_bucket);
    }

    // --- Tax (Stability Fee) Collection ---
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
          latestAccumulatedRate);
        return (newlyAccumulatedRate, diff(newlyAccumulatedRate, lastAccumulatedRate));
    }
    function taxAll() external emitLog {
        for (uint i = 0; i < collateralList.length; i++) {
            drip(collateralList[i]);
        }
    }
    function taxSingle(bytes32 collateralType) public emitLog returns (uint) {
        if (now <= collateralTypes[collateralType].updateTime) {
          (, uint latestAccumulatedRate) = cdpEngine.collateralTypes(collateralType);
          return latestAccumulatedRate;
        }
        (uint newlyAccumulatedRate, int deltaRate) = taxationOutcome(collateralType);
        splitTaxIncome(collateralType, deltaRate);
        (, latestAccumulatedRate) = cdpEngine.collateralTypes(collateralType);
        collateralTypes[collateralType].updateTime = now;
        return latestAccumulatedRate;
    }
    function splitTaxIncome(bytes32 collateralType, int deltaRate) internal {
        (uint debtAmount, ) = cdpEngine.collateralTypes(collateralType);
        uint256 currentBucket = latestBucket;
        int256  currentTaxCut;
        int256  coinBalance;
        while (currentBucket > 0) {
          if (buckets[collateralType][currentBucket].taxPercentage > 0) {
            coinBalance    = -int(cdpEngine.coinBalance(bucketAccounts[currentBucket]));
            currentTaxCut  = mul(int(buckets[collateralType][currentBucket].taxPercentage), deltaRate) / int(HUNDRED);
            currentTaxCut  = (
              both(mul(debtAmount, currentTaxCut) < 0, coinBalance > mul(debtAmount, currentTaxCut))
            ) ? coinBalance / int(debtAmount) : currentTaxCut;
            if (
              both(
                currentTaxCut != 0,
                either(
                  deltaRate >= 0,
                  both(currentTaxCut < 0, buckets[collateralType][currentBucket].take > 0)
                )
              )
            ) {
              cdpEngine.updateAccumulatedRate(collateralType, bucketAccounts[currentBucket], currentTaxCut);
            }
          }
          (, currentBucket) = bucketList.prev(currentBucket);
        }
        coinBalance = -int(cdpEngine.cinBalance(accountingEngine));
        currentTaxCut  = mul(sub(HUNDRED, bucketTaxCut[collateralType]), deltaRate) / int(HUNDRED);
        currentTaxCut  = (
          both(mul(debtAmount, currentTaxCut) < 0, coinBalance > mul(debtAmount, currentTaxCut))
        ) ? coinBalance / int(debtAmount) : currentTaxCut;
        if (currentTaxCut != 0) {
          cdpEngine.updateAccumulatedRate(collateralType, accountingEngine, currentTaxCut);
        }
    }
}
