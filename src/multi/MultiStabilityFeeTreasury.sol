/// MultiStabilityFeeTreasury.sol

// Copyright (C) 2018 Rain <rainbreak@riseup.net>, 2020 Reflexer Labs, INC

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

abstract contract SAFEEngineLike {
    function denySAFEModification(bytes32,address) virtual external;
    function transferInternalCoins(bytes32,address,address,uint256) virtual external;
    function settleDebt(bytes32,uint256) virtual external;
    function coinBalance(bytes32,address) virtual public view returns (uint256);
    function debtBalance(bytes32,address) virtual public view returns (uint256);
}
abstract contract SystemCoinLike {
    function balanceOf(address) virtual public view returns (uint256);
    function approve(address, uint256) virtual public returns (uint256);
    function transfer(address,uint256) virtual public returns (bool);
    function transferFrom(address,address,uint256) virtual public returns (bool);
}
abstract contract CoinJoinLike {
    function coinName() virtual public view returns (bytes32);
    function systemCoin() virtual public view returns (address);
    function join(address, uint256) virtual external;
}

contract MultiStabilityFeeTreasury {
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
        require(authorizedAccounts[coinName][msg.sender] == 1, "MultiStabilityFeeTreasury/account-not-authorized");
        _;
    }

    /**
     * @notice Checks whether a coin is initialized
     */
    modifier coinIsInitialized(bytes32 coinName) {
        require(coinInitialized[coinName] == 1, "MultiStabilityFeeTreasury/coin-not-init");

        _;
    }

    /**
     * @notice Checks that an address is not this contract
     */
    modifier accountNotTreasury(address account) {
        require(account != address(this), "MultiStabilityFeeTreasury/account-cannot-be-treasury");
        _;
    }

    // --- Events ---
    event AddAuthorization(bytes32 indexed coinName, address account);
    event RemoveAuthorization(bytes32 indexed coinName, address account);
    event ModifyParameters(bytes32 parameter, address addr);
    event ModifyParameters(bytes32 indexed coinName, bytes32 parameter, address addr);
    event ModifyParameters(bytes32 indexed coinName, bytes32 parameter, uint256 val);
    event SetTotalAllowance(bytes32 indexed coinName, address indexed account, uint256 rad);
    event SetPerBlockAllowance(bytes32 indexed coinName, address indexed account, uint256 rad);
    event GiveFunds(bytes32 indexed coinName, address indexed account, uint256 rad, uint256 expensesAccumulator);
    event TakeFunds(bytes32 indexed coinName, address indexed account, uint256 rad);
    event PullFunds(bytes32 indexed coinName, address indexed sender, address indexed dstAccount, address token, uint256 rad, uint256 expensesAccumulator);
    event TransferSurplusFunds(bytes32 indexed coinName, address extraSurplusReceiver, uint256 fundsToTransfer);
    event InitializeCoin(
      bytes32 indexed coinName,
      address coinJoin,
      address extraSurplusReceiver,
      uint256 expensesMultiplier,
      uint256 treasuryCapacity,
      uint256 minimumFundsRequired,
      uint256 pullFundsMinThreshold,
      uint256 surplusTransferDelay
    );

    // --- Structs ---
    struct Allowance {
        uint256 total;
        uint256 perBlock;
    }

    // Manager address
    address                                                             public manager;
    // Address of the deployer
    address                                                             public deployer;

    // Whether a coin has been initialized or not
    mapping (bytes32 => uint256)                                        public coinInitialized;
    // Mapping of total and per block allowances
    mapping(bytes32 => mapping(address => Allowance))                   private allowance;
    // Mapping that keeps track of how much surplus an authorized address has pulled each block
    mapping(bytes32 => mapping(address => mapping(uint256 => uint256))) public pulledPerBlock;
    // Mapping of all system coin addresses
    mapping(bytes32 => address)                                         public systemCoin;
    // Coin join contracts
    mapping(bytes32 => address)                                         public coinJoin;
    // The address that receives any extra surplus which is not used by the treasury
    mapping(bytes32 => address)                                         public extraSurplusReceiver;

    // Max amount of SF that can be kept in the treasury
    mapping (bytes32 => uint256)                                        public treasuryCapacity;          // [rad]
    // Minimum amount of SF that must be kept in the treasury at all times
    mapping (bytes32 => uint256)                                        public minimumFundsRequired;      // [rad]
    // Multiplier for expenses
    mapping (bytes32 => uint256)                                        public expensesMultiplier;        // [hundred]
    // Minimum time between transferSurplusFunds calls
    mapping (bytes32 => uint256)                                        public surplusTransferDelay;      // [seconds]
    // Expenses accumulator
    mapping (bytes32 => uint256)                                        public expensesAccumulator;       // [rad]
    // Latest tagged accumulator price
    mapping (bytes32 => uint256)                                        public accumulatorTag;            // [rad]
    // Minimum funds that must be in the treasury so that someone can pullFunds
    mapping (bytes32 => uint256)                                        public pullFundsMinThreshold;     // [rad]
    // Latest timestamp when transferSurplusFunds was called
    mapping (bytes32 => uint256)                                        public latestSurplusTransferTime; // [seconds]

    SAFEEngineLike public safeEngine;

    constructor(
        address safeEngine_
    ) public {
        manager    = msg.sender;
        deployer   = msg.sender;
        safeEngine = SAFEEngineLike(safeEngine_);
    }

    // --- Math ---
    uint256 constant HUNDRED = 10 ** 2;
    uint256 constant RAY     = 10 ** 27;

    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x + y;
        require(z >= x, "MultiStabilityFeeTreasury/add-uint-uint-overflow");
    }
    function addition(int256 x, int256 y) internal pure returns (int256 z) {
        z = x + y;
        if (y <= 0) require(z <= x, "MultiStabilityFeeTreasury/add-int-int-underflow");
        if (y  > 0) require(z > x, "MultiStabilityFeeTreasury/add-int-int-overflow");
    }
    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "MultiStabilityFeeTreasury/sub-uint-uint-underflow");
    }
    function subtract(int256 x, int256 y) internal pure returns (int256 z) {
        z = x - y;
        require(y <= 0 || z <= x, "MultiStabilityFeeTreasury/sub-int-int-underflow");
        require(y >= 0 || z >= x, "MultiStabilityFeeTreasury/sub-int-int-overflow");
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "MultiStabilityFeeTreasury/mul-uint-uint-overflow");
    }
    function divide(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0, "MultiStabilityFeeTreasury/div-y-null");
        z = x / y;
        require(z <= x, "MultiStabilityFeeTreasury/div-invalid");
    }
    function minimum(uint256 x, uint256 y) internal view returns (uint256 z) {
        z = (x <= y) ? x : y;
    }

    // --- Administration ---
    /**
     * @notice Initialize a new coin
     * @param coinName The name of the coin to initialize
     */
    function initializeCoin(
        bytes32 coinName,
        address coinJoin_,
        address extraSurplusReceiver_,
        uint256 expensesMultiplier_,
        uint256 treasuryCapacity_,
        uint256 minimumFundsRequired_,
        uint256 pullFundsMinThreshold_,
        uint256 surplusTransferDelay_
    ) external {
        require(deployer == msg.sender, "MultiStabilityFeeTreasury/caller-not-deployer");
        require(coinInitialized[coinName] == 0, "MultiStabilityFeeTreasury/already-init");
        require(address(safeEngine) != address(0), "MultiStabilityFeeTreasury/null-safe-engine");

        require(address(CoinJoinLike(coinJoin_).systemCoin()) != address(0), "MultiStabilityFeeTreasury/null-system-coin");
        require(CoinJoinLike(coinJoin_).coinName() == coinName, "MultiStabilityFeeTreasury/invalid-join-coin-name");
        require(extraSurplusReceiver_ != address(0), "MultiStabilityFeeTreasury/null-surplus-receiver");
        require(extraSurplusReceiver_ != address(this), "MultiStabilityFeeTreasury/surplus-receiver-cannot-be-this");
        require(expensesMultiplier_ >= HUNDRED, "MultiStabilityFeeTreasury/invalid-expenses-multiplier");
        require(treasuryCapacity_ >= minimumFundsRequired_, "MultiStabilityFeeTreasury/invalid-treasury-capacity");
        require(surplusTransferDelay_ > 0, "MultiStabilityFeeTreasury/null-surplus-transfer-delay");

        authorizedAccounts[coinName][msg.sender] = 1;

        coinInitialized[coinName]           = 1;

        extraSurplusReceiver[coinName]      = extraSurplusReceiver_;
        coinJoin[coinName]                  = coinJoin_;
        systemCoin[coinName]                = CoinJoinLike(coinJoin_).systemCoin();
        latestSurplusTransferTime[coinName] = now;
        expensesMultiplier[coinName]        = expensesMultiplier_;
        treasuryCapacity[coinName]          = treasuryCapacity_;
        minimumFundsRequired[coinName]      = minimumFundsRequired_;
        pullFundsMinThreshold[coinName]     = pullFundsMinThreshold_;
        surplusTransferDelay[coinName]      = surplusTransferDelay_;

        SystemCoinLike(systemCoin[coinName]).approve(coinJoin_, uint256(-1));

        emit InitializeCoin(
          coinName,
          coinJoin_,
          extraSurplusReceiver_,
          expensesMultiplier_,
          treasuryCapacity_,
          minimumFundsRequired_,
          pullFundsMinThreshold_,
          surplusTransferDelay_
        );
        emit AddAuthorization(coinName, msg.sender);
    }
    /**
     * @notice Set an address param
     * @param parameter The name of the parameter to change
     * @param data The new manager
     */
    function modifyParameters(bytes32 parameter, address data) external {
        require(manager == msg.sender, "MultiStabilityFeeTreasury/invalid-manager");
        if (parameter == "manager") {
          manager = data;
        } else if (parameter == "deployer") {
          require(data != address(0), "MultiStabilityFeeTreasury/null-deployer");
          deployer = data;
        }
        else revert("MultiStabilityFeeTreasury/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }
    /**
     * @notice Modify address parameters
     * @param coinName The name of the coin
     * @param parameter The name of the contract whose address will be changed
     * @param addr New address for the contract
     */
    function modifyParameters(bytes32 coinName, bytes32 parameter, address addr) external isAuthorized(coinName) {
        require(addr != address(0), "MultiStabilityFeeTreasury/null-addr");
        if (parameter == "extraSurplusReceiver") {
          require(addr != address(this), "MultiStabilityFeeTreasury/accounting-engine-cannot-be-treasury");
          extraSurplusReceiver[coinName] = addr;
        }
        else revert("MultiStabilityFeeTreasury/modify-unrecognized-param");
        emit ModifyParameters(coinName, parameter, addr);
    }
    /**
     * @notice Modify uint256 parameters
     * @param coinName The name of the coin
     * @param parameter The name of the parameter to modify
     * @param val New parameter value
     */
    function modifyParameters(bytes32 coinName, bytes32 parameter, uint256 val) external isAuthorized(coinName) {
        if (parameter == "expensesMultiplier") expensesMultiplier[coinName] = val;
        else if (parameter == "treasuryCapacity") {
          require(val >= minimumFundsRequired[coinName], "MultiStabilityFeeTreasury/capacity-lower-than-min-funds");
          treasuryCapacity[coinName] = val;
        }
        else if (parameter == "minimumFundsRequired") {
          require(val <= treasuryCapacity[coinName], "MultiStabilityFeeTreasury/min-funds-higher-than-capacity");
          minimumFundsRequired[coinName] = val;
        }
        else if (parameter == "pullFundsMinThreshold") {
          pullFundsMinThreshold[coinName] = val;
        }
        else if (parameter == "surplusTransferDelay") surplusTransferDelay[coinName] = val;
        else revert("MultiStabilityFeeTreasury/modify-unrecognized-param");
        emit ModifyParameters(coinName, parameter, val);
    }

    // --- Utils ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }
    /**
     * @notice Join all ERC20 system coins that the treasury has inside the SAFEEngine
     * @param coinName Name of the coin to join
     */
    function joinAllCoins(bytes32 coinName) internal {
        if (SystemCoinLike(systemCoin[coinName]).balanceOf(address(this)) > 0) {
          CoinJoinLike(coinJoin[coinName]).join(address(this), SystemCoinLike(systemCoin[coinName]).balanceOf(address(this)));
        }
    }
    /*
    * @notice Settle as much bad debt as possible (if this contract has any)
    * @param coinName The name of the coin to settle debt for
    */
    function settleDebt(bytes32 coinName) public {
        uint256 coinBalanceSelf = safeEngine.coinBalance(coinName, address(this));
        uint256 debtBalanceSelf = safeEngine.debtBalance(coinName, address(this));

        if (debtBalanceSelf > 0) {
          safeEngine.settleDebt(coinName, minimum(coinBalanceSelf, debtBalanceSelf));
        }
    }

    // --- Getters ---
    /*
    * @notice Returns the total and per block allowances for a specific address
    * @param coinName Name of the coin for which to return the allowance
    * @param account The address to return the allowances for
    */
    function getAllowance(bytes32 coinName, address account) public view returns (uint256, uint256) {
        return (allowance[coinName][account].total, allowance[coinName][account].perBlock);
    }

    // --- SF Transfer Allowance ---
    /**
     * @notice Modify an address' total allowance in order to withdraw SF from the treasury
     * @param coinName The name of the coin
     * @param account The approved address
     * @param rad The total approved amount of SF to withdraw (number with 45 decimals)
     */
    function setTotalAllowance(bytes32 coinName, address account, uint256 rad) external isAuthorized(coinName) accountNotTreasury(account) {
        require(account != address(0), "MultiStabilityFeeTreasury/null-account");
        allowance[coinName][account].total = rad;
        emit SetTotalAllowance(coinName, account, rad);
    }
    /**
     * @notice Modify an address' per block allowance in order to withdraw SF from the treasury
     * @param coinName The name of the coin
     * @param account The approved address
     * @param rad The per block approved amount of SF to withdraw (number with 45 decimals)
     */
    function setPerBlockAllowance(bytes32 coinName, address account, uint256 rad) external isAuthorized(coinName) accountNotTreasury(account) {
        require(account != address(0), "MultiStabilityFeeTreasury/null-account");
        allowance[coinName][account].perBlock = rad;
        emit SetPerBlockAllowance(coinName, account, rad);
    }

    // --- Stability Fee Transfer (Governance) ---
    /**
     * @notice Governance transfers SF to an address
     * @param coinName The name of the coin
     * @param account Address to transfer SF to
     * @param rad Amount of internal system coins to transfer (a number with 45 decimals)
     */
    function giveFunds(bytes32 coinName, address account, uint256 rad) external isAuthorized(coinName) accountNotTreasury(account) {
        require(account != address(0), "MultiStabilityFeeTreasury/null-account");

        joinAllCoins(coinName);
        settleDebt(coinName);

        require(safeEngine.debtBalance(coinName, address(this)) == 0, "MultiStabilityFeeTreasury/outstanding-bad-debt");
        require(safeEngine.coinBalance(coinName, address(this)) >= rad, "MultiStabilityFeeTreasury/not-enough-funds");

        if (account != extraSurplusReceiver[coinName]) {
          expensesAccumulator[coinName] = addition(expensesAccumulator[coinName], rad);
        }

        safeEngine.transferInternalCoins(coinName, address(this), account, rad);
        emit GiveFunds(coinName, account, rad, expensesAccumulator[coinName]);
    }
    /**
     * @notice Governance takes funds from an address
     * @param coinName The name of the coin
     * @param account Address to take system coins from
     * @param rad Amount of internal system coins to take from the account (a number with 45 decimals)
     */
    function takeFunds(bytes32 coinName, address account, uint256 rad) external isAuthorized(coinName) accountNotTreasury(account) {
        safeEngine.transferInternalCoins(coinName, account, address(this), rad);
        emit TakeFunds(coinName, account, rad);
    }

    // --- Stability Fee Transfer (Approved Accounts) ---
    /**
     * @notice Pull stability fees from the treasury (if your allowance permits)
     * @param coinName The name of the coin
     * @param dstAccount Address to transfer funds to
     * @param token Address of the token to transfer (in this case it must be the address of the ERC20 system coin).
     *              Used only to adhere to a standard for automated, on-chain treasuries
     * @param wad Amount of system coins (SF) to transfer (expressed as an 18 decimal number but the contract will transfer
              internal system coins that have 45 decimals)
     */
    function pullFunds(bytes32 coinName, address dstAccount, address token, uint256 wad) external {
        if (dstAccount == address(this)) return;
	      require(allowance[coinName][msg.sender].total >= multiply(wad, RAY), "MultiStabilityFeeTreasury/not-allowed");
        require(dstAccount != address(0), "MultiStabilityFeeTreasury/null-dst");
        require(dstAccount != extraSurplusReceiver[coinName], "MultiStabilityFeeTreasury/dst-cannot-be-accounting");
        require(wad > 0, "MultiStabilityFeeTreasury/null-transfer-amount");
        require(token == address(systemCoin[coinName]), "MultiStabilityFeeTreasury/token-unavailable");
        if (allowance[coinName][msg.sender].perBlock > 0) {
          require(addition(pulledPerBlock[coinName][msg.sender][block.number], multiply(wad, RAY)) <= allowance[coinName][msg.sender].perBlock, "MultiStabilityFeeTreasury/per-block-limit-exceeded");
        }

        pulledPerBlock[coinName][msg.sender][block.number] =
          addition(pulledPerBlock[coinName][msg.sender][block.number], multiply(wad, RAY));

        joinAllCoins(coinName);
        settleDebt(coinName);

        require(safeEngine.debtBalance(coinName, address(this)) == 0, "MultiStabilityFeeTreasury/outstanding-bad-debt");
        require(safeEngine.coinBalance(coinName, address(this)) >= multiply(wad, RAY), "MultiStabilityFeeTreasury/not-enough-funds");
        require(safeEngine.coinBalance(coinName, address(this)) >= pullFundsMinThreshold[coinName], "MultiStabilityFeeTreasury/below-pullFunds-min-threshold");

        // Update allowance and accumulator
        allowance[coinName][msg.sender].total = subtract(allowance[coinName][msg.sender].total, multiply(wad, RAY));
        expensesAccumulator[coinName]         = addition(expensesAccumulator[coinName], multiply(wad, RAY));

        // Transfer money
        safeEngine.transferInternalCoins(coinName, address(this), dstAccount, multiply(wad, RAY));

        emit PullFunds(coinName, msg.sender, dstAccount, token, multiply(wad, RAY), expensesAccumulator[coinName]);
    }

    // --- Treasury Maintenance ---
    /**
     * @notice Transfer surplus stability fees to the extraSurplusReceiver. This is here to make sure that the treasury
               doesn't accumulate fees that it doesn't even need in order to pay for allowances. It ensures
               that there are enough funds left in the treasury to account for projected expenses (latest expenses multiplied
               by an expense multiplier)
     * @param coinName The name of the coin to transfer
     */
    function transferSurplusFunds(bytes32 coinName) external coinIsInitialized(coinName) {
        require(now >= addition(latestSurplusTransferTime[coinName], surplusTransferDelay[coinName]), "MultiStabilityFeeTreasury/transfer-cooldown-not-passed");
        // Compute latest expenses
        uint256 latestExpenses = subtract(expensesAccumulator[coinName], accumulatorTag[coinName]);
        // Check if we need to keep more funds than the total capacity
        uint256 remainingFunds =
          (treasuryCapacity[coinName] <= divide(multiply(expensesMultiplier[coinName], latestExpenses), HUNDRED)) ?
          divide(multiply(expensesMultiplier[coinName], latestExpenses), HUNDRED) : treasuryCapacity[coinName];
        // Make sure to keep at least minimum funds
        remainingFunds = (divide(multiply(expensesMultiplier[coinName], latestExpenses), HUNDRED) <= minimumFundsRequired[coinName]) ?
                   minimumFundsRequired[coinName] : remainingFunds;
        // Set internal vars
        accumulatorTag[coinName]            = expensesAccumulator[coinName];
        latestSurplusTransferTime[coinName] = now;
        // Join all coins in system
        joinAllCoins(coinName);
        // Settle outstanding bad debt
        settleDebt(coinName);
        // Check that there's no bad debt left
        require(safeEngine.debtBalance(coinName, address(this)) == 0, "MultiStabilityFeeTreasury/outstanding-bad-debt");
        // Check if we have too much money
        if (safeEngine.coinBalance(coinName, address(this)) > remainingFunds) {
          // Make sure that we still keep min SF in treasury
          uint256 fundsToTransfer = subtract(safeEngine.coinBalance(coinName, address(this)), remainingFunds);
          // Transfer surplus to accounting engine
          safeEngine.transferInternalCoins(coinName, address(this), extraSurplusReceiver[coinName], fundsToTransfer);
          // Emit event
          emit TransferSurplusFunds(coinName, extraSurplusReceiver[coinName], fundsToTransfer);
        }
    }
}
