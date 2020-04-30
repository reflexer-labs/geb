/// RedemptionRateSetter.sol

// Copyright (C) 2016, 2017  Nikolai Mushegian <nikolai@dapphub.com>
// Copyright (C) 2016, 2017  Daniel Brockman <daniel@dapphub.com>
// Copyright (C) 2017        Rain Break <rainbreak@riseup.net>
// Copyright (C) 2020        Stefan C. Ionescu <stefanionescu@protonmail.com>

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
import "./ExponentialMath.sol";

contract OracleLike {
    function getPriceWithValidity() external returns (bytes32, bool);
    function lastUpdateTime() external view returns (uint64);
}

contract OracleRelayerLike {
    function redemptionPrice() external returns (uint256);
    function modifyParameters(bytes32,uint256) external;
}

/**
  RedemptionRateSetterOne is a PI controller that tries to set a rate of change for
  the redemption price according to the market/redemption price deviation.

  The main external input is the price feed for the reflex-bond.

  Rates are computed so that they pull the market price in the opposite direction
  of the deviation.

  The deviation is always calculated against the most recent price update from the oracle. Check
  RedemptionRateSetterTwo for a controller that checks the latest deviation against a deviation accumulator.

  The integral component should be adjusted through governance by setting 'integralSensitivity'. Check
  RedemptionRateSetterTwo for an accumulator that computes the integral automatically.

  After deployment, you can set several parameters such as:
    - Default value for 'defaultRedemptionRate'
    - A deviation multiplier for faster response
    - A minimum deviation from the redemption price at which rate recalculation starts again
    - A sensitivity parameter to apply over time to increase/decrease the rates if the
      deviation is kept constant (the integral from PI)
**/
contract RedemptionRateSetterOne is Logging, ExponentialMath {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 1;
    }
    function removeAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 0;
    }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "RedemptionRateSetterOne/account-not-authorized");
        _;
    }

    // --- Events ---
    event UpdateRedemptionRate(
        uint marketPrice,
        uint redemptionRate,
        uint proportionalSensitivity,
        uint integralSensitivity
    );

    // --- Structs ---
    struct PI {
        uint proportionalSensitivity;
        uint integralSensitivity;
    }

    int256            public latestDeviationType;

    uint256           public latestMarketPrice;         // [ray]
    uint256           public lastUpdateTime;

    uint256           public noiseBarrier;              // [ray]
    uint256           public accruedTimeSinceDeviated;

    uint256           public defaultRedemptionRate;     // [ray]

    uint256           public redemptionRateUpperBound;  // [ray]
    uint256           public redemptionRateLowerBound;  // [ray]

    uint256           public contractEnabled;

    PI                public piSettings;

    OracleLike        public orcl;
    OracleRelayerLike public oracleRelayer;

    constructor(
      address oracleRelayer_
    ) public {
        authorizedAccounts[msg.sender] = 1;
        defaultRedemptionRate          = RAY;
        redemptionRateUpperBound       = MAX;
        redemptionRateLowerBound       = MAX;
        lastUpdateTime                 = now;
        oracleRelayer                  = OracleRelayerLike(oracleRelayer_);
        piSettings                     = PI(RAY, 0);
        latestMarketPrice              = oracleRelayer.redemptionPrice();
        contractEnabled                = 1;
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, address addr) external emitLog isAuthorized {
        require(contractEnabled == 1, "RedemptionRateSetterOne/contract-not-enabled");
        if (parameter == "orcl") orcl = OracleLike(addr);
        else if (parameter == "oracleRelayer") oracleRelayer = OracleRelayerLike(addr);
        else revert("RedemptionRateSetterOne/modify-unrecognized-param");
    }
    function modifyParameters(bytes32 parameter, uint256 val) external emitLog isAuthorized {
        require(contractEnabled == 1, "RedemptionRateSetterOne/contract-not-enabled");
        if (parameter == "noiseBarrier") noiseBarrier = val;
        else if (parameter == "defaultRedemptionRate") defaultRedemptionRate = val;
        else if (parameter == "integralSensitivity")  {
          piSettings.integralSensitivity = val;
        }
        else if (parameter == "proportionalSensitivity") {
          piSettings.proportionalSensitivity = val;
        }
        else if (parameter == "redemptionRateUpperBound") {
          if (redemptionRateLowerBound != MAX) {
            require(val >= redemptionRateLowerBound, "RedemptionRateSetterOne/small-upper-bound");
          }
          redemptionRateUpperBound = val;
        }
        else if (parameter == "redemptionRateLowerBound") {
          if (redemptionRateUpperBound != MAX) {
            require(val <= redemptionRateUpperBound, "RedemptionRateSetterOne/big-lower-bound");
          }
          redemptionRateLowerBound = val;
        }
        else revert("RedemptionRateSetterOne/modify-unrecognized-param");
    }
    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;
    uint32  constant SPY = 31536000;
    uint256 constant MAX = 2 ** 255;

    function ray(uint x) internal pure returns (uint z) {
        z = mul(x, 10 ** 9);
    }
    function add(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x);
    }
    function add(uint x, int y) internal pure returns (uint z) {
        z = x + uint(y);
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function add(int x, int y) internal pure returns (int z) {
        z = x + y;
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        z = x - y;
        require(z <= x);
    }
    function sub(uint x, int y) internal pure returns (uint z) {
        z = x - uint(y);
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }
    function sub(int x, int y) internal pure returns (int z) {
        z = x - y;
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function mul(int x, uint y) internal pure returns (int z) {
        require(y == 0 || (z = x * int(y)) / int(y) == x);
    }
    function div(uint x, uint y) internal pure returns (uint z) {
        require(y > 0);
        z = x / y;
        require(z <= x);
    }
    function delta(uint x, uint y) internal pure returns (uint z) {
        z = (x >= y) ? sub(x, y) : sub(y, x);
    }
    function perSecondRedemptionRate(uint x) internal view returns (uint z) {
        /**
          Use the exponential formulas to compute the per-second rate.
          After the initial computation we need to divide by 2^precision.
        **/
        (uint rawResult, uint precision) = pow(x, RAY, 1, SPY);
        z = div((rawResult * RAY), (2 ** precision));
    }

    // --- Utils ---
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }
    function era() internal view returns (uint) {
        return block.timestamp;
    }
    function deviationType(uint x, uint y) internal view returns (int z) {
        z = (x >= y) ? int(-1) : int(1);
    }
    function baseAnnualRate(uint256 x) internal pure returns (uint256 z) {
        return RAY + delta(x, RAY);
    }
    function accrueDeviatedSeconds(uint x) internal {
        accruedTimeSinceDeviated = add(accruedTimeSinceDeviated, x);
    }
    function restartDeviation() internal {
        accruedTimeSinceDeviated = 0;
        latestDeviationType = 0;
    }
    function updateDeviationType(int deviationType_) internal {
        latestDeviationType = (latestDeviationType == 0) ? deviationType_ : -int(latestDeviationType);
    }
    function calculatePIRate(uint x, uint y) internal view returns (uint z) {
        z = add(
          add(div(mul(sub(mul(x, RAY) / y, RAY), piSettings.proportionalSensitivity), RAY), RAY),
          mul(piSettings.integralSensitivity, accruedTimeSinceDeviated)
        );
    }
    function mixCalculatedAndDefaultRates(uint perSecondRedemptionRate_, int deviationType_)
      internal view returns (uint x) {
        if (deviationType_ == 1) {
          x = (defaultRedemptionRate > RAY) ?
            add(defaultRedemptionRate, sub(perSecondRedemptionRate_, RAY)) : add(RAY, sub(perSecondRedemptionRate_, RAY));
        } else {
          x = (defaultRedemptionRate < RAY) ?
            sub(defaultRedemptionRate, sub(perSecondRedemptionRate_, RAY)) : sub(RAY, sub(perSecondRedemptionRate_, RAY));
        }
    }
    function calculateRedemptionRate(uint currentMarketPrice_, uint redemptionPrice_, int deviationType_)
      public view returns (uint256) {
        uint calculatedPIRate_ = (deviationType_ == 1) ?
          calculatePIRate(redemptionPrice_, currentMarketPrice_) : calculatePIRate(currentMarketPrice_, redemptionPrice_);

        uint perSecondRedemptionRate_ = perSecondRedemptionRate(baseAnnualRate(calculatedPIRate_));
        perSecondRedemptionRate_ = mixCalculatedAndDefaultRates(perSecondRedemptionRate_, deviationType_);

        return perSecondRedemptionRate_;
    }

    // --- Feedback Mechanism ---
    function updateRedemptionRate() external emitLog {
        require(contractEnabled == 1, "RedemptionRateSetterOne/contract-not-enabled");
        uint timeSinceLastUpdate = sub(era(), lastUpdateTime);
        require(timeSinceLastUpdate > 0, "RedemptionRateSetterOne/optimized");
        // Fetch redemption price
        uint redemptionPrice = oracleRelayer.redemptionPrice();
        // Get price feed updates
        (bytes32 priceFeedValue, bool hasValidValue) = orcl.getPriceWithValidity();
        // If the OSM has a value
        if (hasValidValue) {
          uint perSecondRedemptionRate_;
          // Compute the deviation and whether it's negative/positive
          uint deviation = delta(ray(uint(priceFeedValue)), redemptionPrice);
          int deviationType_ = deviationType(ray(uint(priceFeedValue)), redemptionPrice);
          // If the deviation is exceeding 'noiseBarrier'
          if (deviation >= noiseBarrier) {
            (deviationType_ == latestDeviationType) ?
              accrueDeviatedSeconds(timeSinceLastUpdate) : updateDeviationType(deviationType_);
            // Compute the new per-second rate
            perSecondRedemptionRate_ = calculateRedemptionRate(
              ray(uint(priceFeedValue)),
              redemptionPrice,
              deviationType_
            );
            // Set the new rate
            oracleRelayer.modifyParameters("redemptionRate", perSecondRedemptionRate_);
            // Emit event
            emit UpdateRedemptionRate(
              ray(uint(priceFeedValue)),
              perSecondRedemptionRate_,
              piSettings.proportionalSensitivity,
              piSettings.integralSensitivity
            );
          } else {
            restartDeviation();
            // Simply set default value for way
            oracleRelayer.modifyParameters("redemptionRate", defaultRedemptionRate);
            // Emit event
            emit UpdateRedemptionRate(
              ray(uint(priceFeedValue)),
              defaultRedemptionRate,
              piSettings.proportionalSensitivity,
              piSettings.integralSensitivity
            );
          }
          // Make sure you store the latest price as a ray
          latestMarketPrice = ray(uint(priceFeedValue));
          // Also store the timestamp of the update
          lastUpdateTime = era();
        }
    }
}

