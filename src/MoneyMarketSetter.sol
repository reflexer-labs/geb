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

contract TaxCollectorLike {
    function modifyParameters(bytes32, uint) external;
    function taxAll() external;
    function globalStabilityFee() external view returns (uint256);
}

contract CoinSavingsAccountLike {
    function updateAccumulatedRate() external returns (uint);
    function modifyParameters(bytes32, uint256) external;
    function savingsRate() external view returns (uint256);
}

/***
  MoneyMarketSetterOne is a PI controller for a pegged coin.
  It automatically adjusts the stability fee and the savings rate according to deviations from the peg.

  It does not change the redemption price but rather tries to maintain a strong peg without the need
  for continuous governance intervention.

  This Pop takes into consideration the deviation between the latest market price and the target price.
***/
contract MoneyMarketSetterOne is Logging, ExponentialMath {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 1;
    }
    function removeAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 0;
    }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "MoneyMarketSetterOne/account-not-authorized");
        _;
    }

    // --- Events ---
    event UpdateRates(
        uint marketPrice,
        uint stabilityFee,
        uint savingsRate,
        uint proportionalSensitivity,
        uint integralSensitivity
    );
    event ReturnRatesBackToDefault(
        uint stabilityFee,
        uint savingsRate,
        uint returnToDefaultRate,
        uint returnToDefaultDeadline
    );

    // --- Structs ---
    struct PI {
        uint proportionalSensitivity;
        uint integralSensitivity;
    }
    struct RateBounds {
        uint upperBound;
        uint lowerBound;
    }
    struct MarketRates {
        uint stabilityFee;
        uint savingsRate;
    }

    int256       public latestDeviationType;

    uint256      public latestMarketPrice;             // [ray]
    uint256      public lastUpdateTime;
    uint256      public accruedTimeSincePriceDeviated;

    uint32       public defaultRateChangeTimeframe;
    uint256      public noiseBarrier;                  // [ray]

    uint256      public returnToDefaultTimeframe;
    uint256      public returnToDefaultRate;
    uint256      public returnToDefaultDeadline;
    uint256      public returnToDefaultUpdateTime;

    uint256      public rateSpread;

    uint256      public contractEnabled;

    PI           public piSettings;
    MarketRates  public defaultRates;
    RateBounds   public stabilityFeeBounds;
    RateBounds   public savingsRateBounds;

    OracleLike             public orcl;
    OracleRelayerLike      public oracleRelayer;
    CoinSavingsAccountLike public coinSavingsAccount;
    TaxCollectorLike       public taxCollector;

    constructor(
      address oracleRelayer_,
      address coinSavingsAccount_,
      address taxCollector_
    ) public {
        authorizedAccounts[msg.sender] = 1;
        latestMarketPrice = RAY;
        rateSpread = RAY;
        defaultRateChangeTimeframe = uint32(SPY);
        lastUpdateTime = now;
        oracleRelayer = OracleRelayerLike(oracleRelayer_);
        coinSavingsAccount = CoinSavingsAccountLike(coinSavingsAccount_);
        taxCollector = TaxCollectorLike(taxCollector_);
        piSettings = PI(RAY, 0);
        returnToDefaultRate = RAY;
        returnToDefaultDeadline = now;
        stabilityFeeBounds = RateBounds(MAX, MAX);
        savingsRateBounds  = RateBounds(MAX, MAX);
        defaultRates = MarketRates(RAY, RAY);
        contractEnabled = 1;
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, address addr) external emitLog isAuthorized {
        require(contractEnabled == 1, "MoneyMarketSetterOne/contract-not-enabled");
        if (parameter == "orcl") orcl = OracleLike(addr);
        else if (parameter == "oracleRelayer") oracleRelayer = OracleRelayerLike(addr);
        else if (parameter == "taxCollector") taxCollector = TaxCollectorLike(addr);
        else if (parameter == "coinSavingsAccount") coinSavingsAccount = CoinSavingsAccountLike(addr);
        else revert("MoneyMarketSetterOne/modify-unrecognized-param");
    }
    function modifyParameters(bytes32 parameter, uint256 val) external emitLog isAuthorized {
        require(contractEnabled == 1, "MoneyMarketSetterOne/contract-not-enabled");
        if (parameter == "noiseBarrier") noiseBarrier = val;
        else if (parameter == "rateSpread") rateSpread = val;
        else if (parameter == "returnToDefaultTimeframe") returnToDefaultTimeframe = val;
        else if (parameter == "defaultRateChangeTimeframe") defaultRateChangeTimeframe = uint32(val);
        else if (parameter == "stabilityFee") {
          require(val >= defaultRates.savingsRate, "MoneyMarketSetterOne/small-stability-fee");
          defaultRates.stabilityFee = val;
        }
        else if (parameter == "savingsRate") {
          require(val <= defaultRates.stabilityFee, "MoneyMarketSetterOne/big-savings-rate");
          defaultRates.savingsRate = val;
        }
        else if (parameter == "integralSensitivity")  {
          piSettings.integralSensitivity  = val;
        }
        else if (parameter == "proportionalSensitivity") {
          piSettings.proportionalSensitivity = val;
        }
        else if (parameter == "stabilityFeeBounds-upperBound") {
          if (stabilityFeeBounds.lowerBound != MAX) {
            require(val >= stabilityFeeBounds.lowerBound, "MoneyMarketSetterOne/small-upper-bound");
          }
          stabilityFeeBounds.upperBound = val;
        }
        else if (parameter == "stabilityFeeBounds-lowerBound") {
          if (stabilityFeeBounds.upperBound != MAX) {
            require(val <= stabilityFeeBounds.upperBound, "MoneyMarketSetterOne/big-lower-bound");
          }
          stabilityFeeBounds.lowerBound = val;
        }
        else if (parameter == "savingsRateBounds-upperBound") {
          if (savingsRateBounds.lowerBound != MAX) {
            require(val >= savingsRateBounds.lowerBound, "MoneyMarketSetterOne/small-upper-bound");
          }
          savingsRateBounds.upperBound = val;
        }
        else if (parameter == "savingsRateBounds-lowerBound") {
          if (savingsRateBounds.upperBound != MAX) {
            require(val <= savingsRateBounds.upperBound, "MoneyMarketSetterOne/big-lower-bound");
          }
          savingsRateBounds.lowerBound = val;
        }
        else revert("MoneyMarketSetterOne/modify-unrecognized-param");
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
    function sub(uint x, uint y) internal pure returns (uint z) {
        z = x - y;
        require(z <= x);
    }
    function sub(uint x, int y) internal pure returns (uint z) {
        z = x - uint(y);
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
        z = (x >= y) ? x - y : y - x;
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, y) / RAY;
    }
    function rpow(uint x, uint n, uint base) internal pure returns (uint z) {
        assembly {
            switch x case 0 {switch n case 0 {z := base} default {z := 0}}
            default {
                switch mod(n, 2) case 0 { z := base } default { z := x }
                let half := div(base, 2)  // for rounding.
                for { n := div(n, 2) } n { n := div(n,2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0,0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0,0) }
                    x := div(xxRound, base)
                    if mod(n,2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0,0) }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }
    function perIntervalRate(uint x, uint32 timeframe) internal view returns (uint z) {
        /**
          Use the Exp formulas to compute the per-second rate.
          After the initial computation we need to divide by 2^precision.
        **/
        (uint rawResult, uint precision) = pow(x, RAY, 1, timeframe);
        z = div((rawResult * RAY), (2 ** precision));
    }

    // --- Utils ---
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
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
    function baseAnnualRateWithSpread(uint256 x) internal view returns (uint256 z) {
        return RAY + div(mul(delta(x, RAY), RAY), rateSpread);
    }
    function accruePriceDeviatedSeconds(uint x) internal {
        accruedTimeSincePriceDeviated = add(accruedTimeSincePriceDeviated, x);
    }
    function oppositeDeviationSign(int newDeviationType) internal {
        latestDeviationType = (latestDeviationType == 0) ? newDeviationType : -latestDeviationType;
    }
    function customPerSecondRate(uint x, uint y, uint32 wide) internal view returns (uint z) {
        if (x == y) return RAY;
        (uint max, uint min) = (x > y) ? (x, y) : (y, x);
        z = perIntervalRate(baseAnnualRate(mul(max, RAY) / min), wide);
        z = (x > y) ? sub(RAY, sub(z, RAY)) : add(RAY, sub(z, RAY));
    }
    function calculatePIRate(uint x, uint y) internal view returns (uint z) {
        z = add(
          add(div(mul(sub(mul(x, RAY) / y, RAY), piSettings.proportionalSensitivity), RAY), RAY),
          mul(piSettings.integralSensitivity, accruedTimeSincePriceDeviated)
        );
    }
    function mixCalculatedAndDefaultRates(
        uint stabilityFee_,
        uint savingsRate_,
        int deviationType_
    ) internal view returns (uint x, uint y) {
        x = add(taxCollector.globalStabilityFee(), mul(deviationType_, sub(stabilityFee_, RAY)));
        y = add(coinSavingsAccount.savingsRate(), mul(deviationType_, sub(savingsRate_, RAY)));
    }
    function calculateRedemptionRate(
        uint currentMarketPrice_,
        uint redemptionPrice,
        int deviationType_
    ) public view returns (uint256, uint256) {
        // Calculate adjusted annual rate
        uint calculatePIRate_ = (deviationType_ == 1) ?
          calculatePIRate(redemptionPrice, currentMarketPrice_) :
          calculatePIRate(currentMarketPrice_, redemptionPrice);

        // Calculate the per-second stability fee and per-second savings rate
        uint stabilityFee_ = perIntervalRate(baseAnnualRate(calculatePIRate_), defaultRateChangeTimeframe);
        uint savingsRate_ =
          (rateSpread == RAY) ?
          stabilityFee_ :
          perIntervalRate(baseAnnualRateWithSpread(calculatePIRate_), defaultRateChangeTimeframe);

        // If the deviation is positive, we set a negative rate and vice-versa
        (stabilityFee_, savingsRate_) = mixCalculatedAndDefaultRates(
          stabilityFee_, savingsRate_, deviationType_
        );

        // The stability fee might have bounds so make sure you don't pass them
        stabilityFee_ =
          (stabilityFee_ < stabilityFeeBounds.upperBound && stabilityFeeBounds.lowerBound != MAX) ?
          stabilityFeeBounds.lowerBound : stabilityFee_;
        stabilityFee_ =
          (stabilityFee_ > stabilityFeeBounds.upperBound && stabilityFeeBounds.upperBound != MAX) ?
          stabilityFeeBounds.upperBound : stabilityFee_;

        // The savings rate might have bounds so make sure you don't pass them
        savingsRate_ =
          (savingsRate_ < savingsRateBounds.lowerBound && savingsRateBounds.lowerBound != MAX) ?
          savingsRateBounds.lowerBound : savingsRate_;
        savingsRate_ =
          (savingsRate_ > savingsRateBounds.upperBound && savingsRateBounds.upperBound != MAX) ?
          savingsRateBounds.upperBound : savingsRate_;

        // Adjust savings rate so it's smaller or equal to stability fee
        savingsRate_ = (savingsRate_ > stabilityFee_) ? stabilityFee_ : savingsRate_;

        return (stabilityFee_, savingsRate_);
    }

    // --- Feedback Mechanism ---
    function updateRedemptionRate() external emitLog {
        require(contractEnabled == 1, "MoneyMarketSetterOne/contract-not-enabled");
        uint timeSinceLastUpdate = sub(era(), lastUpdateTime);
        require(timeSinceLastUpdate > 0, "MoneyMarketSetterOne/optimized");
        // Fetch redemptionPrice
        uint redemptionPrice = oracleRelayer.redemptionPrice();
        // Get price feed updates
        (bytes32 priceFeedValue, bool hasValidValue) = orcl.getPriceWithValidity();
        // Initialize rates
        uint stabilityFee_; uint savingsRate_;
        // If the OSM has a value
        if (hasValidValue) {
          // Compute the deviation and whether it's negative/positive
          uint deviation = delta(ray(uint(priceFeedValue)), redemptionPrice);
          int newDeviationType = oppositeDeviationSign(ray(uint(priceFeedValue)), redemptionPrice);
          // If the deviation is at least 'noiseBarrier'
          if (deviation >= noiseBarrier) {
            // Reset return to default params
            returnToDefaultRate = RAY;
            returnToDefaultDeadline = now;
            returnToDefaultUpdateTime = now;
            // Accrue seconds passed since market price deviation has been on one side
            (newDeviationType == latestDeviationType) ?
              accruePriceDeviatedSeconds(timeSinceLastUpdate) : oppositeDeviationSign(newDeviationType);
            // Compute the new per-second rate
            (stabilityFee_, savingsRate_) = calculateRedemptionRate(
              ray(uint(priceFeedValue)),
              redemptionPrice,
              newDeviationType
            );
            // Set the new rates
            setNewRates(stabilityFee_, savingsRate_);
            // Emit event
            emit UpdateRates(
              ray(uint(priceFeedValue)),
              stabilityFee_,
              savingsRate_,
              piSettings.proportionalSensitivity,
              piSettings.integralSensitivity
            );
          } else {
            // Set return to default params
            if (latestDeviationType != 0) {
              setReturnToDefaultParams();
            }
            // Restart latest deviation type
            latestDeviationType = 0;
            // Restart accruedTimeSincePriceDeviated
            accruedTimeSincePriceDeviated = 0;
            // Update current rates
            (stabilityFee_, savingsRate_) = returnRatesBackToDefault();
            // Emit event
            emit ReturnRatesBackToDefault(
              stabilityFee_,
              savingsRate_,
              returnToDefaultRate,
              returnToDefaultDeadline
            );
          }
          // Make sure you store the latest price as a ray
          latestMarketPrice = ray(uint(priceFeedValue));
          // Also store the timestamp of the update
          lastUpdateTime = era();
        }
    }
    function setReturnToDefaultParams() internal {
        if (returnToDefaultTimeframe == 0) return;
        returnToDefaultRate = customPerSecondRate(
          taxCollector.globalStabilityFee(),
          defaultRates.stabilityFee,
          uint32(returnToDefaultTimeframe)
        );
        returnToDefaultDeadline = add(now, returnToDefaultTimeframe);
        returnToDefaultUpdateTime = now;
    }
    function returnRatesBackToDefault() internal returns (uint, uint){
        if (
          either(
            either(returnToDefaultDeadline <= now, returnToDefaultRate == RAY),
            either(
              taxCollector.globalStabilityFee() != defaultRates.stabilityFee,
              coinSavingsAccount.savingsRate() != defaultRates.savingsRate
            )
          )
        ) {
          returnToDefaultRate = RAY;
          returnToDefaultUpdateTime = now;
          setNewRates(defaultRates.stabilityFee, defaultRates.savingsRate);
          return (defaultRates.stabilityFee, defaultRates.savingsRate);
        }
        if (now <= returnToDefaultUpdateTime) {
          return (taxCollector.globalStabilityFee(), coinSavingsAccount.savingsRate());
        }
        int rateType              = (returnToDefaultRate < RAY) ? int(-1) : int(1);
        uint globalStabilityFee   = taxCollector.globalStabilityFee();
        uint savingsRate          = coinSavingsAccount.savingsRate();
        uint newStabilityFee      = rmul(
          rpow(returnToDefaultRate, sub(now, returnToDefaultUpdateTime), RAY),
          globalStabilityFee
        );
        uint newSavingsRate       = add(
          savingsRate,
          mul(rateType, div(mul(delta(newStabilityFee, globalStabilityFee), RAY), rateSpread))
        );
        returnToDefaultUpdateTime = now;
        setNewRates(newStabilityFee, newSavingsRate);
        return (newStabilityFee, newSavingsRate);
    }
    function setNewRates(uint stabilityFee_, uint savingsRate_) internal {
        taxCollector.taxAll();
        taxCollector.modifyParameters("globalStabilityFee", stabilityFee_);

        coinSavingsAccount.updateAccumulatedRate();
        coinSavingsAccount.modifyParameters("savingsRate", savingsRate_);
    }
}
