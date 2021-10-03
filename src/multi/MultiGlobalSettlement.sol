/// MultiGlobalSettlement.sol

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
// Copyright (C) 2018 Lev Livnev <lev@liv.nev.org.uk>
//
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
    function collateralFamily(bytes32, bytes32) virtual public view returns (bytes32);
    function coinBalance(bytes32,address) virtual public view returns (uint256);
    function collateralTypes(bytes32,bytes32) virtual public view returns (
        uint256 debtAmount,        // [wad]
        uint256 accumulatedRate,   // [ray]
        uint256 safetyPrice,       // [ray]
        uint256 debtCeiling,       // [rad]
        uint256 debtFloor,         // [rad]
        uint256 liquidationPrice   // [ray]
    );
    function safes(bytes32,bytes32,bytes32,address) virtual public view returns (
        uint256 lockedCollateral, // [wad]
        uint256 generatedDebt     // [wad]
    );
    function globalDebt(bytes32) virtual public returns (uint256);
    function transferInternalCoins(bytes32 coinName, address src, address dst, uint256 rad) virtual external;
    function approveSAFEModification(bytes32,address) virtual external;
    function transferCollateral(bytes32 coinName, bytes32 collateralType, bytes32 subCollateral, address src, address dst, uint256 wad) virtual external;
    function confiscateSAFECollateralAndDebt(bytes32 coinName, bytes32 collateralType, bytes32 subCollateral, address safe, address collateralSource, address debtDestination, int256 deltaCollateral, int256 deltaDebt) virtual external;
    function createUnbackedDebt(bytes32 coinName, address debtDestination, address coinDestination, uint256 rad) virtual external;
    function disableCoin(bytes32) virtual external;
}
abstract contract LiquidationEngineLike {
    function collateralTypes(bytes32,bytes32) virtual public view returns (
        address liquidationPool,
        address collateralAuctionHouse,
        uint256 liquidationPenalty,     // [wad]
        uint256 liquidationQuantity     // [rad]
    );
    function disableCoin(bytes32) virtual external;
}
abstract contract StabilityFeeTreasuryLike {
    function disableCoin(bytes32) virtual external;
}
abstract contract AccountingEngineLike {
    function disableCoin(bytes32) virtual external;
}
abstract contract CollateralAuctionHouseLike {
    function subCollateral(uint256 id) virtual public view returns (bytes32);
    function bidAmount(uint256 id) virtual public view returns (uint256);
    function raisedAmount(uint256 id) virtual public view returns (uint256);
    function remainingAmountToSell(uint256 id) virtual public view returns (uint256);
    function forgoneCollateralReceiver(uint256 id) virtual public view returns (address);
    function amountToRaise(uint256 id) virtual public view returns (uint256);
    function terminateAuctionPrematurely(uint256 auctionId) virtual external;
}
abstract contract OracleLike {
    function read() virtual public view returns (uint256);
}
abstract contract OracleRelayerLike {
    function redemptionPrice(bytes32) virtual public returns (uint256);
    function collateralTypes(bytes32,bytes32) virtual public view returns (
        OracleLike orcl,
        uint256 safetyCRatio,
        uint256 liquidationCRatio
    );
    function disableCoin(bytes32) virtual external;
}