/**
  RedemptionRateSetterTwo tries to set a rate of change for the redemption price according to recent market
  price deviations. It is meant to resemble a PID controller as closely as possible.

  The elements that come into computing the rate of change are:
    - The current market price deviation from the redemption price (the proportional from PID)
    - An accumulator of the latest market price deviations from the redemption price (the integral from PID)
    - A derivative (slope) of the market/redemption price deviation computed using two accumulators (the derivative from PID)

  The main external input is the price feed for the reflex-bond.

  Rates are computed so that they pull the market price in the opposite direction
  of the deviation, toward the constantly updating target price.

  After deployment, you can set several parameters such as:

    - Default value for the redemption rate
    - A default deviation multiplier
    - A default sensitivity parameter to apply over time
    - A default multiplier for the slope of change in price
    - A minimum deviation from the target price accumulator at which rate recalculation starts again
**/
contract RedemptionRateSetterTwo is Logging, ExponentialMath {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "RedemptionRateSetterTwo/account-not-authorized");
        _;
    }

    // --- Events ---
    event UpdateRedemptionRate(
        uint marketPrice,
        uint redemptionRate,
        uint proportionalSensitivity,
        uint integralSensitivity
    );
    event AccumulateDeviation(
        int256 oldAccumulator,
        int256 integralAccumulator,
        int256 rawAccumulator
    );

    // --- Structs ---
    struct PID {
        uint proportionalSensitivity;
        uint integralSensitivity;
    }

    // -- Static & Default Variables ---
    uint256 public noiseBarrier;
    uint256 public defaultRedemptionRate;          // [ray]

    uint256 public redemptionRateUpperBound;       // [ray]
    uint256 public redemptionRateLowerBound;       // [ray]

    uint256 public oldLength;
    uint256 public integralLength;
    uint256 public rawLength;

    PID     public pidSettings;

    uint256 public contractEnabled;

    // --- Fluctuating Variables ---
    int256  public trendDeviationType;
    int256  public latestDeviationType;
    uint256 public latestMarketPrice;              // [ray]

    // --- Accumulator ---
    int256[] public deviationHistory;
    uint64   public lastUpdateTime;

    int256   public oldAccumulator;
    int256   public integralAccumulator;
    int256   public rawAccumulator;

    // --- Other System Components ---
    OracleLike        public orcl;
    OracleRelayerLike public oracleRelayer;

    constructor(
        address oracleRelayer_,
        uint256 oldLength_,
        uint256 integralLength_,
        uint256 rawLength_
    ) public {
        require(integralLength_ == oldLength_ + rawLength_, "RedemptionRateSetterTwo/improper-accumulator-lengths");
        require(integralLength_ > 0, "RedemptionRateSetterTwo/null-integral-accumulator-length");
        authorizedAccounts[msg.sender] = 1;
        oldAccumulator = 0;
        integralAccumulator = 0;
        rawAccumulator = 0;
        oldLength = oldLength_;
        integralLength = integralLength_;
        rawLength = rawLength_;
        defaultRedemptionRate = RAY;
        redemptionRateUpperBound = MAX;
        redemptionRateLowerBound = MAX;
        oracleRelayer = OracleRelayerLike(oracleRelayer_);
        latestMarketPrice = oracleRelayer.redemptionPrice();
        pidSettings = PID(RAY, RAY);
        deviationHistory.push(0);
        contractEnabled = 1;
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, address addr) external emitLog isAuthorized {
        require(contractEnabled == 1, "RedemptionRateSetterTwo/contract-not-enabled");
        if (parameter == "orcl") orcl = OracleLike(addr);
        else if (parameter == "oracleRelayer") oracleRelayer = OracleRelayerLike(addr);
        else revert("RedemptionRateSetterTwo/modify-unrecognized-param");
    }
    function modifyParameters(bytes32 parameter, uint256 val) external emitLog isAuthorized {
        require(contractEnabled == 1, "RedemptionRateSetterTwo/contract-not-enabled");
        if (parameter == "noiseBarrier") noiseBarrier = val;
        else if (parameter == "defaultRedemptionRate") defaultRedemptionRate = val;
        else if (parameter == "proportionalSensitivity") pidSettings.proportionalSensitivity = val;
        else if (parameter == "integralSensitivity") pidSettings.integralSensitivity = val;
        else if (parameter == "redemptionRateUpperBound") {
          if (redemptionRateLowerBound != MAX) require(val >= redemptionRateLowerBound, "RedemptionRateSetterOne/small-upper-bound");
          redemptionRateUpperBound = val;
        }
        else if (parameter == "redemptionRateLowerBound") {
          if (redemptionRateUpperBound != MAX) require(val <= redemptionRateUpperBound, "RedemptionRateSetterOne/big-lower-bound");
          redemptionRateLowerBound = val;
        }
        else revert("RedemptionRateSetterTwo/modify-unrecognized-param");
    }
    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;
    uint32  constant SPY = 31536000;
    uint256 constant MAX = 2 ** 255;

    function ray(uint x) internal pure returns (uint z) {
        z = mul(x, 10 ** 9);
    }
    function add(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x);
    }
    function add(uint x, int y) internal pure returns (uint z) {
        z = x + uint(y);
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function add(int x, int y) internal pure returns (int z) {
        z = x + y;
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        z = x - y;
        require(z <= x);
    }
    function sub(uint x, int y) internal pure returns (uint z) {
        z = x - uint(y);
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }
    function sub(int x, int y) internal pure returns (int z) {
        z = x - y;
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function mul(int x, uint y) internal pure returns (int z) {
        require(y == 0 || (z = x * int(y)) / int(y) == x);
    }
    function mul(int x, int y) internal pure returns (int z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function div(uint x, uint y) internal pure returns (uint z) {
        require(y > 0);
        z = x / y;
        require(z <= x);
    }
    function delta(uint x, uint y) internal pure returns (uint z) {
        z = (x >= y) ? x - y : y - x;
    }
    function perSecondRedemptionRate(uint x) internal view returns (uint z) {
        /**
          Use the exponential formulas to compute the per-second rate.
          After the initial computation we need to divide by 2^precision.
        **/
        (uint rawResult, uint precision) = pow(x, RAY, 1, SPY);
        z = div((rawResult * RAY), (2 ** precision));
    }

    // --- Utils ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }
    function era() internal view returns (uint) {
        return block.timestamp;
    }
    function oppositeDeviationSign(uint x, uint y) internal view returns (int z) {
        z = (x >= y) ? int(-1) : int(1);
    }
    function baseAnnualRate(uint256 x) internal pure returns (uint256 z) {
        return RAY + delta(x, RAY);
    }
    function updateTrendDeviationType(int newTrendDeviationType) internal {
        trendDeviationType = (trendDeviationType == 0) ? newTrendDeviationType : -trendDeviationType;
    }
    function updateLatestDeviationType(int newLatestDeviationType) internal {
        latestDeviationType = (latestDeviationType == 0) ? newLatestDeviationType : -latestDeviationType;
    }
    function oppositeDeviationForce(uint x, uint y) internal view returns (int z) {
        uint deltaDeviation = delta(x, y);
        int oppositeDeviationSign = oppositeDeviationSign(x, y);
        return mul(-oppositeDeviationSign, deltaDeviation);
    }
    // Update accumulators and deviation history
    function updateAccumulatorsAndHistory(int oppositeDeviationForce_) internal {
        // Update deviation history
        deviationHistory.push(oppositeDeviationForce_);
        // Update the integral accumulator
        integralAccumulator  = add(integralAccumulator, oppositeDeviationForce_);
        if (deviationHistory.length > integralLength) {
          integralAccumulator = sub(
            integralAccumulator,
            deviationHistory[sub(deviationHistory.length, add(integralLength, uint(1)))]
          );
        }
        // Update the old and raw accumulators
        rawAccumulator = add(rawAccumulator, oppositeDeviationForce_);
        if (deviationHistory.length > rawLength) {
          rawAccumulator = sub(
            rawAccumulator,
            deviationHistory[sub(deviationHistory.length, add(rawLength, uint(1)))]
          );
        }
        oldAccumulator = sub(integralAccumulator, rawAccumulator);
    }
    // Calculate yearly rate according to PID settings
    function calculatePIDRate(
        uint higherPrice,
        uint lowerPrice,
        int trendDeviationType_,
        int latestDeviationType_
    ) public view returns (int P, int I, int D, uint pid) {
        P   = mul(mul(latestDeviationType_, sub(higherPrice, lowerPrice)), pidSettings.proportionalSensitivity) / int(RAY);
        I   = mul(int(-1), int(mul(integralAccumulator, pidSettings.integralSensitivity) / int(RAY)));
        D   = either(oldAccumulator == 0, rawAccumulator == 0) ? int(RAY) : mul(rawAccumulator, RAY) / oldAccumulator;

        int deltaPID = mul(add(P, I), D) / int(RAY);
        /***
          Minimize the current direction even more if the market prices are predominantly on the
          other side (they already overshoot)
        ***/
        if (either(oldAccumulator < 0 && rawAccumulator > 0, rawAccumulator < 0 && oldAccumulator > 0)) {
          deltaPID = -deltaPID;
        }

        // To avoid underflow, if deltaPID is smaller than -higherPrice or -lowerPrice, make it zero (only for this update)
        deltaPID = (both(deltaPID < 0, both(trendDeviationType_ > 0, deltaPID < int(-lowerPrice)))) ?  0 : deltaPID;
        deltaPID = (both(deltaPID < 0, both(trendDeviationType_ < 0, deltaPID < int(-higherPrice)))) ? 0 : deltaPID;

        uint adjustedPIDRate = (trendDeviationType_ > 0) ? add(lowerPrice, deltaPID) : add(higherPrice, deltaPID);

        pid = (trendDeviationType_ > 0) ?
          mul(adjustedPIDRate, RAY) / higherPrice : mul(higherPrice, RAY) / adjustedPIDRate;
    }
    function mixCalculatedAndDefaultRates(uint perSecondRedemptionRate_, int deviationType_)
      internal view returns (uint x) {
        if (deviationType_ == 1) {
          x = (defaultRedemptionRate > RAY) ?
            add(defaultRedemptionRate, sub(perSecondRedemptionRate_, RAY)) : add(RAY, sub(perSecondRedemptionRate_, RAY));
        } else {
          x = (defaultRedemptionRate < RAY) ?
            sub(defaultRedemptionRate, sub(perSecondRedemptionRate_, RAY)) : sub(RAY, sub(perSecondRedemptionRate_, RAY));
        }
    }
    function calculateRedemptionRate(
        uint currentMarketPrice_,
        uint redemptionPrice_,
        int trendDeviationType_,
        int latestDeviationType_
    ) public view returns (uint256) {
        (, , , uint calculatedPIDRate_) = (latestDeviationType_ == 1) ?
          calculatePIDRate(redemptionPrice_, currentMarketPrice_, trendDeviationType_, latestDeviationType_) :
          calculatePIDRate(currentMarketPrice_, redemptionPrice_, trendDeviationType_, latestDeviationType_);

        uint perSecondRedemptionRate_ = perSecondRedemptionRate(baseAnnualRate(calculatedPIDRate_));
        perSecondRedemptionRate_      = mixCalculatedAndDefaultRates(perSecondRedemptionRate_, trendDeviationType_);

        return perSecondRedemptionRate_;
    }

    // --- Feedback Mechanism ---
    function updateRedemptionRate() external emitLog {
        require(contractEnabled == 1, "RedemptionRateSetterTwo/contract-not-enabled");
        // Get feed latest price timestamp
        uint64 lastUpdateTime_ = orcl.lastUpdateTime();
        // If there's no new time in the feed, simply return
        if (lastUpdateTime_ <= lastUpdateTime) return;
        // Get price feed updates
        (bytes32 priceFeedValue, bool hasValidValue) = orcl.getPriceWithValidity();
        // If the OSM has a value
        if (hasValidValue) {
          uint redemptionPrice = oracleRelayer.redemptionPrice();
          // Update accumulators and deviation history
          updateAccumulatorsAndHistory(oppositeDeviationForce(ray(uint(priceFeedValue)), redemptionPrice));
          // If we don't have enough datapoints, return
          if (
            either(
              either(deviationHistory.length <= rawLength, deviationHistory.length <= integralLength),
              deviationHistory.length <= oldLength
            )
          ) {
            return;
          }
          // Initialize new per-second target rate
          uint perSecondRedemptionRate_;
          // Compute the deviation of the integral accumulator from the redemption price
          int deltaDeviation = (integralAccumulator == 0) ? 0 : integralAccumulator / int(integralLength);
          // Compute the opposite of the current integral accumulator sign
          int trendDeviationType_ = (deltaDeviation < 0) ? int(1) : int(-1);
          // Compute the opposite sign of the current market price deviation
          int latestDeviationType_ = oppositeDeviationSign(ray(uint(priceFeedValue)), redemptionPrice);
          // If the deviation is exceeding 'noiseBarrier'
          if (either(deltaDeviation >= int(noiseBarrier), deltaDeviation <= -int(noiseBarrier))) {
            /**
              If the current deviation is different than the latest one,
              update the latest one
            **/
            if (trendDeviationType_ != trendDeviationType) {
              updateTrendDeviationType(trendDeviationType_);
            }
            if (latestDeviationType_ != latestDeviationType) {
              updateLatestDeviationType(latestDeviationType_);
            }
            // Compute the new per-second rate
            perSecondRedemptionRate_ = calculateRedemptionRate(
              ray(uint(priceFeedValue)),
              redemptionPrice,
              trendDeviationType_,
              latestDeviationType_
            );
            oracleRelayer.modifyParameters("redemptionRate", perSecondRedemptionRate_);
            // Emit event
            emit UpdateRedemptionRate(
              ray(uint(priceFeedValue)),
              perSecondRedemptionRate_,
              pidSettings.proportionalSensitivity,
              pidSettings.integralSensitivity
            );
          } else {
            // Restart deviation types
            trendDeviationType  = 0;
            latestDeviationType = 0;
            // Set default rate
            oracleRelayer.modifyParameters("redemptionRate", defaultRedemptionRate);
            // Emit event
            emit UpdateRedemptionRate(
              ray(uint(priceFeedValue)),
              defaultRedemptionRate,
              pidSettings.proportionalSensitivity,
              pidSettings.integralSensitivity
            );
          }
          // Store the latest market price
          latestMarketPrice = ray(uint(priceFeedValue));
          // Store the timestamp of the oracle update
          lastUpdateTime = lastUpdateTime_;
          // Emit event
          emit AccumulateDeviation(
            oldAccumulator,
            integralAccumulator,
            rawAccumulator
          );
        }
    }
}
