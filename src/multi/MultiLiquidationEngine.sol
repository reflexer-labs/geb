/// MultiLiquidationEngine.sol

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
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

abstract contract CollateralAuctionHouseLike {
    function coinName() virtual public view returns (bytes32);
    function startAuction(
      bytes32 subCollateral,
      address forgoneCollateralReceiver,
      address initialBidder,
      uint256 amountToRaise,
      uint256 collateralToSell,
      uint256 initialBid
    ) virtual public returns (uint256);
}
abstract contract SAFESaviourLike {
    function saveSAFE(bytes32,address,bytes32,bytes32,address) virtual external returns (bool,uint256,uint256);
}
abstract contract LiquidationPoolLike {
    function canLiquidate(bytes32,bytes32,bytes32,uint256,uint256) virtual external returns (bool);
    function liquidateSAFE(bytes32,bytes32,bytes32,uint256,uint256,address) virtual external returns (bool);
}
abstract contract SAFEEngineLike {
    function collateralFamily(bytes32,bytes32) virtual public view returns (uint256);
    function tokenCollateral(bytes32,bytes32,address) virtual public view returns (uint256);
    function collateralTypes(bytes32,bytes32) virtual public view returns (
        uint256 debtAmount,        // [wad]
        uint256 accumulatedRate,   // [ray]
        uint256 safetyPrice,       // [ray]
        uint256 debtCeiling,       // [rad]
        uint256 debtFloor,         // [rad]
        uint256 liquidationPrice   // [ray]
    );
    function safes(bytes32,bytes32,bytes32,address) virtual public view returns (
        uint256 lockedCollateral,  // [wad]
        uint256 generatedDebt      // [wad]
    );
    function confiscateSAFECollateralAndDebt(bytes32,bytes32,bytes32,address,address,address,int256,int256) virtual external;
    function canModifySAFE(bytes32,address,address) virtual public view returns (bool);
    function approveSAFEModification(bytes32,address) virtual external;
    function denySAFEModification(bytes32,address) virtual external;
}
abstract contract AccountingEngineLike {
    function pushDebtToQueue(bytes32,uint256) virtual external;
}