/*
    This is the Global Settlement module. It is an
    involved, stateful process that takes place over nine steps.
    First we freeze the system and lock the prices for each collateral type.
    1. `shutdownCoin(coinName)`:
        - freezes user entrypoints
        - starts cooldown period
    2. `freezeCollateralType(coinName, collateralType)`:
       - set the final price for each collateralType for a specific coin, reading off the price feed
    We must process some system state before it is possible to calculate
    the final coin / collateral price. In particular, we need to determine:
      a. `collateralShortfall` (considers under-collateralised SAFEs)
      b. `outstandingCoinSupply` (after including system surplus / deficit)
    We determine (a) by processing all under-collateralised SAFEs with
    `processSAFE`
    3. `processSAFE(coinName, collateralType, subCollateral, safe)`:
       - cancels SAFE debt
       - any excess collateral remains
       - backing collateral taken
    We determine (b) by processing ongoing coin generating processes,
    i.e. auctions. We need to ensure that auctions will not generate any
    further coin income. In the two-way auction model this occurs when
    all auctions are in the reverse (`decreaseSoldAmount`) phase. There are two ways
    of ensuring this:
    4.  i) `shutdownCooldown`: set the cooldown period to be at least as long as the
           longest auction duration, which needs to be determined by the
           shutdown administrator.
           This takes a fairly predictable time to occur but with altered
           auction dynamics due to the now varying price of the system coin.
       ii) `fastTrackAuction`: cancel all ongoing auctions and seize the collateral.
           This allows for faster processing at the expense of more
           processing calls. This option allows coin holders to retrieve
           their collateral faster.
           `fastTrackAuction(coinName, collateralType, auctionId)`:
            - cancel individual collateral auctions in the `increaseBidSize` (forward) phase
            - retrieves collateral and returns coins to bidder
            - `decreaseSoldAmount` (reverse) phase auctions can continue normally
    Option (i), `shutdownCooldown`, is sufficient for processing the system
    settlement but option (ii), `fastTrackAuction`, will speed it up. Both options
    are available in this implementation, with `fastTrackAuction` being enabled on a
    per-auction basis.
    When a SAFE has been processed and has no debt remaining, the
    remaining collateral can be removed.
    5. `freeCollateral(coinName, collateralType, subCollateral)`:
        - remove collateral from the caller's SAFE
        - owner can call as needed
    After the processing period has elapsed, we enable calculation of
    the final price for each collateral type.
    6. `setOutstandingCoinSupply(coinName)`:
       - only callable after processing time period elapsed
       - assumption that all under-collateralised SAFEs are processed
       - fixes the total outstanding supply of coin
       - may also require extra SAFE processing to cover system surplus
    7. `calculateCashPrice(collateralType)`:
        - calculate `collateralCashPrice`
        - adjusts `collateralCashPrice` in the case of deficit / surplus
    At this point we have computed the final price for each collateral
    type and coin holders can now turn their coin into collateral. Each
    unit coin can claim a fixed basket of collateral.
    Coin holders must first `prepareCoinsForRedeeming` into a `coinBag`. Once prepared,
    coins cannot be transferred out of the bag. More coin can be added to a bag later.
    8. `prepareCoinsForRedeeming(coinName, coinAmount)`:
        - put some coins into a bag in order to 'redeemCollateral'. The bigger the bag, the more collateral the user can claim.
    9. `redeemCollateral(coinName, collateralType, subCollateral, collateralAmount)`:
        - exchange some coin from your bag for tokens from a specific sub-collateral from a collateral type
        - the amount of sub-collateral available to redeem is limited by how big your bag is
*/

