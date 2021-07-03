/// MultiOracleRelayer.sol

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity 0.6.7;

abstract contract SAFEEngineLike {
    function modifyParameters(bytes32, bytes32, bytes32, uint256) virtual external;
}

abstract contract OracleLike {
    function getResultWithValidity() virtual public view returns (uint256, bool);
}

contract MultiOracleRelayer {
    // --- Auth ---
    mapping (bytes32 => mapping(address => uint256)) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(bytes32 coinName, address account) external isAuthorized(coinName) {
        require(coinEnabled[coinName] == 1, "MultiOracleRelayer/coin-not-enabled");
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
        require(authorizedAccounts[coinName][msg.sender] == 1, "MultiOracleRelayer/account-not-authorized");
        _;
    }

    mapping (address => uint256) public systemComponents;
    /**
     * @notice Add a system component
     * @param component Component to auth
     */
    function addSystemComponent(address component) external {
        require(manager == msg.sender, "MultiOracleRelayer/invalid-manager");
        systemComponents[component] = 1;
        emit AddSystemComponent(component);
    }
    /**
     * @notice Remove a system component
      @param component Component to deauth
     */
    function removeSystemComponent(address component) external {
        require(manager == msg.sender, "MultiOracleRelayer/invalid-manager");
        systemComponents[component] = 0;
        emit RemoveSystemComponent(component);
    }
    /**
    * @notice Checks whether msg.sender is a system component
    **/
    modifier isSystemComponent {
        require(systemComponents[msg.sender] == 1, "MultiAccountingEngine/account-not-component");
        _;
    }

    // --- Data ---
    struct CollateralType {
        // Usually an oracle security module that enforces delays to fresh price feeds
        OracleLike orcl;
        // CRatio used to compute the 'safePrice' - the price used when generating debt in SAFEEngine
        uint256 safetyCRatio;
        // CRatio used to compute the 'liquidationPrice' - the price used when liquidating SAFEs
        uint256 liquidationCRatio;
    }

    // Data about each collateral type backing each coin
    mapping (bytes32 => mapping(bytes32 => CollateralType)) public collateralTypes;

    SAFEEngineLike public safeEngine;
    // The manager address
    address        public manager;
    // Address of the deployer
    address        public deployer;

    // Mapping of coin states
    mapping (bytes32 => uint256) public  coinEnabled;
    // Whether a coin has been initialized or not
    mapping (bytes32 => uint256) public  coinInitialized;
    // Virtual redemption prices (not the most updated values)
    mapping (bytes32 => uint256) internal _redemptionPrice;                                   // [ray]
    // The forces that change the system users' incentives by changing redemption prices
    mapping (bytes32 => uint256) public  redemptionRate;                                      // [ray]
    // Last time when a redemption price was changed
    mapping (bytes32 => uint256) public  redemptionPriceUpdateTime;                           // [unix epoch time]
    // Upper bound for a specific per-second redemption rate
    mapping (bytes32 => uint256) public  redemptionRateUpperBound;                            // [ray]
    // Lower bound for a specific per-second redemption rate
    mapping (bytes32 => uint256) public  redemptionRateLowerBound;                            // [ray]

    // --- Events ---
    event AddAuthorization(bytes32 indexed coinName, address account);
    event RemoveAuthorization(bytes32 indexed coinName, address account);
    event AddSystemComponent(address component);
    event RemoveSystemComponent(address component);
    event DisableCoin(bytes32 indexed coinName);
    event ModifyParameters(
        bytes32 indexed coinName,
        bytes32 collateralType,
        bytes32 parameter,
        address addr
    );
    event ModifyParameters(bytes32 indexed parameter, address data);
    event ModifyParameters(bytes32 indexed coinName, bytes32 parameter, uint256 data);
    event ModifyParameters(
        bytes32 indexed coinName,
        bytes32 collateralType,
        bytes32 parameter,
        uint256 data
    );
    event UpdateRedemptionPrice(bytes32 indexed coinName, uint256 redemptionPrice);
    event UpdateCollateralPrice(
        bytes32 indexed coinName,
        bytes32 indexed collateralType,
        uint256 priceFeedValue,
        uint256 safetyPrice,
        uint256 liquidationPrice
    );
    event InitializeCoin(
        bytes32 indexed coinName,
        uint256 redemptionPrice_,
        uint256 redemptionRateUpperBound_,
        uint256 redemptionRateLowerBound_
    );

    // --- Init ---
    constructor(address safeEngine_) public {
        require(safeEngine_ != address(0), "MultiOracleRelayer/null-safe-engine");
        safeEngine = SAFEEngineLike(safeEngine_);
        manager    = msg.sender;
        deployer   = msg.sender;
    }

    // --- Math ---
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;

    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x - y;
        require(z <= x, "MultiOracleRelayer/sub-underflow");
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "MultiOracleRelayer/mul-overflow");
    }
    function rmultiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // always rounds down
        z = multiply(x, y) / RAY;
    }
    function rdivide(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0, "MultiOracleRelayer/rdiv-by-zero");
        z = multiply(x, RAY) / y;
    }
    function rpower(uint256 x, uint256 n, uint256 base) internal pure returns (uint256 z) {
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

    // --- Administration ---
    /**
     * @notice Initialize a new coin
     * @param coinName The name of the coin to initialize
     * @param redemptionPrice_ The initial redemption price
     * @param redemptionRateUpperBound_ The initial redemption rate upper bound
     * @param redemptionRateLowerBound_ The initial redemption rate lower bound
     */
    function initializeCoin(
        bytes32 coinName,
        uint256 redemptionPrice_,
        uint256 redemptionRateUpperBound_,
        uint256 redemptionRateLowerBound_
    ) external {
        require(deployer == msg.sender, "MultiOracleRelayer/caller-not-deployer");
        require(coinInitialized[coinName] == 0, "MultiOracleRelayer/already-init");
        require(redemptionPrice_ > 0, "MultiOracleRelayer/null-red-price");
        require(redemptionRateUpperBound_ > RAY, "MultiOracleRelayer/invalid-red-rate-upper-bound");
        require(redemptionRateLowerBound_ < RAY, "MultiOracleRelayer/invalid-red-rate-lower-bound");

        authorizedAccounts[coinName][msg.sender] = 1;

        coinInitialized[coinName] = 1;
        coinEnabled[coinName]     = 1;

        _redemptionPrice[coinName]          = redemptionPrice_;
        redemptionRate[coinName]            = RAY;
        redemptionPriceUpdateTime[coinName] = now;
        redemptionRateUpperBound[coinName]  = redemptionRateUpperBound_;
        redemptionRateLowerBound[coinName]  = redemptionRateLowerBound_;

        emit InitializeCoin(coinName, redemptionPrice_, redemptionRateUpperBound_, redemptionRateLowerBound_);
        emit AddAuthorization(coinName, msg.sender);
    }
    /**
     * @notice Modify oracle price feed addresses
     * @param coinName The name of the coin for which we modify a price feed
     * @param collateralType Collateral whose oracle we change
     * @param parameter Name of the parameter
     * @param addr New oracle address
     */
    function modifyParameters(
        bytes32 coinName,
        bytes32 collateralType,
        bytes32 parameter,
        address addr
    ) external isAuthorized(coinName) {
        require(coinEnabled[coinName] == 1, "MultiOracleRelayer/coin-not-enabled");
        require(coinInitialized[coinName] == 1, "MultiOracleRelayer/coin-not-init");

        if (parameter == "orcl") collateralTypes[coinName][collateralType].orcl = OracleLike(addr);
        else revert("MultiOracleRelayer/modify-unrecognized-param");

        emit ModifyParameters(
            coinName,
            collateralType,
            parameter,
            addr
        );
    }
    /**
     * @notice Modify redemption rate/price related parameters
     * @param coinName The name of the coin for which we modify a param
     * @param parameter Name of the parameter
     * @param data New param value
     */
    function modifyParameters(bytes32 coinName, bytes32 parameter, uint256 data) external isAuthorized(coinName) {
        require(coinEnabled[coinName] == 1, "MultiOracleRelayer/coin-not-enabled");
        require(coinInitialized[coinName] == 1, "MultiOracleRelayer/coin-not-init");
        require(data > 0, "MultiOracleRelayer/null-data");

        if (parameter == "redemptionPrice") {
          _redemptionPrice[coinName] = data;
        }
        else if (parameter == "redemptionRate") {
          require(now == redemptionPriceUpdateTime[coinName], "MultiOracleRelayer/redemption-price-not-updated");
          uint256 adjustedRate = data;
          if (data > redemptionRateUpperBound[coinName]) {
            adjustedRate = redemptionRateUpperBound[coinName];
          } else if (data < redemptionRateLowerBound[coinName]) {
            adjustedRate = redemptionRateLowerBound[coinName];
          }
          redemptionRate[coinName] = adjustedRate;
        }
        else if (parameter == "redemptionRateUpperBound") {
          require(data > RAY, "MultiOracleRelayer/invalid-redemption-rate-upper-bound");
          redemptionRateUpperBound[coinName] = data;
        }
        else if (parameter == "redemptionRateLowerBound") {
          require(data < RAY, "MultiOracleRelayer/invalid-redemption-rate-lower-bound");
          redemptionRateLowerBound[coinName] = data;
        }
        else revert("MultiOracleRelayer/modify-unrecognized-param");
        emit ModifyParameters(
            coinName,
            parameter,
            data
        );
    }
    /**
     * @notice Modify CRatio related parameters
     * @param coinName The name of the coin for which we modify a param
     * @param collateralType Collateral whose parameters we change
     * @param parameter Name of the parameter
     * @param data New param value
     */
    function modifyParameters(
        bytes32 coinName,
        bytes32 collateralType,
        bytes32 parameter,
        uint256 data
    ) external isAuthorized(coinName) {
        require(coinEnabled[coinName] == 1, "MultiOracleRelayer/coin-not-enabled");
        require(coinInitialized[coinName] == 1, "MultiOracleRelayer/coin-not-init");

        if (parameter == "safetyCRatio") {
          require(data >= collateralTypes[coinName][collateralType].liquidationCRatio, "MultiOracleRelayer/safety-lower-than-liquidation-cratio");
          collateralTypes[coinName][collateralType].safetyCRatio = data;
        }
        else if (parameter == "liquidationCRatio") {
          require(data <= collateralTypes[coinName][collateralType].safetyCRatio, "MultiOracleRelayer/safety-lower-than-liquidation-cratio");
          collateralTypes[coinName][collateralType].liquidationCRatio = data;
        }
        else revert("MultiOracleRelayer/modify-unrecognized-param");
        emit ModifyParameters(
            coinName,
            collateralType,
            parameter,
            data
        );
    }
    /**
     * @notice Set an address param
     * @param parameter The name of the parameter to change
     * @param data The new manager
     */
    function modifyParameters(bytes32 parameter, address data) external {
        require(manager == msg.sender, "MultiOracleRelayer/invalid-manager");
        if (parameter == "manager") {
          manager = data;
        } else if (parameter == "deployer") {
          require(data != address(0), "MultiOracleRelayer/null-deployer");
          deployer = data;
        }
        else revert("MultiOracleRelayer/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }

    // --- Redemption Price Update ---
    /**
     * @notice Update a redemption price using the current redemption rate for a coin
     * @param coinName The name of the coin for which the redemption price will get updated
     */
    function updateRedemptionPrice(bytes32 coinName) internal returns (uint256) {
        // Update redemption price
        _redemptionPrice[coinName] = rmultiply(
          rpower(redemptionRate[coinName], subtract(now, redemptionPriceUpdateTime[coinName]), RAY),
          _redemptionPrice[coinName]
        );
        if (_redemptionPrice[coinName] == 0) _redemptionPrice[coinName] = 1;
        redemptionPriceUpdateTime[coinName] = now;
        emit UpdateRedemptionPrice(coinName, _redemptionPrice[coinName]);
        // Return the updated redemption price
        return _redemptionPrice[coinName];
    }
    /**
     * @notice Fetch the latest redemption price for a specific coin by first updating it
     * @param coinName The name of the coin for which to fetch the redemption price
     */
    function redemptionPrice(bytes32 coinName) public returns (uint256) {
        if (coinEnabled[coinName] == 0) return 0;
        if (now > redemptionPriceUpdateTime[coinName]) return updateRedemptionPrice(coinName);
        return _redemptionPrice[coinName];
    }

    // --- Update value ---
    /**
     * @notice Update the collateral price inside the system (inside SAFEEngine)
     * @param collateralType The collateral we want to update prices (safety and liquidation prices) for
     */
    function updateCollateralPrice(bytes32 coinName, bytes32 collateralType) external {
        require(coinEnabled[coinName] == 1, "MultiOracleRelayer/coin-not-enabled");
        require(coinInitialized[coinName] == 1, "MultiOracleRelayer/coin-not-init");

        (uint256 priceFeedValue, bool hasValidValue) =
          collateralTypes[coinName][collateralType].orcl.getResultWithValidity();
        uint256 redemptionPrice_ = redemptionPrice(coinName);
        uint256 safetyPrice_ = hasValidValue ? rdivide(rdivide(multiply(uint256(priceFeedValue), 10 ** 9), redemptionPrice_), collateralTypes[coinName][collateralType].safetyCRatio) : 0;
        uint256 liquidationPrice_ = hasValidValue ? rdivide(rdivide(multiply(uint256(priceFeedValue), 10 ** 9), redemptionPrice_), collateralTypes[coinName][collateralType].liquidationCRatio) : 0;

        safeEngine.modifyParameters(coinName, collateralType, "safetyPrice", safetyPrice_);
        safeEngine.modifyParameters(coinName, collateralType, "liquidationPrice", liquidationPrice_);
        emit UpdateCollateralPrice(coinName, collateralType, priceFeedValue, safetyPrice_, liquidationPrice_);
    }

    /**
     * @notice Disable a specific coin
     */
    function disableCoin(bytes32 coinName) external isSystemComponent {
        coinEnabled[coinName]    = 0;
        redemptionRate[coinName] = RAY;
        emit DisableCoin(coinName);
    }

    /**
     * @notice Fetch the safety CRatio of a specific collateral type for a specific coin
     * @param coinName The name of the coin
     * @param collateralType The collateral type we want the safety CRatio for
     */
    function safetyCRatio(bytes32 coinName, bytes32 collateralType) public view returns (uint256) {
        return collateralTypes[coinName][collateralType].safetyCRatio;
    }
    /**
     * @notice Fetch the liquidation CRatio of a specific collateral type for a specific coin
     * @param coinName The name of the coin
     * @param collateralType The collateral type we want the liquidation CRatio for
     */
    function liquidationCRatio(bytes32 coinName, bytes32 collateralType) public view returns (uint256) {
        return collateralTypes[coinName][collateralType].liquidationCRatio;
    }
    /**
     * @notice Fetch the oracle price feed of a specific collateral type for a specific coin
     * @param coinName The name of the coin
     * @param collateralType The collateral type we want the oracle price feed for
     */
    function orcl(bytes32 coinName, bytes32 collateralType) public view returns (address) {
        return address(collateralTypes[coinName][collateralType].orcl);
    }
}