contract MultiLiquidationEngine {
    // --- Auth ---
    mapping (bytes32 => mapping(address => uint256)) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(bytes32 coinName, address account) external isAuthorized(coinName) {
        require(coinEnabled[coinName] == 1, "MultiLiquidationEngine/coin-not-enabled");
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
        require(authorizedAccounts[coinName][msg.sender] == 1, "MultiLiquidationEngine/account-not-authorized");
        _;
    }

    mapping (address => uint256) public systemComponents;
    /**
     * @notice Add a system component
     * @param component Component to auth
     */
    function addSystemComponent(address component) external {
        require(manager == msg.sender, "MultiLiquidationEngine/invalid-manager");
        systemComponents[component] = 1;
        emit AddSystemComponent(component);
    }
    /**
     * @notice Remove a system component
      @param component Component to deauth
     */
    function removeSystemComponent(address component) external {
        require(manager == msg.sender, "MultiLiquidationEngine/invalid-manager");
        systemComponents[component] = 0;
        emit RemoveSystemComponent(component);
    }
    /**
    /**
    * @notice Checks whether msg.sender is a system component
    **/
    modifier isSystemComponent {
        require(systemComponents[msg.sender] == 1, "MultiLiquidationEngine/account-not-component");
        _;
    }

    // --- SAFE Saviours ---
    // Contracts that can save SAFEs from liquidation
    mapping (bytes32 => mapping(address => uint256)) public safeSaviours;
    /**
    * @notice Authed function to add contracts that can save SAFEs from liquidation
    * @param saviour SAFE saviour contract to be whitelisted
    **/
    function connectSAFESaviour(bytes32 coinName, address saviour) external isAuthorized(coinName) {
        (bool ok, uint256 collateralAdded, uint256 liquidatorReward) =
          SAFESaviourLike(saviour).saveSAFE(coinName, address(this), "", "", address(0));
        require(ok, "MultiLiquidationEngine/saviour-not-ok");
        require(both(collateralAdded == uint256(-1), liquidatorReward == uint256(-1)), "MultiLiquidationEngine/invalid-amounts");
        safeSaviours[coinName][saviour] = 1;
        emit ConnectSAFESaviour(coinName, saviour);
    }
    /**
    * @notice Governance used function to remove contracts that can save SAFEs from liquidation
    * @param saviour SAFE saviour contract to be removed
    **/
    function disconnectSAFESaviour(bytes32 coinName, address saviour) external isAuthorized(coinName) {
        safeSaviours[coinName][saviour] = 0;
        emit DisconnectSAFESaviour(coinName, saviour);
    }

    // --- Data ---
    struct CollateralType {
        // Liquidation pool
        address liquidationPool;
        // Address of the collateral auction house handling liquidations for this collateral type
        address collateralAuctionHouse;
        // Penalty applied to every liquidation involving this collateral type. Discourages SAFE users from bidding on their own SAFEs
        uint256 liquidationPenalty;                                                                                                   // [wad]
        // Max amount of system coins to request in one auction
        uint256 liquidationQuantity;                                                                                                  // [rad]
    }

    // Collateral types included in the system for each individual system coin
    mapping (bytes32 => mapping(bytes32 => CollateralType))                               public collateralTypes;
    // Saviour contract chosen for each SAFE by its creator
    mapping (bytes32 => mapping(bytes32 => mapping(address => address)))                  public chosenSAFESaviour;
    // Mutex used to block against re-entrancy when 'liquidateSAFE' passes execution to a saviour
    mapping (bytes32 => mapping(bytes32 => mapping(bytes32 => mapping(address => uint8)))) public mutex;

    // Max amount of system coins that can be on liquidation at any time
    mapping(bytes32 => uint256)  public onAuctionSystemCoinLimit;     // [rad]
    // Current amount of system coins out for liquidation
    mapping(bytes32 => uint256)  public currentOnAuctionSystemCoins;  // [rad]
    // Mapping of coin states
    mapping (bytes32 => uint256) public coinEnabled;
    // Whether a coin has been initialized or not
    mapping (bytes32 => uint256) public coinInitialized;

    // Manager address
    address              public manager;
    // Address of the deployer
    address              public deployer;
    // SAFE database
    SAFEEngineLike       public safeEngine;
    // Accounting engine
    AccountingEngineLike public accountingEngine;

    // --- Events ---
    event AddAuthorization(bytes32 indexed coinName, address account);
    event RemoveAuthorization(bytes32 indexed coinName, address account);
    event InitializeCoin(bytes32 indexed coinName, uint256 onAuctionSystemCoinLimit);
    event AddSystemComponent(address component);
    event RemoveSystemComponent(address component);
    event ConnectSAFESaviour(bytes32 indexed coinName, address saviour);
    event DisconnectSAFESaviour(bytes32 indexed coinName, address saviour);
    event UpdateCurrentOnAuctionSystemCoins(uint256 currentOnAuctionSystemCoins);
    event FailLiquidationPoolLiquidate(
      bytes32 indexed coinName,
      bytes32 collateralType,
      bytes32 subCollateral,
      uint256 debtAmount,
      uint256 collateralAmount,
      bytes revertReason
    );
    event FailLiquidationPoolCanLiquidate(bytes32 indexed coinName, bytes32 collateralType, bytes32 subCollateral, bytes revertReason);
    event ModifyParameters(bytes32 indexed coinName, bytes32 parameter, uint256 data);
    event ModifyParameters(bytes32 indexed coinName, address data);
    event ModifyParameters(
      bytes32 indexed coinName,
      bytes32 collateralType,
      bytes32 parameter,
      uint256 data
    );
    event ModifyParameters(
      bytes32 indexed coinName,
      bytes32 collateralType,
      bytes32 parameter,
      address data
    );
    event ModifyParameters(
      bytes32 indexed coinName,
      bytes32 collateralType,
      bytes32 subCollateral,
      bytes32 parameter,
      address data
    );
    event DisableCoin(bytes32 indexed coinName);
    event Liquidate(
      bytes32 indexed coinName,
      bytes32 indexed collateralType,
      bytes32 indexed subCollateral,
      address safe,
      uint256 collateralAmount,
      uint256 debtAmount,
      uint256 amountToRaise,
      uint256 auctionId
    );
    event SaveSAFE(
      bytes32 indexed coinName,
      bytes32 indexed collateralType,
      bytes32 indexed subCollateral,
      address safe,
      uint256 collateralAddedOrDebtRepaid
    );
    event FailedSAFESave(bytes32 indexed coinName, bytes failReason);
    event ProtectSAFE(
      bytes32 indexed coinName,
      bytes32 indexed collateralType,
      address indexed safe,
      address saviour
    );

    // --- Modifiers ---
    /**
     * @notice Checks whether a sub-collateral is part of a collateral family
     */
    modifier isSubCollateral(bytes32 collateralType, bytes32 subCollateral) {
        require(safeEngine.collateralFamily(collateralType, subCollateral) == 1, "MultiLiquidationEngine/not-in-family");
        _;
    }

    // --- Init ---
    constructor(address safeEngine_) public {
        manager     = msg.sender;
        deployer    = msg.sender;
        safeEngine  = SAFEEngineLike(safeEngine_);
    }

    // --- Math ---
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant MAX_LIQUIDATION_QUANTITY = uint256(-1) / RAY;

    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "MultiLiquidationEngine/add-overflow");
    }
    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "MultiLiquidationEngine/sub-underflow");
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "MultiLiquidationEngine/mul-overflow");
    }
    function minimum(uint256 x, uint256 y) internal pure returns (uint256 z) {
        if (x > y) { z = y; } else { z = x; }
    }

    // --- Utils ---
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    // --- Administration ---
    /**
     * @notice Initialize a new coin
     * @param coinName The name of the coin
     * @param onAuctionSystemCoinLimit_ The on auction system coin limit for the coin
     */
    function initializeCoin(bytes32 coinName, uint256 onAuctionSystemCoinLimit_) external {
        require(deployer == msg.sender, "MultiLiquidationEngine/caller-not-deployer");
        require(coinInitialized[coinName] == 0, "MultiLiquidationEngine/already-init");
        require(onAuctionSystemCoinLimit_ > 0, "MultiLiquidationEngine/null-transfer-amount");

        authorizedAccounts[coinName][msg.sender] = 1;

        coinInitialized[coinName] = 1;
        coinEnabled[coinName]     = 1;

        onAuctionSystemCoinLimit[coinName] = onAuctionSystemCoinLimit_;

        emit InitializeCoin(coinName, onAuctionSystemCoinLimit_);
        emit AddAuthorization(coinName, msg.sender);
    }
    /*
    * @notice Modify uint256 parameters
    * @param coinName The name of the coin
    * @param parameter The name of the parameter modified
    * @param data Value for the new parameter
    */
    function modifyParameters(bytes32 coinName, bytes32 parameter, uint256 data) external isAuthorized(coinName) {
        if (parameter == "onAuctionSystemCoinLimit") {
          require(data > 0, "MultiLiquidationEngine/null-on-auction-coin-limit");
          onAuctionSystemCoinLimit[coinName] = data;
        }
        else if (parameter == "currentOnAuctionSystemCoins") {
          currentOnAuctionSystemCoins[coinName] = data;
        }
        else revert("MultiLiquidationEngine/modify-unrecognized-param");
        emit ModifyParameters(coinName, parameter, data);
    }
    /**
     * @notice Modify contract integrations
     * @param parameter The name of the parameter modified
     * @param data New address for the parameter
     */
    function modifyParameters(bytes32 parameter, address data) external {
        require(manager == msg.sender, "MultiLiquidationEngine/invalid-manager");
        if (parameter == "accountingEngine") accountingEngine = AccountingEngineLike(data);
        else if (parameter == "manager") {
          manager = data;
        } else if (parameter == "deployer") {
          require(data != address(0), "MultiLiquidationEngine/null-deployer");
          deployer = data;
        }
        else revert("MultiLiquidationEngine/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }
    /**
     * @notice Modify liquidation params
     * @param coinName The name of the coin
     * @param collateralType The collateral type we change parameters for
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(
        bytes32 coinName,
        bytes32 collateralType,
        bytes32 parameter,
        uint256 data
    ) external isAuthorized(coinName) {
        if (parameter == "liquidationPenalty") {
          require(data >= WAD, "MultiLiquidationEngine/invalid-liquidation-penalty");
          collateralTypes[coinName][collateralType].liquidationPenalty = data;
        }
        else if (parameter == "liquidationQuantity") {
          require(data <= MAX_LIQUIDATION_QUANTITY, "MultiLiquidationEngine/liquidation-quantity-overflow");
          collateralTypes[coinName][collateralType].liquidationQuantity = data;
        }
        else revert("MultiLiquidationEngine/modify-unrecognized-param");
        emit ModifyParameters(
          coinName,
          collateralType,
          parameter,
          data
        );
    }
    /**
     * @notice Modify address params (main collaterals)
     * @param coinName The name of the coin
     * @param collateralType The collateral type we change parameters for
     * @param parameter The name of the integration modified
     * @param data New address for the integration contract
     */
    function modifyParameters(
        bytes32 coinName,
        bytes32 collateralType,
        bytes32 parameter,
        address data
    ) external isAuthorized(coinName) {
        if (parameter == "collateralAuctionHouse") {
            safeEngine.denySAFEModification(coinName, collateralTypes[coinName][collateralType].collateralAuctionHouse);
            collateralTypes[coinName][collateralType].collateralAuctionHouse = data;
            safeEngine.approveSAFEModification(coinName, data);
        }
        else revert("MultiLiquidationEngine/modify-unrecognized-param");
        emit ModifyParameters(
            coinName,
            collateralType,
            parameter,
            data
        );
    }
    /**
     * @notice Modify address params (sub-collateral specific)
     * @param coinName The name of the coin
     * @param collateralType The collateral type we change parameters for
     * @param subCollateral The sub-collateral of the main collateral type
     * @param parameter The name of the integration modified
     * @param data New address for the integration contract
     */
    function modifyParameters(
        bytes32 coinName,
        bytes32 collateralType,
        bytes32 subCollateral,
        bytes32 parameter,
        address data
    ) external isSubCollateral(collateralType, subCollateral) isAuthorized(coinName) {
        if (parameter == "liquidationPool") {
            safeEngine.denySAFEModification(coinName, collateralTypes[coinName][collateralType].liquidationPool);
            collateralTypes[coinName][collateralType].liquidationPool = data;
            require(LiquidationPoolLike(data).canLiquidate(coinName, collateralType, subCollateral, uint(-1), uint(-1)), "MultiLiquidationEngine/faulty-liq-pool");
            safeEngine.approveSAFEModification(coinName, data);
        }
        else revert("MultiLiquidationEngine/modify-unrecognized-param");
        emit ModifyParameters(
            coinName,
            collateralType,
            subCollateral,
            parameter,
            data
        );
    }
    /**
     * @notice Disable a coin (normally called by Global Settlement)
     * @param coinName The coin to disable
     */
    function disableCoin(bytes32 coinName) external isSystemComponent {
        require(coinEnabled[coinName] == 1, "MultiLiquidationEngine/coin-not-enabled");
        require(coinInitialized[coinName] == 1, "MultiLiquidationEngine/coin-not-init");
        coinEnabled[coinName] = 0;
        emit DisableCoin(coinName);
    }

    // --- SAFE Liquidation ---
    /**
     * @notice Choose a saviour contract for your SAFE
     * @param coinName The name of the coin for which to protect a SAFE
     * @param collateralType The SAFE's collateral type
     * @param safe The SAFE's address
     * @param saviour The chosen saviour
     */
    function protectSAFE(
        bytes32 coinName,
        bytes32 collateralType,
        address safe,
        address saviour
    ) external {
        require(coinEnabled[coinName] == 1, "MultiLiquidationEngine/coin-not-enabled");
        require(coinInitialized[coinName] == 1, "MultiLiquidationEngine/coin-not-init");
        require(safeEngine.canModifySAFE(coinName, safe, msg.sender), "MultiLiquidationEngine/cannot-modify-safe");
        require(saviour == address(0) || safeSaviours[coinName][saviour] == 1, "MultiLiquidationEngine/saviour-not-authorized");
        chosenSAFESaviour[coinName][collateralType][safe] = saviour;
        emit ProtectSAFE(
            coinName,
            collateralType,
            safe,
            saviour
        );
    }
    /**
     * @notice Liquidate a SAFE
     * @param coinName The name of the coin minted by the SAFE
     * @param collateralType The SAFE's collateral type
     * @param subCollateral The SAFE's sub-collateral
     * @param safe The SAFE's address
     */
    function liquidateSAFE(bytes32 coinName, bytes32 collateralType, bytes32 subCollateral, address safe)
      external isSubCollateral(collateralType, subCollateral) returns (uint256 auctionId) {
        require(mutex[coinName][collateralType][subCollateral][safe] == 0, "MultiLiquidationEngine/non-null-mutex");
        mutex[coinName][collateralType][subCollateral][safe] = 1;

        (, uint256 accumulatedRate, , , uint256 debtFloor, uint256 liquidationPrice) =
          safeEngine.collateralTypes(coinName, collateralType);
        (uint256 safeCollateral, uint256 safeDebt) = safeEngine.safes(coinName, collateralType, subCollateral, safe);

        // Avoid stack too deep
        {
          require(coinEnabled[coinName] == 1, "MultiLiquidationEngine/coin-not-enabled");
          require(coinInitialized[coinName] == 1, "MultiLiquidationEngine/coin-not-init");
          require(both(
            liquidationPrice > 0,
            multiply(safeCollateral, liquidationPrice) < multiply(safeDebt, accumulatedRate)
          ), "MultiLiquidationEngine/safe-not-unsafe");
          require(
            both(currentOnAuctionSystemCoins[coinName] < onAuctionSystemCoinLimit[coinName],
            subtract(onAuctionSystemCoinLimit[coinName], currentOnAuctionSystemCoins[coinName]) >= debtFloor),
            "MultiLiquidationEngine/liquidation-limit-hit"
          );
        }

        if (chosenSAFESaviour[coinName][collateralType][safe] != address(0) &&
            safeSaviours[coinName][chosenSAFESaviour[coinName][collateralType][safe]] == 1) {
          try SAFESaviourLike(chosenSAFESaviour[coinName][collateralType][safe]).saveSAFE(coinName, msg.sender, collateralType, subCollateral, safe)
            returns (bool ok, uint256 collateralAddedOrDebtRepaid, uint256) {
            if (both(ok, collateralAddedOrDebtRepaid > 0)) {
              emit SaveSAFE(coinName, collateralType, subCollateral, safe, collateralAddedOrDebtRepaid);
            }
          } catch (bytes memory revertReason) {
            emit FailedSAFESave(coinName, revertReason);
          }
        }

        // Checks that the saviour didn't take collateral or add more debt to the SAFE
        {
          (uint256 newSafeCollateral, uint256 newSafeDebt) = safeEngine.safes(coinName, collateralType, subCollateral, safe);
          require(both(newSafeCollateral >= safeCollateral, newSafeDebt <= safeDebt), "MultiLiquidationEngine/invalid-safe-saviour-operation");
        }

        (, accumulatedRate, , , , liquidationPrice) = safeEngine.collateralTypes(coinName, collateralType);
        (safeCollateral, safeDebt) = safeEngine.safes(coinName, collateralType, subCollateral, safe);

        if (both(liquidationPrice > 0, multiply(safeCollateral, liquidationPrice) < multiply(safeDebt, accumulatedRate))) {
          CollateralType memory collateralData = collateralTypes[coinName][collateralType];

          uint256 limitAdjustedDebt;
          {
            uint256 amountDebtToLiquidate = subtract(onAuctionSystemCoinLimit[coinName], currentOnAuctionSystemCoins[coinName]);
            amountDebtToLiquidate         = minimum(collateralData.liquidationQuantity, amountDebtToLiquidate);
            limitAdjustedDebt = minimum(
              safeDebt,
              multiply(amountDebtToLiquidate, WAD) / accumulatedRate / collateralData.liquidationPenalty
            );
            require(limitAdjustedDebt > 0, "MultiLiquidationEngine/null-auction");
            require(either(limitAdjustedDebt == safeDebt, multiply(subtract(safeDebt, limitAdjustedDebt), accumulatedRate) >= debtFloor), "MultiLiquidationEngine/dusty-safe");
          }

          uint256 collateralToSell = minimum(safeCollateral, multiply(safeCollateral, limitAdjustedDebt) / safeDebt);

          require(collateralToSell > 0, "MultiLiquidationEngine/null-collateral-to-sell");
          require(both(collateralToSell <= 2**255, limitAdjustedDebt <= 2**255), "MultiLiquidationEngine/collateral-or-debt-overflow");

          safeEngine.confiscateSAFECollateralAndDebt(
            coinName, collateralType, subCollateral, safe, address(this), address(accountingEngine), -int256(collateralToSell), -int256(limitAdjustedDebt)
          );
          accountingEngine.pushDebtToQueue(coinName, multiply(limitAdjustedDebt, accumulatedRate));

          {
            // This calculation will overflow if multiply(limitAdjustedDebt, accumulatedRate) exceeds ~10^14,
            // i.e. the maximum amountToRaise is roughly 100 trillion system coins.
            uint256 amountToRaise_ = multiply(multiply(limitAdjustedDebt, accumulatedRate), collateralData.liquidationPenalty) / WAD;

            // Try to liquidate with the pool. If it can't be done,
            if (!liquidateWithPool(coinName, collateralType, subCollateral, amountToRaise_, collateralToSell)) {
              currentOnAuctionSystemCoins[coinName] = addition(currentOnAuctionSystemCoins[coinName], amountToRaise_);

              auctionId = CollateralAuctionHouseLike(collateralData.collateralAuctionHouse).startAuction(
                { subCollateral: subCollateral
                , forgoneCollateralReceiver: safe
                , initialBidder: address(accountingEngine)
                , amountToRaise: amountToRaise_
                , collateralToSell: collateralToSell
                , initialBid: 0
               });

               emit UpdateCurrentOnAuctionSystemCoins(currentOnAuctionSystemCoins[coinName]);
            }
          }

          emit Liquidate(
            coinName,
            collateralType,
            subCollateral,
            safe,
            collateralToSell,
            limitAdjustedDebt,
            multiply(limitAdjustedDebt, accumulatedRate),
            auctionId
          );
        }

        mutex[coinName][collateralType][subCollateral][safe] = 0;
    }
    /**
     * @notice Remove debt that was being auctioned
     * @param coinName The name of the coin to remove from auction
     * @param collateralType The collateral type handled by the caling auction house
     * @param rad The amount of debt to withdraw from currentOnAuctionSystemCoins
     */
    function removeCoinsFromAuction(bytes32 coinName, bytes32 collateralType, uint256 rad) public {
        require(msg.sender == collateralTypes[coinName][collateralType].collateralAuctionHouse, "MultiLiquidationEngine/invalid-caller");
        currentOnAuctionSystemCoins[coinName] = subtract(currentOnAuctionSystemCoins[coinName], rad);
        emit UpdateCurrentOnAuctionSystemCoins(currentOnAuctionSystemCoins[coinName]);
    }

    // --- Internal Logic ---
    /**
     * @notice Liquidate a SAFE using a liquidation pool
     * @param coinName The name of the coin held in the SAFE
     * @param collateralType The collateral type class
     * @param subCollateral The sub-collateral being sold off
     * @param debtAmount The amount of system coins being requested
     * @param collateralAmount The amount of collateral being sold
     */
    function liquidateWithPool(
      bytes32 coinName,
      bytes32 collateralType,
      bytes32 subCollateral,
      uint256 debtAmount,
      uint256 collateralAmount
    ) internal returns (bool) {
        address liquidationPool = collateralTypes[coinName][collateralType].liquidationPool;
        if (liquidationPool == address(0)) return false;

        // Check if the pool can liquidate everything
        try LiquidationPoolLike(liquidationPool).canLiquidate(
          coinName, collateralType, subCollateral, debtAmount, collateralAmount
        ) returns (bool canLiquidate) {
          if (!canLiquidate) return false;

          uint256 selfCollateralBalance = safeEngine.tokenCollateral(collateralType, subCollateral, address(this));

          // If the pool can liquidate, start the process
          try LiquidationPoolLike(liquidationPool).liquidateSAFE(
            coinName,
            collateralType,
            subCollateral,
            debtAmount,
            collateralAmount,
            address(accountingEngine)
          ) returns (bool liquidated) {
            // If it couldn't be liquidated or if the collateral hasn't been fully transferred to the pool, revert
            selfCollateralBalance = subtract(
              selfCollateralBalance,
              safeEngine.tokenCollateral(collateralType, subCollateral, address(this))
            );

            if (either(!liquidated, selfCollateralBalance < collateralAmount)) {
              revert("MultiLiquidationEngine/invalid-pool-liquidation");
            }

            return true;
          } catch(bytes memory failLiquidateReason) {
            emit FailLiquidationPoolLiquidate(coinName, collateralType, subCollateral, debtAmount, collateralAmount, failLiquidateReason);
            return false;
          }
        } catch(bytes memory failCanLiquidateReason) {
          emit FailLiquidationPoolCanLiquidate(coinName, collateralType, subCollateral, failCanLiquidateReason);
          return false;
        }
    }

    // --- Getters ---
    /*
    * @notice Get the amount of debt that can currently be covered by a collateral auction for a specific safe
    * @param coinName The name of the coin to get the limit adjusted debt for
    * @param collateralType The collateral type class
    * @param subCollateral The sub-collateral stored in the SAFE
    * @param safe The SAFE's address/handler
    */
    function getLimitAdjustedDebtToCover(bytes32 coinName, bytes32 collateralType, bytes32 subCollateral, address safe)
      external view returns (uint256) {
        (, uint256 accumulatedRate,,,,)            = safeEngine.collateralTypes(coinName, collateralType);
        (uint256 safeCollateral, uint256 safeDebt) = safeEngine.safes(coinName, collateralType, subCollateral, safe);
        CollateralType memory collateralData       = collateralTypes[coinName][collateralType];

        uint256 amountDebtToLiquidate = subtract(onAuctionSystemCoinLimit[coinName], currentOnAuctionSystemCoins[coinName]);
        amountDebtToLiquidate         = minimum(collateralData.liquidationQuantity, amountDebtToLiquidate);

        return minimum(
          safeDebt,
          multiply(amountDebtToLiquidate, WAD) / accumulatedRate / collateralData.liquidationPenalty
        );
    }
}