contract MultiGlobalSettlement {
    // --- Auth ---
    mapping (bytes32 => mapping(address => uint256)) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(bytes32 coinName, address account) external isAuthorized(coinName) {
        require(coinEnabled[coinName] == 1, "MultiGlobalSettlement/coin-not-enabled");
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
        require(authorizedAccounts[coinName][msg.sender] == 1, "MultiGlobalSettlement/account-not-authorized");
        _;
    }

    mapping (bytes32 => mapping(address => uint256)) public disableTriggers;
    /**
     * @notice Add a disable trigger
     * @param trigger Trigger to auth
     */
    function addTrigger(bytes32 coinName, address trigger) external isAuthorized(coinName) {
        disableTriggers[coinName][trigger] = 1;
        emit AddDisableTrigger(coinName, trigger);
    }
    /**
     * @notice Remove a disable trigger
      @param trigger Trigger to deauth
     */
    function removeTrigger(bytes32 coinName, address trigger) external isAuthorized(coinName) {
        disableTriggers[coinName][trigger] = 0;
        emit RemoveDisableTrigger(coinName, trigger);
    }
    /**
    * @notice Checks whether msg.sender is a trigger for a coin
    **/
    modifier isTrigger(bytes32 coinName) {
        require(disableTriggers[coinName][msg.sender] == 1, "MultiGlobalSettlement/account-not-trigger");
        _;
    }

    // --- Data ---
    SAFEEngineLike           public safeEngine;
    LiquidationEngineLike    public liquidationEngine;
    AccountingEngineLike     public accountingEngine;
    OracleRelayerLike        public oracleRelayer;

    // Manager address
    address                  public manager;
    // Address of the deployer
    address                  public deployer;
    // The amount of time post settlement during which no processing takes place
    uint256                  public shutdownCooldown;

    // Mapping of coin states
    mapping(bytes32 => uint256) public coinEnabled;
    // Whether a coin has been initialized or not
    mapping(bytes32 => uint256) public coinInitialized;

    // The timestamp when settlement was triggered for a specific coin
    mapping(bytes32 => uint256) public shutdownTime;                                                 // [timestamp]
    // The outstanding supply of system coins computed during the setOutstandingCoinSupply(coinName) phase
    mapping(bytes32 => uint256) public outstandingCoinSupply;                                        // [rad]

    // The amount of collateral that a system coin can redeem
    mapping (bytes32 => mapping(bytes32 => uint256))  public finalCoinPerCollateralPrice;            // [ray]
    // Total amount of bad debt in SAFEs with different collateral types
    mapping (bytes32 => mapping(bytes32 => uint256))  public collateralShortfall;                    // [wad]
    // Total debt backed by every collateral type
    mapping (bytes32 => mapping(bytes32 => uint256))  public collateralTotalDebt;                    // [wad]
    // Mapping of collateral prices in terms of system coins after taking into account system surplus/deficit and finalCoinPerCollateralPrices
    mapping (bytes32 => mapping(bytes32 => uint256))  public collateralCashPrice;                    // [ray]

    // Bags of coins ready to be used for collateral redemption
    mapping (bytes32 => mapping(address => uint256))  public coinBag;                                // [wad]
    // Amount of coins already used for collateral redemption by every address and for different collateral types
    mapping (bytes32 => mapping(bytes32 => mapping (address => uint256))) public coinsUsedToRedeem;  // [wad]
    // Contracts that keep collateral for each individual coin
    mapping (bytes32 => address)                      public collateralHolder;

    // --- Events ---
    event AddAuthorization(bytes32 indexed coinName, address account);
    event RemoveAuthorization(bytes32 indexed coinName, address account);
    event AddDisableTrigger(bytes32 indexed coinName, address trigger);
    event RemoveDisableTrigger(bytes32 indexed coinName, address trigger);
    event ModifyParameters(bytes32 parameter, address data);
    event ShutdownCoin(bytes32 indexed coinName);
    event InitializeCoin(bytes32 indexed coinName);
    event FreezeCollateralType(bytes32 indexed coinName, bytes32 indexed collateralType, uint256 finalCoinPerCollateralPrice);
    event FastTrackAuction(bytes32 indexed coinName, bytes32 indexed collateralType, uint256 auctionId, uint256 collateralTotalDebt);
    event ProcessSAFE(bytes32 indexed coinName, bytes32 indexed collateralType, bytes32 indexed subCollateral, address safe, uint256 collateralShortfall);
    event FreeCollateral(bytes32 indexed coinName, bytes32 indexed collateralType, bytes32 indexed subCollateral, address sender, int256 collateralAmount);
    event SetOutstandingCoinSupply(bytes32 indexed coinName, uint256 outstandingCoinSupply);
    event CalculateCashPrice(bytes32 indexed coinName, bytes32 indexed collateralType, uint256 collateralCashPrice);
    event PrepareCoinsForRedeeming(bytes32 indexed coinName, address indexed sender, uint256 coinBag);
    event RedeemCollateral(bytes32 indexed coinName, bytes32 indexed collateralType, bytes32 indexed subCollateral, address indexed sender, uint256 coinsAmount, uint256 collateralAmount);

    // --- Modifiers ---
    /**
     * @notice Checks whether a sub-collateral is part of a collateral family
     */
    modifier isSubCollateral(bytes32 collateralType, bytes32 subCollateral) {
        require(safeEngine.collateralFamily(collateralType, subCollateral) == 1, "MultiGlobalSettlement/not-in-family");
        _;
    }

    // --- Init ---
    constructor(uint256 shutdownCooldown_) public {
        require(shutdownCooldown_ > 0, "MultiGlobalSettlement/invalid-shutdown-cooldown");
        require(addition(now, shutdownCooldown_) <= uint(-1), "MultiGlobalSettlement/large-shutdown-cooldown");

        manager          = msg.sender;
        deployer         = msg.sender;
        shutdownCooldown = shutdownCooldown_;
    }

    // --- Math ---
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;

    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x + y;
        require(z >= x, "MultiGlobalSettlement/add-overflow");
    }
    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "MultiGlobalSettlement/sub-underflow");
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "MultiGlobalSettlement/mul-overflow");
    }
    function minimum(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x <= y ? x : y;
    }
    function rmultiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = multiply(x, y) / RAY;
    }
    function rdivide(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0, "MultiGlobalSettlement/rdiv-by-zero");
        z = multiply(x, RAY) / y;
    }
    function wdivide(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0, "MultiGlobalSettlement/wdiv-by-zero");
        z = multiply(x, WAD) / y;
    }

    // --- Administration ---
    /**
     * @notice Initialize a new coin
     * @param coinName The name of the coin to initialize
     */
    function initializeCoin(bytes32 coinName) external {
        require(deployer == msg.sender, "MultiGlobalSettlement/caller-not-deployer");
        require(coinInitialized[coinName] == 0, "MultiGlobalSettlement/already-init");
        require(address(safeEngine) != address(0), "MultiGlobalSettlement/null-safe-engine");

        authorizedAccounts[coinName][msg.sender] = 1;

        coinInitialized[coinName]  = 1;
        coinEnabled[coinName]      = 1;

        collateralHolder[coinName] = address(new SettlementCollateralHolder(address(safeEngine), coinName));

        emit InitializeCoin(coinName);
        emit AddAuthorization(coinName, msg.sender);
    }
    /*
    * @notify Modify an address parameter
    * @param parameter The name of the parameter to modify
    * @param data The new address for the parameter
    */
    function modifyParameters(bytes32 parameter, address data) external {
        require(manager == msg.sender, "MultiGlobalSettlement/invalid-manager");
        if (parameter == "safeEngine") safeEngine = SAFEEngineLike(data);
        else if (parameter == "liquidationEngine") liquidationEngine = LiquidationEngineLike(data);
        else if (parameter == "accountingEngine") accountingEngine = AccountingEngineLike(data);
        else if (parameter == "oracleRelayer") oracleRelayer = OracleRelayerLike(data);
        else if (parameter == "manager") manager = data;
        else if (parameter == "deployer") {
          require(data != address(0), "MultiGlobalSettlement/null-deployer");
          deployer = data;
        }
        else revert("MultiGlobalSettlement/modify-unrecognized-parameter");
        emit ModifyParameters(parameter, data);
    }

    // --- Settlement ---
    /**
     * @notice Freeze the system and start the cooldown period
     * @param coinName The name of the coin to shut down
     */
    function shutdownCoin(bytes32 coinName) external isTrigger(coinName) {
        require(coinEnabled[coinName] == 1, "MultiGlobalSettlement/coin-not-enabled");
        require(coinInitialized[coinName] == 1, "MultiGlobalSettlement/coin-not-init");

        coinEnabled[coinName]  = 0;
        shutdownTime[coinName] = now;

        safeEngine.disableCoin(coinName);
        liquidationEngine.disableCoin(coinName);
        accountingEngine.disableCoin(coinName);
        oracleRelayer.disableCoin(coinName);

        emit ShutdownCoin(coinName);
    }
    /**
     * @notice Calculate a collateral type's final price according to the latest system coin redemption price
     * @param coinName The name of the coin to freeze collateral for
     * @param collateralType The collateral type to calculate the price for
     */
    function freezeCollateralType(bytes32 coinName, bytes32 collateralType) external {
        require(coinEnabled[coinName] == 0, "MultiGlobalSettlement/coin-not-disabled");
        require(coinInitialized[coinName] == 1, "MultiGlobalSettlement/coin-not-init");

        require(finalCoinPerCollateralPrice[coinName][collateralType] == 0, "MultiGlobalSettlement/final-collateral-price-already-defined");
        (collateralTotalDebt[coinName][collateralType],,,,,) = safeEngine.collateralTypes(coinName, collateralType);
        (OracleLike orcl,,) = oracleRelayer.collateralTypes(coinName, collateralType);
        // redemptionPrice is a ray, orcl returns a wad
        finalCoinPerCollateralPrice[coinName][collateralType] = wdivide(oracleRelayer.redemptionPrice(coinName), uint256(orcl.read()));
        emit FreezeCollateralType(coinName, collateralType, finalCoinPerCollateralPrice[coinName][collateralType]);
    }
    /**
     * @notice Fast track an ongoing collateral auction
     * @param coinName The name of the coin to fasttrack an auction for
     * @param collateralType The collateral type associated with the auction contract
     * @param auctionId The ID of the auction to be fast tracked
     */
    function fastTrackAuction(bytes32 coinName, bytes32 collateralType, uint256 auctionId) external {
        require(finalCoinPerCollateralPrice[coinName][collateralType] != 0, "MultiGlobalSettlement/final-collateral-price-not-defined");

        (,address auctionHouse_,,)        = liquidationEngine.collateralTypes(coinName, collateralType);
        CollateralAuctionHouseLike collateralAuctionHouse = CollateralAuctionHouseLike(auctionHouse_);
        (, uint256 accumulatedRate,,,,)   = safeEngine.collateralTypes(coinName, collateralType);

        uint256 raisedAmount              = collateralAuctionHouse.raisedAmount(auctionId);
        uint256 collateralToSell          = collateralAuctionHouse.remainingAmountToSell(auctionId);
        address forgoneCollateralReceiver = collateralAuctionHouse.forgoneCollateralReceiver(auctionId);
        uint256 amountToRaise             = collateralAuctionHouse.amountToRaise(auctionId);
        bytes32 subCollateral             = collateralAuctionHouse.subCollateral(auctionId);

        safeEngine.createUnbackedDebt(coinName, address(accountingEngine), address(accountingEngine), subtract(amountToRaise, raisedAmount));
        safeEngine.createUnbackedDebt(coinName, address(accountingEngine), address(this), collateralAuctionHouse.bidAmount(auctionId));
        safeEngine.approveSAFEModification(coinName, address(collateralAuctionHouse));
        collateralAuctionHouse.terminateAuctionPrematurely(auctionId);

        collateralTotalDebt[coinName][collateralType] =
          addition(collateralTotalDebt[coinName][collateralType], subtract(amountToRaise, raisedAmount) / accumulatedRate);
        require(int256(collateralToSell) >= 0 && int256(subtract(amountToRaise, raisedAmount) / accumulatedRate) >= 0, "MultiGlobalSettlement/overflow");
        safeEngine.confiscateSAFECollateralAndDebt(
          coinName,
          collateralType,
          subCollateral,
          forgoneCollateralReceiver,
          address(this),
          address(accountingEngine),
          int256(collateralToSell),
          int256(subtract(amountToRaise, raisedAmount) / accumulatedRate)
        );
        emit FastTrackAuction(coinName, collateralType, auctionId, collateralTotalDebt[coinName][collateralType]);
    }
    /**
     * @notice Cancel a SAFE's debt and leave any extra collateral in it
     * @param coinName The name of the coin to process a SAFE for
     * @param collateralType The collateral type associated with the SAFE
     * @param subCollateral The sub-collateral associated with the collateral type
     * @param safe The SAFE to be processed
     */
    function processSAFE(bytes32 coinName, bytes32 collateralType, bytes32 subCollateral, address safe)
      external isSubCollateral(collateralType, subCollateral) {
        require(finalCoinPerCollateralPrice[coinName][collateralType] != 0, "MultiGlobalSettlement/final-collateral-price-not-defined");
        (, uint256 accumulatedRate,,,,) = safeEngine.collateralTypes(coinName, collateralType);
        (uint256 safeCollateral, uint256 safeDebt) = safeEngine.safes(coinName, collateralType, subCollateral, safe);

        uint256 amountOwed    = rmultiply(rmultiply(safeDebt, accumulatedRate), finalCoinPerCollateralPrice[coinName][collateralType]);
        uint256 minCollateral = minimum(safeCollateral, amountOwed);
        collateralShortfall[coinName][collateralType] = addition(
            collateralShortfall[coinName][collateralType],
            subtract(amountOwed, minCollateral)
        );

        require(minCollateral <= 2**255 && safeDebt <= 2**255, "MultiGlobalSettlement/overflow");
        safeEngine.confiscateSAFECollateralAndDebt(
            coinName,
            collateralType,
            subCollateral,
            safe,
            collateralHolder[coinName],
            address(accountingEngine),
            -int256(minCollateral),
            -int256(safeDebt)
        );

        emit ProcessSAFE(coinName, collateralType, subCollateral, safe, collateralShortfall[coinName][collateralType]);
    }
    /**
     * @notice Remove collateral from the caller's SAFE
     * @param coinName The name of the coin to free collateral for
     * @param collateralType The collateral type to free
     * @param subCollateral The sub-collateral type associated with the main collateral
     */
    function freeCollateral(bytes32 coinName, bytes32 collateralType, bytes32 subCollateral)
      external isSubCollateral(collateralType, subCollateral) {
        require(coinEnabled[coinName] == 0, "MultiGlobalSettlement/coin-not-disabled");
        require(coinInitialized[coinName] == 1, "MultiGlobalSettlement/coin-not-init");
        (uint256 safeCollateral, uint256 safeDebt) = safeEngine.safes(coinName, collateralType, subCollateral, msg.sender);
        require(safeDebt == 0, "MultiGlobalSettlement/safe-debt-not-zero");
        require(safeCollateral <= 2**255, "MultiGlobalSettlement/overflow");
        safeEngine.confiscateSAFECollateralAndDebt(
          coinName,
          collateralType,
          subCollateral,
          msg.sender,
          msg.sender,
          address(accountingEngine),
          -int256(safeCollateral),
          0
        );
        emit FreeCollateral(coinName, collateralType, subCollateral, msg.sender, -int256(safeCollateral));
    }
    /**
     * @notice Set the final outstanding supply of system coins
     * @param coinName The name of the coin to set the outstanding supply for
     * @dev There must be no remaining surplus in the accounting engine
     */
    function setOutstandingCoinSupply(bytes32 coinName) external {
        require(coinEnabled[coinName] == 0, "MultiGlobalSettlement/coin-not-disabled");
        require(coinInitialized[coinName] == 1, "MultiGlobalSettlement/coin-not-init");
        require(outstandingCoinSupply[coinName] == 0, "MultiGlobalSettlement/outstanding-coin-supply-not-zero");
        require(safeEngine.coinBalance(coinName, address(accountingEngine)) == 0, "MultiGlobalSettlement/surplus-not-zero");
        require(now >= addition(shutdownTime[coinName], shutdownCooldown), "MultiGlobalSettlement/shutdown-cooldown-not-finished");
        outstandingCoinSupply[coinName] = safeEngine.globalDebt(coinName);
        emit SetOutstandingCoinSupply(coinName, outstandingCoinSupply[coinName]);
    }
    /**
     * @notice Calculate a collateral's price taking into consideration system surplus/deficit and the finalCoinPerCollateralPrice
     * @param coinName The name of the coin to calculate the cash price for
     * @param collateralType The collateral whose cash price will be calculated
     */
    function calculateCashPrice(bytes32 coinName, bytes32 collateralType) external {
        require(outstandingCoinSupply[coinName] != 0, "MultiGlobalSettlement/outstanding-coin-supply-zero");
        require(collateralCashPrice[coinName][collateralType] == 0, "MultiGlobalSettlement/collateral-cash-price-already-defined");

        (, uint256 accumulatedRate,,,,) = safeEngine.collateralTypes(coinName, collateralType);
        uint256 redemptionAdjustedDebt = rmultiply(
          rmultiply(collateralTotalDebt[coinName][collateralType], accumulatedRate), finalCoinPerCollateralPrice[coinName][collateralType]
        );
        collateralCashPrice[coinName][collateralType] =
          multiply(subtract(redemptionAdjustedDebt, collateralShortfall[coinName][collateralType]), RAY) / (outstandingCoinSupply[coinName] / RAY);

        emit CalculateCashPrice(coinName, collateralType, collateralCashPrice[coinName][collateralType]);
    }
    /**
     * @notice Add coins into a 'bag' so that you can use them to redeem collateral
     * @param coinName The name of the coin to prepare
     * @param coinAmount The amount of internal system coins to add into the bag
     */
    function prepareCoinsForRedeeming(bytes32 coinName, uint256 coinAmount) external {
        require(outstandingCoinSupply[coinName] != 0, "MultiGlobalSettlement/outstanding-coin-supply-zero");
        safeEngine.transferInternalCoins(coinName, msg.sender, address(accountingEngine), multiply(coinAmount, RAY));
        coinBag[coinName][msg.sender] = addition(coinBag[coinName][msg.sender], coinAmount);
        emit PrepareCoinsForRedeeming(coinName, msg.sender, coinBag[coinName][msg.sender]);
    }
    /**
     * @notice Redeem a specific collateral type using an amount of internal system coins from your bag
     * @param coinName The name of the coin to redeem collateral with
     * @param collateralType The collateral type to redeem
     * @param subCollateral The sub-collateral that's part of the main collateral's family
     * @param coinsAmount The amount of internal coins to use from your bag
     */
    function redeemCollateral(bytes32 coinName, bytes32 collateralType, bytes32 subCollateral, uint256 coinsAmount)
      external isSubCollateral(collateralType, subCollateral) {
        require(collateralCashPrice[coinName][collateralType] != 0, "MultiGlobalSettlement/collateral-cash-price-not-defined");
        uint256 collateralAmount = rmultiply(coinsAmount, collateralCashPrice[coinName][collateralType]);
        safeEngine.transferCollateral(
          coinName,
          collateralType,
          subCollateral,
          collateralHolder[coinName],
          msg.sender,
          collateralAmount
        );
        coinsUsedToRedeem[coinName][collateralType][msg.sender] =
          addition(coinsUsedToRedeem[coinName][collateralType][msg.sender], coinsAmount);
        require(coinsUsedToRedeem[coinName][collateralType][msg.sender] <= coinBag[coinName][msg.sender], "MultiGlobalSettlement/insufficient-bag-balance");
        emit RedeemCollateral(coinName, collateralType, subCollateral, msg.sender, coinsAmount, collateralAmount);
    }
}

/*
* @notice This thing keeps collateral for the GlobalSettlement contract
*/
contract SettlementCollateralHolder {
    constructor(address safeEngine, bytes32 coinName) public {
        require(safeEngine != address(0), "SettlementCollateralHolder/null-safe-engine");
        SAFEEngineLike(safeEngine).approveSAFEModification(coinName, msg.sender);
    }
}
