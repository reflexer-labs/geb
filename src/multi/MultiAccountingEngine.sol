/// MultiAccountingEngine.sol

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

abstract contract SAFEEngineLike {
    function coinBalance(bytes32,address) virtual public view returns (uint256);
    function debtBalance(bytes32,address) virtual public view returns (uint256);
    function settleDebt(bytes32,uint256) virtual external;
    function transferInternalCoins(bytes32,address,address,uint256) virtual external;
}

contract MultiAccountingEngine {
    // --- Auth ---
    mapping (bytes32 => mapping(address => uint256)) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(bytes32 coinName, address account) external isAuthorized(coinName) {
        require(coinEnabled[coinName] == 1, "MultiAccountingEngine/coin-not-enabled");
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
        require(authorizedAccounts[coinName][msg.sender] == 1, "MultiAccountingEngine/account-not-authorized");
        _;
    }

    mapping (address => uint256) public systemComponents;
    /**
     * @notice Add a system component
     * @param component Component to auth
     */
    function addSystemComponent(address component) external {
        require(manager == msg.sender, "MultiAccountingEngine/invalid-manager");
        systemComponents[component] = 1;
        emit AddSystemComponent(component);
    }
    /**
     * @notice Remove a system component
      @param component Component to deauth
     */
    function removeSystemComponent(address component) external {
        require(manager == msg.sender, "MultiAccountingEngine/invalid-manager");
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

    /**
     * @notice Checks whether a coin is initialized
     */
    modifier coinIsInitialized(bytes32 coinName) {
        require(coinInitialized[coinName] == 1, "MultiAccountingEngine/coin-not-init");

        _;
    }

    // --- Data ---
    // SAFE database
    SAFEEngineLike               public safeEngine;
    // Manager address
    address                      public manager;
    // Address of the deployer
    address                      public deployer;
    // The address that gets coins when transferPostSettlementSurplus() is called
    address                      public postSettlementSurplusDrain;

    // Addresses that receive surplus
    mapping (bytes32 => address) public extraSurplusReceiver;
    /**
      Debt blocks that need to be covered by auctions. There is a delay to pop debt from
      this queue and either settle it with surplus that came from collateral auctions or with debt auctions
      that print protocol tokens
    **/
    mapping (bytes32 => mapping(uint256 => uint256)) public debtQueue;   // [unix timestamp => rad]
    // Addresses that popped debt out of the queue
    mapping (bytes32 => mapping(uint256 => address)) public debtPoppers; // [unix timestamp => address]
    // Mapping of coin states
    mapping (bytes32 => uint256) public coinEnabled;
    // Whether a coin has been initialized or not
    mapping (bytes32 => uint256) public coinInitialized;
    // Total debt in a queue (that the system tries to cover with collateral auctions)
    mapping (bytes32 => uint256) public totalQueuedDebt;                 // [rad]
    // Amount of extra surplus to transfer
    mapping (bytes32 => uint256) public surplusTransferAmount;           // [rad]
    // Amount of stability fees that need to accrue in this contract before any transfer can start
    mapping (bytes32 => uint256) public surplusBuffer;                   // [rad]
    // When a coin was disabled
    mapping (bytes32 => uint256) public disableTimestamp;                // [unix timestamp]

    // Delay after which debt can be popped from debtQueue
    uint256 public popDebtDelay;                                         // [seconds]
    // Time to wait (post settlement) until any remaining surplus can be transferred out so GlobalSettlement can finalize
    uint256 public disableCooldown;                                      // [seconds]

    // --- Events ---
    event AddAuthorization(bytes32 indexed coinName, address account);
    event RemoveAuthorization(bytes32 indexed coinName, address account);
    event AddSystemComponent(address component);
    event RemoveSystemComponent(address component);
    event ModifyParameters(bytes32 indexed parameter, address data);
    event ModifyParameters(bytes32 indexed coinName, bytes32 indexed parameter, uint256 data);
    event ModifyParameters(bytes32 indexed coinName, bytes32 indexed parameter, address data);
    event PushDebtToQueue(bytes32 indexed coinName, uint256 indexed timestamp, uint256 debtQueueBlock, uint256 totalQueuedDebt);
    event PopDebtFromQueue(bytes32 indexed coinName, uint256 indexed timestamp, uint256 debtQueueBlock, uint256 totalQueuedDebt);
    event SettleDebt(bytes32 indexed coinName, uint256 rad, uint256 coinBalance, uint256 debtBalance);
    event DisableCoin(bytes32 indexed coinName, uint256 indexed coinBalance, uint256 debtBalance);
    event InitializeCoin(bytes32 indexed coinName, uint256 surplusTransferAmount, uint256 surplusBuffer);
    event TransferPostSettlementSurplus(bytes32 indexed coinName, address postSettlementSurplusDrain, uint256 coinBalance, uint256 debtBalance);
    event TransferExtraSurplus(bytes32 indexed coinName, address indexed extraSurplusReceiver, uint256 coinBalance);

    // --- Init ---
    constructor(
      address safeEngine_,
      address postSettlementSurplusDrain_,
      uint256 popDebtDelay_,
      uint256 disableCooldown_
    ) public {
        require(popDebtDelay_ > 0, "MultiAccountingEngine/null-pop-debt-delay");
        require(disableCooldown_ > 0, "MultiAccountingEngine/null-disable-cooldown");
        manager                    = msg.sender;
        deployer                   = msg.sender;
        popDebtDelay               = popDebtDelay_;
        disableCooldown            = disableCooldown_;
        postSettlementSurplusDrain = postSettlementSurplusDrain_;
        safeEngine                 = SAFEEngineLike(safeEngine_);
    }

    // --- Boolean Logic ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    // --- Math ---
    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "MultiAccountingEngine/add-overflow");
    }
    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "MultiAccountingEngine/sub-underflow");
    }
    function minimum(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x <= y ? x : y;
    }

    // --- Administration ---
    /**
     * @notice Initialize a new coin
     * @param coinName The name of the coin
     * @param surplusTransferAmount_ The amount of extra surplus coinName transferred out of this contract
     * @param surplusBuffer_ The initial surplus buffer for coinName
     */
    function initializeCoin(bytes32 coinName, uint256 surplusTransferAmount_, uint256 surplusBuffer_) external {
        require(deployer == msg.sender, "MultiAccountingEngine/caller-not-deployer");
        require(coinInitialized[coinName] == 0, "MultiAccountingEngine/already-init");
        require(surplusTransferAmount_ > 0, "MultiAccountingEngine/null-transfer-amount");
        require(surplusBuffer_ > 0, "MultiAccountingEngine/null-surplus-buffer");

        authorizedAccounts[coinName][msg.sender] = 1;

        coinInitialized[coinName] = 1;
        coinEnabled[coinName]     = 1;

        surplusTransferAmount[coinName] = surplusTransferAmount_;
        surplusBuffer[coinName]         = surplusBuffer_;

        emit InitializeCoin(coinName, surplusTransferAmount_, surplusBuffer_);
        emit AddAuthorization(coinName, msg.sender);
    }
    /**
     * @notice Set an address param
     * @param parameter The name of the parameter to change
     * @param data The new manager
     */
    function modifyParameters(bytes32 parameter, address data) external {
        require(manager == msg.sender, "MultiAccountingEngine/invalid-manager");
        if (parameter == "manager") {
          manager = data;
        } else if (parameter == "deployer") {
          require(data != address(0), "MultiAccountingEngine/null-deployer");
          deployer = data;
        }
        else revert("MultiAccountingEngine/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }
    /**
     * @notice Modify a general uint256 param
     * @param coinName The name of the coin to change a param for
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(bytes32 coinName, bytes32 parameter, uint256 data) external isAuthorized(coinName) {
        if (parameter == "surplusTransferAmount") surplusTransferAmount[coinName] = data;
        else if (parameter == "surplusBuffer") surplusBuffer[coinName] = data;
        else revert("MultiAccountingEngine/modify-unrecognized-param");
        emit ModifyParameters(coinName, parameter, data);
    }
    /**
     * @notice Modify a general address param
     * @param coinName The name of the coin to change a param for
     * @param parameter The name of the parameter
     * @param data New address for the parameter
     */
    function modifyParameters(bytes32 coinName, bytes32 parameter, address data) external isAuthorized(coinName) {
        if (parameter == "extraSurplusReceiver") extraSurplusReceiver[coinName] = data;
        else revert("MultiAccountingEngine/modify-unrecognized-param");
        emit ModifyParameters(coinName, parameter, data);
    }

    // --- Getters ---
    /*
    * @notice Returns the amount of bad debt that is not in the debtQueue
    * @param coinName The name of the coin to get the unqueued debt for
    */
    function unqueuedDebt(bytes32 coinName) public view returns (uint256) {
        return subtract(safeEngine.debtBalance(coinName, address(this)), totalQueuedDebt[coinName]);
    }

    // --- Debt Queueing ---
    /**
     * @notice Push bad debt into a queue
     * @dev Debt is locked in a queue to give the system enough time to auction collateral
     *      and gather surplus
     * @param coinName The name of the coin to push debt for
     * @param debtBlock Amount of debt to push
     */
    function pushDebtToQueue(bytes32 coinName, uint256 debtBlock) external isSystemComponent coinIsInitialized(coinName) {
        debtQueue[coinName][now]  = addition(debtQueue[coinName][now], debtBlock);
        totalQueuedDebt[coinName] = addition(totalQueuedDebt[coinName], debtBlock);
        emit PushDebtToQueue(coinName, now, debtQueue[coinName][now], totalQueuedDebt[coinName]);
    }
    /**
     * @notice Pop a block of bad debt from the debt queue
     * @dev A block of debt can be popped from the queue after popDebtDelay seconds have passed since it was
     *         added there
     * @param coinName The name of the coin to pop debt for
     * @param debtBlockTimestamp Timestamp of the block of debt that should be popped out
     */
    function popDebtFromQueue(bytes32 coinName, uint256 debtBlockTimestamp) external coinIsInitialized(coinName) {
        require(addition(debtBlockTimestamp, popDebtDelay) <= now, "MultiAccountingEngine/pop-debt-delay-not-passed");
        require(debtQueue[coinName][debtBlockTimestamp] > 0, "MultiAccountingEngine/null-debt-block");
        totalQueuedDebt[coinName] = subtract(totalQueuedDebt[coinName], debtQueue[coinName][debtBlockTimestamp]);
        debtPoppers[coinName][debtBlockTimestamp] = msg.sender;
        emit PopDebtFromQueue(coinName, now, debtQueue[coinName][debtBlockTimestamp], totalQueuedDebt[coinName]);
        debtQueue[coinName][debtBlockTimestamp] = 0;
    }

    // Debt settlement
    /**
     * @notice Destroy an equal amount of coins and bad debt
     * @dev We can only destroy debt that is not locked in the queue and also not in a debt auction
     * @param coinName The name of the coin to settle debt for
     * @param rad Amount of coins/debt to destroy (number with 45 decimals)
     * @param coinName The name of the coin to settle debt for
    **/
    function settleDebt(bytes32 coinName, uint256 rad) public coinIsInitialized(coinName) {
        require(rad <= safeEngine.coinBalance(coinName, address(this)), "MultiAccountingEngine/insufficient-surplus");
        require(rad <= unqueuedDebt(coinName), "MultiAccountingEngine/insufficient-debt");
        safeEngine.settleDebt(coinName, rad);
        emit SettleDebt(coinName, rad, safeEngine.coinBalance(coinName, address(this)), safeEngine.debtBalance(coinName, address(this)));
    }

    // Extra surplus transfers
    /**
     * @notice Send surplus to an address as an alternative to surplus auctions
     * @dev We can only transfer surplus if we wait at least 'surplusTransferDelay' seconds since the last
     *      transfer, if we keep enough surplus in the buffer and if there is no bad debt left to settle
     * @param coinName The name of the coin to transfer surplus for
    **/
    function transferExtraSurplus(bytes32 coinName) external coinIsInitialized(coinName) {
        require(extraSurplusReceiver[coinName] != address(0), "MultiAccountingEngine/null-surplus-receiver");
        require(surplusTransferAmount[coinName] > 0, "MultiAccountingEngine/null-amount-to-transfer");
        settleDebt(coinName, unqueuedDebt(coinName));
        require(
          safeEngine.coinBalance(coinName, address(this)) >=
          addition(addition(safeEngine.debtBalance(coinName, address(this)), surplusTransferAmount[coinName]), surplusBuffer[coinName]),
          "MultiAccountingEngine/insufficient-surplus"
        );
        require(
          unqueuedDebt(coinName) == 0,
          "MultiAccountingEngine/debt-not-zero"
        );
        safeEngine.transferInternalCoins(coinName, address(this), extraSurplusReceiver[coinName], surplusTransferAmount[coinName]);
        emit TransferExtraSurplus(coinName, extraSurplusReceiver[coinName], safeEngine.coinBalance(coinName, address(this)));
    }

    /**
     * @notice Disable a coin (normally called by Global Settlement)
     * @dev When it's being disabled, the contract will record the current timestamp. Afterwards,
     *      the contract tries to settle as much debt as possible (if there's any) with any surplus that's
     *      left in the MultiAccountingEngine
     * @param coinName The name of the coin to disable
    **/
    function disableCoin(bytes32 coinName) external isSystemComponent {
        require(coinEnabled[coinName] == 1, "MultiAccountingEngine/coin-not-enabled");
        require(coinInitialized[coinName] == 1, "MultiAccountingEngine/coin-not-init");

        coinEnabled[coinName]          = 0;
        totalQueuedDebt[coinName]      = 0;
        extraSurplusReceiver[coinName] = address(0);
        disableTimestamp[coinName]     = now;

        safeEngine.settleDebt(
          coinName, minimum(safeEngine.coinBalance(coinName, address(this)), safeEngine.debtBalance(coinName, address(this)))
        );

        emit DisableCoin(
          coinName, safeEngine.coinBalance(coinName, address(this)), safeEngine.debtBalance(coinName, address(this))
        );
    }
    /**
     * @notice Transfer any remaining surplus after the disable cooldown has passed. Meant to be a backup in case GlobalSettlement
               has a bug, governance doesn't have power over the system and there's still surplus left in the AccountingEngine
               which then blocks GlobalSettlement.setOutstandingCoinSupply.
     * @dev Transfer any remaining surplus after disableCooldown seconds have passed since disabling a coin
    **/
    function transferPostSettlementSurplus(bytes32 coinName) external {
        require(coinEnabled[coinName] == 0, "MultiAccountingEngine/coin-not-disabled");
        require(coinInitialized[coinName] == 1, "MultiAccountingEngine/coin-not-init");
        require(addition(disableTimestamp[coinName], disableCooldown) <= now, "MultiAccountingEngine/cooldown-not-passed");

        safeEngine.settleDebt(
          coinName, minimum(safeEngine.coinBalance(coinName, address(this)), safeEngine.debtBalance(coinName, address(this)))
        );
        safeEngine.transferInternalCoins(
          coinName, address(this), postSettlementSurplusDrain, safeEngine.coinBalance(coinName, address(this))
        );
        emit TransferPostSettlementSurplus(
          coinName,
          postSettlementSurplusDrain,
          safeEngine.coinBalance(coinName, address(this)),
          safeEngine.debtBalance(coinName, address(this))
        );
    }
}
