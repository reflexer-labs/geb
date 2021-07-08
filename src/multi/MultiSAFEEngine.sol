/// MultiSAFEEngine.sol -- SAFE database

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

contract MultiSAFEEngine {
    // --- Auth ---
    mapping (bytes32 => mapping(address => uint256)) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(bytes32 coinName, address account) external isAuthorized(coinName) {
        require(coinEnabled[coinName] == 1, "MultiSAFEEngine/coin-not-enabled");
        authorizedAccounts[coinName][account] = 1;
        emit AddAuthorization(coinName, account);
    }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(bytes32 coinName, address account) external isAuthorized(coinName) {
        require(coinEnabled[coinName] == 1, "MultiSAFEEngine/coin-not-enabled");
        authorizedAccounts[coinName][account] = 0;
        emit RemoveAuthorization(coinName, account);
    }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized(bytes32 coinName) {
        require(authorizedAccounts[coinName][msg.sender] == 1, "MultiSAFEEngine/account-not-authorized");
        _;
    }

    mapping (address => uint256) public systemComponents;
    /**
     * @notice Add a system component
     * @param component Component to auth
     */
    function addSystemComponent(address component) external {
        require(manager == msg.sender, "MultiSAFEEngine/invalid-manager");
        systemComponents[component] = 1;
        emit AddSystemComponent(component);
    }
    /**
     * @notice Remove a system component
      @param component Component to deauth
     */
    function removeSystemComponent(address component) external {
        require(manager == msg.sender, "MultiSAFEEngine/invalid-manager");
        systemComponents[component] = 0;
        emit RemoveSystemComponent(component);
    }
    /**
    * @notice Checks whether msg.sender is a system component
    **/
    modifier isSystemComponent {
        require(systemComponents[msg.sender] == 1, "MultiSAFEEngine/account-not-component");
        _;
    }

    /**
    * @notice Checks whether msg.sender is a system component or an authed address for a specific coin
    **/
    modifier isSystemComponentOrAuth(bytes32 coinName) {
        require(either(systemComponents[msg.sender] == 1, authorizedAccounts[coinName][msg.sender] == 1), "MultiSAFEEngine/account-not-component-or-auth");
        _;
    }

    mapping (bytes32 => mapping(address => uint256)) public collateralJoins;
    /**
     * @notice Add a collateral join
     * @param collateralType The name of the collateral associated with this join
     * @param join Join to auth
     */
    function addCollateralJoin(bytes32 collateralType, address join) external {
        require(deployer == msg.sender, "MultiSAFEEngine/invalid-deployer");
        collateralJoins[collateralType][join] = 1;
        emit AddCollateralJoin(collateralType, join);
    }
    /**
     * @notice Remove a collateral join
     * @param collateralType The name of the collateral associated with this join
      @param join Join to deauth
     */
    function removeCollateralJoin(bytes32 collateralType, address join) external {
        require(deployer == msg.sender, "MultiSAFEEngine/invalid-deployer");
        collateralJoins[collateralType][join] = 0;
        emit RemoveCollateralJoin(collateralType, join);
    }
    /**
    * @notice Checks whether msg.sender is a collateral join
    * @param collateralType The collateral for which to check msg.sender against
    **/
    modifier isCollateralJoin(bytes32 collateralType) {
        require(collateralJoins[collateralType][msg.sender] == 1, "MultiSAFEEngine/account-not-join");
        _;
    }

    // Who can transfer collateral & debt in/out of a SAFE
    mapping(bytes32 => mapping(address => mapping (address => uint256))) public safeRights;
    /**
     * @notice Allow an address to modify your SAFE
     * @param coinName Name of the coin
     * @param account Account to give SAFE permissions to
     */
    function approveSAFEModification(bytes32 coinName, address account) external {
        safeRights[coinName][msg.sender][account] = 1;
        emit ApproveSAFEModification(coinName, msg.sender, account);
    }
    /**
     * @notice Deny an address the rights to modify your SAFE
     * @param coinName Name of the coin
     * @param account Account that is denied SAFE permissions
     */
    function denySAFEModification(bytes32 coinName, address account) external {
        safeRights[coinName][msg.sender][account] = 0;
        emit DenySAFEModification(coinName, msg.sender, account);
    }
    /**
    * @notice Checks whether msg.sender has the right to modify a SAFE
    **/
    function canModifySAFE(bytes32 coinName, address safe, address account) public view returns (bool) {
        return either(safe == account, safeRights[coinName][safe][account] == 1);
    }

    // --- Data ---
    struct CollateralType {
        // Total debt issued for this specific collateral type
        uint256 debtAmount;        // [wad]
        // Accumulator for interest accrued on this collateral type
        uint256 accumulatedRate;   // [ray]
        // Floor price at which a SAFE is allowed to generate debt
        uint256 safetyPrice;       // [ray]
        // Maximum amount of debt that can be generated with this collateral type
        uint256 debtCeiling;       // [rad]
        // Minimum amount of debt that must be generated by a SAFE using this collateral
        uint256 debtFloor;         // [rad]
        // Price at which a SAFE gets liquidated
        uint256 liquidationPrice;  // [ray]
    }
    struct SAFE {
        // Total amount of collateral locked in a SAFE
        uint256 lockedCollateral;  // [wad]
        // Total amount of debt generated by a SAFE
        uint256 generatedDebt;     // [wad]
    }

    // Data about each collateral type
    mapping (bytes32 => mapping(bytes32 => CollateralType))                public collateralTypes;
    // Data about each SAFE
    mapping (bytes32 => mapping(bytes32 => mapping (address => SAFE )))    public safes;
    // Balance of each collateral type
    mapping (bytes32 => mapping (address => uint256))                      public tokenCollateral;  // [wad]
    // Internal balance of system coins
    mapping (bytes32 => mapping(address => uint256))                       public coinBalance;      // [rad]
    // Amount of debt held by an account. Coins & debt are like matter and antimatter. They nullify each other
    mapping (bytes32 => mapping(address => uint256))                       public debtBalance;      // [rad]

    // Total amount of debt that a single safe can generate
    mapping (bytes32 => uint256)  public safeDebtCeiling;     // [wad]
    // Total amount of debt (coins) currently issued
    mapping (bytes32 => uint256)  public globalDebt;          // [rad]
    // 'Bad' debt that's not covered by collateral
    mapping (bytes32 => uint256)  public globalUnbackedDebt;  // [rad]
    // Maximum amount of debt that can be issued
    mapping (bytes32 => uint256)  public globalDebtCeiling;   // [rad]
    // Mapping of coin states
    mapping (bytes32 => uint256)  public coinEnabled;
    // Whether a coin has been initialized or not
    mapping (bytes32 => uint256)  public coinInitialized;

    // Manager address
    address                      public manager;
    // Address of the deployer
    address                      public deployer;

    // --- Events ---
    event AddAuthorization(bytes32 indexed coinName, address account);
    event RemoveAuthorization(bytes32 indexed coinName, address account);
    event AddSystemComponent(address component);
    event RemoveSystemComponent(address component);
    event AddCollateralJoin(bytes32 indexed collateralType, address join);
    event RemoveCollateralJoin(bytes32 indexed collateralType, address join);
    event InitializeCoin(bytes32 indexed coinName, uint256 globalDebtCeiling);
    event ApproveSAFEModification(bytes32 indexed coinName, address sender, address account);
    event DenySAFEModification(bytes32 indexed coinName, address sender, address account);
    event InitializeCollateralType(bytes32 indexed coinName, bytes32 collateralType);
    event ModifyParameters(bytes32 indexed coinName, bytes32 parameter, uint256 data);
    event ModifyParameters(bytes32 indexed coinName, bytes32 collateralType, bytes32 parameter, uint256 data);
    event DisableCoin(bytes32 indexed coinName);
    event ModifyCollateralBalance(bytes32 indexed collateralType, address indexed account, int256 wad);
    event TransferCollateral(bytes32 indexed collateralType, address indexed src, address indexed dst, uint256 wad);
    event TransferInternalCoins(bytes32 indexed coinName, address indexed src, address indexed dst, uint256 rad);
    event ModifySAFECollateralization(
        bytes32 indexed coinName,
        bytes32 indexed collateralType,
        address indexed safe,
        address collateralSource,
        address debtDestination,
        int256 deltaCollateral,
        int256 deltaDebt,
        uint256 lockedCollateral,
        uint256 generatedDebt,
        uint256 globalDebt
    );
    event TransferSAFECollateralAndDebt(
        bytes32 coinName,
        bytes32 indexed collateralType,
        address indexed src,
        address indexed dst,
        int256 deltaCollateral,
        int256 deltaDebt,
        uint256 srcLockedCollateral,
        uint256 srcGeneratedDebt,
        uint256 dstLockedCollateral,
        uint256 dstGeneratedDebt
    );
    event ConfiscateSAFECollateralAndDebt(
        bytes32 indexed coinName,
        bytes32 indexed collateralType,
        address indexed safe,
        address collateralCounterparty,
        address debtCounterparty,
        int256 deltaCollateral,
        int256 deltaDebt,
        uint256 globalUnbackedDebt
    );
    event SettleDebt(
      bytes32 indexed coinName,
      address indexed account,
      uint256 rad,
      uint256 debtBalance,
      uint256 coinBalance,
      uint256 globalUnbackedDebt,
      uint256 globalDebt
    );
    event CreateUnbackedDebt(
        bytes32 indexed coinName,
        address indexed debtDestination,
        address indexed coinDestination,
        uint256 rad,
        uint256 debtDstBalance,
        uint256 coinDstBalance,
        uint256 globalUnbackedDebt,
        uint256 globalDebt
    );
    event UpdateAccumulatedRate(
        bytes32 indexed coinName,
        bytes32 indexed collateralType,
        address surplusDst,
        int256 rateMultiplier,
        uint256 dstCoinBalance,
        uint256 globalDebt
    );

    // --- Init ---
    constructor() public {
        manager  = msg.sender;
        deployer = msg.sender;
    }

    // --- Math ---
    function addition(uint256 x, int256 y) internal pure returns (uint256 z) {
        z = x + uint256(y);
        require(y >= 0 || z <= x, "MultiSAFEEngine/add-uint-int-overflow");
        require(y <= 0 || z >= x, "MultiSAFEEngine/add-uint-int-underflow");
    }
    function addition(int256 x, int256 y) internal pure returns (int256 z) {
        z = x + y;
        require(y >= 0 || z <= x, "MultiSAFEEngine/add-int-int-overflow");
        require(y <= 0 || z >= x, "MultiSAFEEngine/add-int-int-underflow");
    }
    function subtract(uint256 x, int256 y) internal pure returns (uint256 z) {
        z = x - uint256(y);
        require(y <= 0 || z <= x, "MultiSAFEEngine/sub-uint-int-overflow");
        require(y >= 0 || z >= x, "MultiSAFEEngine/sub-uint-int-underflow");
    }
    function subtract(int256 x, int256 y) internal pure returns (int256 z) {
        z = x - y;
        require(y <= 0 || z <= x, "MultiSAFEEngine/sub-int-int-overflow");
        require(y >= 0 || z >= x, "MultiSAFEEngine/sub-int-int-underflow");
    }
    function multiply(uint256 x, int256 y) internal pure returns (int256 z) {
        z = int256(x) * y;
        require(int256(x) >= 0, "MultiSAFEEngine/mul-uint-int-null-x");
        require(y == 0 || z / y == int256(x), "MultiSAFEEngine/mul-uint-int-overflow");
    }
    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "MultiSAFEEngine/add-uint-uint-overflow");
    }
    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "MultiSAFEEngine/sub-uint-uint-underflow");
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "MultiSAFEEngine/multiply-uint-uint-overflow");
    }

    // --- Administration ---
    /**
     * @notice Initialize a new coin
     * @param coinName The name of the coin to initialize
     * @param globalDebtCeiling_ The initial global debt ceiling for the coin
     */
    function initializeCoin(bytes32 coinName, uint256 globalDebtCeiling_) external {
        require(deployer == msg.sender, "MultiSAFEEngine/caller-not-deployer");
        require(coinInitialized[coinName] == 0, "MultiSAFEEngine/already-init");
        require(globalDebtCeiling_ > 0, "MultiSAFEEngine/null-global-debt-ceiling");

        authorizedAccounts[coinName][msg.sender] = 1;

        coinInitialized[coinName]   = 1;
        coinEnabled[coinName]       = 1;
        globalDebtCeiling[coinName] = globalDebtCeiling_;
        safeDebtCeiling[coinName]   = uint256(-1);

        emit InitializeCoin(coinName, globalDebtCeiling[coinName]);
        emit AddAuthorization(coinName, msg.sender);
    }
    /**
     * @notice Creates a brand new collateral type for a specific coin
     * @param coinName The name of the coin to initialize
     * @param collateralType Collateral type name (e.g ETH-A, TBTC-B)
     */
    function initializeCollateralType(bytes32 coinName, bytes32 collateralType) external isAuthorized(coinName) {
        require(collateralTypes[coinName][collateralType].accumulatedRate == 0, "MultiSAFEEngine/collateral-type-already-exists");
        collateralTypes[coinName][collateralType].accumulatedRate = 10 ** 27;
        emit InitializeCollateralType(coinName, collateralType);
    }
    /**
     * @notice Modify general uint256 params
     * @param coinName The name of the coin
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(bytes32 coinName, bytes32 parameter, uint256 data) external isAuthorized(coinName) {
        require(coinEnabled[coinName] == 1, "MultiSAFEEngine/coin-not-enabled");
        if (parameter == "globalDebtCeiling") globalDebtCeiling[coinName] = data;
        else if (parameter == "safeDebtCeiling") safeDebtCeiling[coinName] = data;
        else revert("MultiSAFEEngine/modify-unrecognized-param");
        emit ModifyParameters(coinName, parameter, data);
    }
    /**
     * @notice Modify collateral specific params
     * @param coinName The name of the coin
     * @param collateralType Collateral type we modify params for
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(
        bytes32 coinName,
        bytes32 collateralType,
        bytes32 parameter,
        uint256 data
    ) external isSystemComponentOrAuth(coinName) {
        require(coinEnabled[coinName] == 1, "MultiSAFEEngine/coin-not-enabled");
        if (parameter == "safetyPrice") collateralTypes[coinName][collateralType].safetyPrice = data;
        else if (parameter == "liquidationPrice") collateralTypes[coinName][collateralType].liquidationPrice = data;
        else if (parameter == "debtCeiling") collateralTypes[coinName][collateralType].debtCeiling = data;
        else if (parameter == "debtFloor") collateralTypes[coinName][collateralType].debtFloor = data;
        else revert("MultiSAFEEngine/modify-unrecognized-param");
        emit ModifyParameters(coinName, collateralType, parameter, data);
    }
    /**
     * @notice Disable a coin (normally called by GlobalSettlement)
     * @param coinName The name of the coin to disable
     */
    function disableCoin(bytes32 coinName) external isSystemComponentOrAuth(coinName) {
        coinEnabled[coinName] = 0;
        emit DisableCoin(coinName);
    }

    // --- Fungibility ---
    /**
     * @notice Join/exit collateral into and and out of the system
     * @param collateralType Collateral type to join/exit
     * @param account Account that gets credited/debited
     * @param wad Amount of collateral
     */
    function modifyCollateralBalance(
        bytes32 collateralType,
        address account,
        int256 wad
    ) external isCollateralJoin(collateralType) {
        tokenCollateral[collateralType][account] = addition(tokenCollateral[collateralType][account], wad);
        emit ModifyCollateralBalance(collateralType, account, wad);
    }
    /**
     * @notice Transfer collateral between accounts
     * @param coinName The name of the coin that the accounts have
     * @param collateralType Collateral type transferred
     * @param src Collateral source
     * @param dst Collateral destination
     * @param wad Amount of collateral transferred
     */
    function transferCollateral(
        bytes32 coinName,
        bytes32 collateralType,
        address src,
        address dst,
        uint256 wad
    ) external {
        require(canModifySAFE(coinName, src, msg.sender), "MultiSAFEEngine/not-allowed");
        tokenCollateral[collateralType][src] = subtract(tokenCollateral[collateralType][src], wad);
        tokenCollateral[collateralType][dst] = addition(tokenCollateral[collateralType][dst], wad);
        emit TransferCollateral(collateralType, src, dst, wad);
    }
    /**
     * @notice Transfer internal coins (does not affect external balances from Coin.sol)
     * @param coinName The name of the coin to transfer
     * @param src Coins source
     * @param dst Coins destination
     * @param rad Amount of coins transferred
     */
    function transferInternalCoins(bytes32 coinName, address src, address dst, uint256 rad) external {
        require(canModifySAFE(coinName, src, msg.sender), "MultiSAFEEngine/not-allowed");
        coinBalance[coinName][src] = subtract(coinBalance[coinName][src], rad);
        coinBalance[coinName][dst] = addition(coinBalance[coinName][dst], rad);
        emit TransferInternalCoins(coinName, src, dst, rad);
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- SAFE Manipulation ---
    /**
     * @notice Add/remove collateral or put back/generate more debt in a SAFE
     * @param coinName The name of the coin to mint
     * @param collateralType Type of collateral to withdraw/deposit in and from the SAFE
     * @param safe Target SAFE
     * @param collateralSource Account we take collateral from/put collateral into
     * @param debtDestination Account from which we credit/debit coins and debt
     * @param deltaCollateral Amount of collateral added/extract from the SAFE (wad)
     * @param deltaDebt Amount of debt to generate/repay (wad)
     */
    function modifySAFECollateralization(
        bytes32 coinName,
        bytes32 collateralType,
        address safe,
        address collateralSource,
        address debtDestination,
        int256 deltaCollateral,
        int256 deltaDebt
    ) external {
        // coin is enabled
        require(coinEnabled[coinName] == 1, "MultiSAFEEngine/coin-not-enabled");

        SAFE memory safeData = safes[coinName][collateralType][safe];
        CollateralType memory collateralTypeData = collateralTypes[coinName][collateralType];
        // collateral type has been initialised
        require(collateralTypeData.accumulatedRate != 0, "MultiSAFEEngine/collateral-type-not-initialized");

        safeData.lockedCollateral      = addition(safeData.lockedCollateral, deltaCollateral);
        safeData.generatedDebt         = addition(safeData.generatedDebt, deltaDebt);
        collateralTypeData.debtAmount  = addition(collateralTypeData.debtAmount, deltaDebt);

        int256 deltaAdjustedDebt = multiply(collateralTypeData.accumulatedRate, deltaDebt);
        uint256 totalDebtIssued  = multiply(collateralTypeData.accumulatedRate, safeData.generatedDebt);
        globalDebt[coinName]     = addition(globalDebt[coinName], deltaAdjustedDebt);

        // either debt has decreased, or debt ceilings are not exceeded
        {
          uint256 _globalDebt        = globalDebt[coinName];
          uint256 _globalDebtCeiling = globalDebtCeiling[coinName];
          bool belowDebtCeilings     =
            (multiply(collateralTypeData.debtAmount, collateralTypeData.accumulatedRate) <= collateralTypeData.debtCeiling);
          belowDebtCeilings = both(belowDebtCeilings, _globalDebt <= _globalDebtCeiling);

          require(
            either(deltaDebt <= 0,belowDebtCeilings),
            "MultiSAFEEngine/ceiling-exceeded"
          );
          // safe is either less risky than before, or it is safe
          require(
            either(
              both(deltaDebt <= 0, deltaCollateral >= 0),
              totalDebtIssued <= multiply(safeData.lockedCollateral, collateralTypeData.safetyPrice)
            ),
            "MultiSAFEEngine/not-safe"
          );
        }

        // safe is either more safe, or the owner consents
        require(either(both(deltaDebt <= 0, deltaCollateral >= 0), canModifySAFE(coinName, safe, msg.sender)), "MultiSAFEEngine/not-allowed-to-modify-safe");
        // collateral src consents
        require(either(deltaCollateral <= 0, canModifySAFE(coinName, collateralSource, msg.sender)), "MultiSAFEEngine/not-allowed-collateral-src");
        // debt dst consents
        require(either(deltaDebt >= 0, canModifySAFE(coinName, debtDestination, msg.sender)), "MultiSAFEEngine/not-allowed-debt-dst");

        // safe has no debt, or a non-dusty amount
        require(either(safeData.generatedDebt == 0, totalDebtIssued >= collateralTypeData.debtFloor), "MultiSAFEEngine/dust");

        // safe didn't go above the safe debt limit
        if (deltaDebt > 0) {
          require(safeData.generatedDebt <= safeDebtCeiling[coinName], "MultiSAFEEngine/above-debt-limit");
        }

        tokenCollateral[collateralType][collateralSource] =
          subtract(tokenCollateral[collateralType][collateralSource], deltaCollateral);

        coinBalance[coinName][debtDestination] = addition(coinBalance[coinName][debtDestination], deltaAdjustedDebt);

        safes[coinName][collateralType][safe]     = safeData;
        collateralTypes[coinName][collateralType] = collateralTypeData;

        uint256 _globalDebt = globalDebt[coinName];
        emit ModifySAFECollateralization(
            coinName,
            collateralType,
            safe,
            collateralSource,
            debtDestination,
            deltaCollateral,
            deltaDebt,
            safeData.lockedCollateral,
            safeData.generatedDebt,
            _globalDebt
        );
    }

    // --- SAFE Fungibility ---
    /**
     * @notice Transfer collateral and/or debt between SAFEs
     * @param coinName The name of the coin to transfer
     * @param collateralType Collateral type transferred between SAFEs
     * @param src Source SAFE
     * @param dst Destination SAFE
     * @param deltaCollateral Amount of collateral to take/add into src and give/take from dst (wad)
     * @param deltaDebt Amount of debt to take/add into src and give/take from dst (wad)
     */
    function transferSAFECollateralAndDebt(
        bytes32 coinName,
        bytes32 collateralType,
        address src,
        address dst,
        int256 deltaCollateral,
        int256 deltaDebt
    ) external {
        SAFE storage srcSAFE = safes[coinName][collateralType][src];
        SAFE storage dstSAFE = safes[coinName][collateralType][dst];
        CollateralType storage collateralType_ = collateralTypes[coinName][collateralType];

        srcSAFE.lockedCollateral = subtract(srcSAFE.lockedCollateral, deltaCollateral);
        srcSAFE.generatedDebt    = subtract(srcSAFE.generatedDebt, deltaDebt);
        dstSAFE.lockedCollateral = addition(dstSAFE.lockedCollateral, deltaCollateral);
        dstSAFE.generatedDebt    = addition(dstSAFE.generatedDebt, deltaDebt);

        uint256 srcTotalDebtIssued = multiply(srcSAFE.generatedDebt, collateralType_.accumulatedRate);
        uint256 dstTotalDebtIssued = multiply(dstSAFE.generatedDebt, collateralType_.accumulatedRate);

        // both sides consent
        require(both(canModifySAFE(coinName, src, msg.sender), canModifySAFE(coinName, dst, msg.sender)), "MultiSAFEEngine/not-allowed");

        // both sides safe
        require(srcTotalDebtIssued <= multiply(srcSAFE.lockedCollateral, collateralType_.safetyPrice), "MultiSAFEEngine/not-safe-src");
        require(dstTotalDebtIssued <= multiply(dstSAFE.lockedCollateral, collateralType_.safetyPrice), "MultiSAFEEngine/not-safe-dst");

        // both sides non-dusty
        require(either(srcTotalDebtIssued >= collateralType_.debtFloor, srcSAFE.generatedDebt == 0), "MultiSAFEEngine/dust-src");
        require(either(dstTotalDebtIssued >= collateralType_.debtFloor, dstSAFE.generatedDebt == 0), "MultiSAFEEngine/dust-dst");

        emit TransferSAFECollateralAndDebt(
            coinName,
            collateralType,
            src,
            dst,
            deltaCollateral,
            deltaDebt,
            srcSAFE.lockedCollateral,
            srcSAFE.generatedDebt,
            dstSAFE.lockedCollateral,
            dstSAFE.generatedDebt
        );
    }

    // --- SAFE Confiscation ---
    /**
     * @notice Normally used by the LiquidationEngine in order to confiscate collateral and
       debt from a SAFE and give them to someone else
     * @param coinName The name of the coin to confiscate
     * @param collateralType Collateral type the SAFE has locked inside
     * @param safe Target SAFE
     * @param collateralCounterparty Who we take/give collateral to
     * @param debtCounterparty Who we take/give debt to
     * @param deltaCollateral Amount of collateral taken/added into the SAFE (wad)
     * @param deltaDebt Amount of debt taken/added into the SAFE (wad)
     */
    function confiscateSAFECollateralAndDebt(
        bytes32 coinName,
        bytes32 collateralType,
        address safe,
        address collateralCounterparty,
        address debtCounterparty,
        int256 deltaCollateral,
        int256 deltaDebt
    ) external isSystemComponent() {
        // Avoid stack too deep
        {
          SAFE storage safe_ = safes[coinName][collateralType][safe];
          safe_.lockedCollateral = addition(safe_.lockedCollateral, deltaCollateral);
          safe_.generatedDebt = addition(safe_.generatedDebt, deltaDebt);
        }

        // Avoid stack too deep
        {
          CollateralType storage collateralType_ = collateralTypes[coinName][collateralType];
          collateralType_.debtAmount = addition(collateralType_.debtAmount, deltaDebt);

          int256 deltaTotalIssuedDebt = multiply(collateralType_.accumulatedRate, deltaDebt);

          tokenCollateral[collateralType][collateralCounterparty] = subtract(
            tokenCollateral[collateralType][collateralCounterparty],
            deltaCollateral
          );
          debtBalance[coinName][debtCounterparty] = subtract(
            debtBalance[coinName][debtCounterparty],
            deltaTotalIssuedDebt
          );
          globalUnbackedDebt[coinName] = subtract(
            globalUnbackedDebt[coinName],
            deltaTotalIssuedDebt
          );
        }

        uint256 unbackedDebt = globalUnbackedDebt[coinName];
        emit ConfiscateSAFECollateralAndDebt(
            coinName,
            collateralType,
            safe,
            collateralCounterparty,
            debtCounterparty,
            deltaCollateral,
            deltaDebt,
            unbackedDebt
        );
    }

    // --- Settlement ---
    /**
     * @notice Nullify an amount of coins with an equal amount of debt
     * @param coinName The name of the coin to nullify
     * @param rad Amount of debt & coins to destroy
     */
    function settleDebt(bytes32 coinName, uint256 rad) external {
        address account                = msg.sender;
        debtBalance[coinName][account] = subtract(debtBalance[coinName][account], rad);
        coinBalance[coinName][account] = subtract(coinBalance[coinName][account], rad);
        globalUnbackedDebt[coinName]   = subtract(globalUnbackedDebt[coinName], rad);
        globalDebt[coinName]           = subtract(globalDebt[coinName], rad);
        emit SettleDebt(
          coinName,
          account,
          rad,
          debtBalance[coinName][account],
          coinBalance[coinName][account],
          globalUnbackedDebt[coinName],
          globalDebt[coinName]
        );
    }
    /**
     * @notice Create unbacked debt
     * @param coinName The name of the coin to nullify
     * @param debtDestination Usually AccountingEngine that can settle uncovered debt with surplus
     * @param coinDestination Usually CoinSavingsAccount that passes the new coins to depositors
     * @param rad Amount of debt to create
     */
    function createUnbackedDebt(
        bytes32 coinName,
        address debtDestination,
        address coinDestination,
        uint256 rad
    ) external isSystemComponentOrAuth(coinName) {
        debtBalance[coinName][debtDestination]  = addition(debtBalance[coinName][debtDestination], rad);
        coinBalance[coinName][coinDestination]  = addition(coinBalance[coinName][coinDestination], rad);
        globalUnbackedDebt[coinName]            = addition(globalUnbackedDebt[coinName], rad);
        globalDebt[coinName]                    = addition(globalDebt[coinName], rad);
        emit CreateUnbackedDebt(
            coinName,
            debtDestination,
            coinDestination,
            rad,
            debtBalance[coinName][debtDestination],
            coinBalance[coinName][coinDestination],
            globalUnbackedDebt[coinName],
            globalDebt[coinName]
        );
    }

    // --- Rates ---
    /**
     * @notice Usually called by TaxCollector in order to accrue interest on a specific collateral type
     * @param coinName The name of the coin to nullify
     * @param collateralType Collateral type we accrue interest for
     * @param surplusDst Destination for the newly created surplus
     * @param rateMultiplier Multiplier applied to the debtAmount in order to calculate the surplus [ray]
     */
    function updateAccumulatedRate(
        bytes32 coinName,
        bytes32 collateralType,
        address surplusDst,
        int256 rateMultiplier
    ) external isSystemComponent() {
        require(coinEnabled[coinName] == 1, "MultiSAFEEngine/coin-not-enabled");
        CollateralType storage collateralType_ = collateralTypes[coinName][collateralType];
        collateralType_.accumulatedRate        = addition(collateralType_.accumulatedRate, rateMultiplier);
        int256 deltaSurplus                    = multiply(collateralType_.debtAmount, rateMultiplier);
        coinBalance[coinName][surplusDst]      = addition(coinBalance[coinName][surplusDst], deltaSurplus);
        globalDebt[coinName]                   = addition(globalDebt[coinName], deltaSurplus);
        emit UpdateAccumulatedRate(
            coinName,
            collateralType,
            surplusDst,
            rateMultiplier,
            coinBalance[coinName][surplusDst],
            globalDebt[coinName]
        );
    }
}
