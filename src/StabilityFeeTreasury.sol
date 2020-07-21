/// StabilityFeeTreasury.sol

// Copyright (C) 2020 Reflexer Labs, INC

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

pragma solidity ^0.6.7;

import "./Logging.sol";

abstract contract CDPEngineLike {
    function approveCDPModification(address) virtual external;
    function denyCDPModification(address) virtual external;
    function transferInternalCoins(address,address,uint) virtual external;
    function coinBalance(address) virtual public view returns (uint);
}
abstract contract SystemCoinLike {
    function balanceOf(address) virtual public view returns (uint);
    function approve(address, uint) virtual public returns (uint);
    function transfer(address,uint) virtual public returns (bool);
    function transferFrom(address,address,uint) virtual public returns (bool);
}
abstract contract CoinJoinLike {
    function systemCoin() virtual public view returns (address);
    function join(address, uint) virtual external;
    function exit(address, uint) virtual external;
}

contract StabilityFeeTreasury is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "StabilityFeeTreasury/account-not-authorized");
        _;
    }

    // --- Events ---
    event TransferSurplusFunds(address accountingEngine, uint fundsToTransfer);

    mapping(address => uint) public allowance;

    CDPEngineLike   public cdpEngine;
    SystemCoinLike  public systemCoin;
    CoinJoinLike    public coinJoin;

    address public accountingEngine;

    uint256 public treasuryCapacity;           // max amount of SF that can be kept in treasury                        [rad]
    uint256 public minimumFundsRequired;       // minimum amount of SF that must be kept in the treasury at all times  [rad]
    uint256 public expensesMultiplier;         // multiplier for expenses                                              [hundred]
    uint256 public surplusTransferDelay;       // minimum time between transferSurplusFunds calls                      [seconds]
    uint256 public expensesAccumulator;        // expenses accumulator                                                 [rad]
    uint256 public accumulatorTag;             // latest tagged accumulator price                                      [rad]
    uint256 public latestSurplusTransferTime;  // latest timestamp when transferSurplusFunds was called                [seconds]
    uint256 public contractEnabled;

    constructor(
        address cdpEngine_,
        address accountingEngine_,
        address coinJoin_
    ) public {
        require(address(CoinJoinLike(coinJoin_).systemCoin()) != address(0), "StabilityFeeTreasury/null-system-coin");
        authorizedAccounts[msg.sender] = 1;
        cdpEngine                 = CDPEngineLike(cdpEngine_);
        accountingEngine          = accountingEngine_;
        coinJoin                  = CoinJoinLike(coinJoin_);
        systemCoin                = SystemCoinLike(coinJoin.systemCoin());
        latestSurplusTransferTime = now;
        expensesMultiplier        = HUNDRED;
        contractEnabled           = 1;
        systemCoin.approve(address(coinJoin), uint(-1));
        cdpEngine.approveCDPModification(address(coinJoin));
    }

    // --- Math ---
    uint256 constant HUNDRED = 10 ** 2;
    uint256 constant RAY     = 10 ** 27;

    function addition(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x);
    }
    function addition(int x, int y) internal pure returns (int z) {
        z = x + y;
        if (y <= 0) require(z <= x);
        if (y  > 0) require(z > x);
    }
    function subtract(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function subtract(int x, int y) internal pure returns (int z) {
        z = x - y;
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }
    function multiply(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function divide(uint x, uint y) internal pure returns (uint z) {
        require(y > 0);
        z = x / y;
        require(z <= x);
    }

    // --- Administration ---
    /**
     * @notice Modify contract addresses
     * @param parameter The name of the contract whose address will be changed
     * @param addr New address for the contract
     */
    function modifyParameters(bytes32 parameter, address addr) external emitLog isAuthorized {
        require(contractEnabled == 1, "StabilityFeeTreasury/contract-not-enabled");
        require(addr != address(0), "StabilityFeeTreasury/null-addr");
        if (parameter == "accountingEngine") accountingEngine = addr;
        else revert("StabilityFeeTreasury/modify-unrecognized-param");
    }
    /**
     * @notice Modify uint256 parameters
     * @param parameter The name of the parameter to modify
     * @param val New parameter value
     */
    function modifyParameters(bytes32 parameter, uint val) external emitLog isAuthorized {
        require(contractEnabled == 1, "StabilityFeeTreasury/not-live");
        if (parameter == "expensesMultiplier") expensesMultiplier = val;
        else if (parameter == "treasuryCapacity") {
          require(val >= minimumFundsRequired, "StabilityFeeTreasury/capacity-lower-than-min-funds");
          treasuryCapacity = val;
        }
        else if (parameter == "minimumFundsRequired") {
          require(val <= treasuryCapacity, "StabilityFeeTreasury/min-funds-higher-than-capacity");
          minimumFundsRequired = val;
        }
        else if (parameter == "surplusTransferDelay") surplusTransferDelay = val;
        else revert("StabilityFeeTreasury/modify-unrecognized-param");
    }
    /**
     * @notice Disable this contract (normally called by GlobalSettlement)
     */
    function disableContract() external emitLog isAuthorized {
        require(contractEnabled == 1, "StabilityFeeTreasury/already-disabled");
        contractEnabled = 0;
        if (systemCoin.balanceOf(address(this)) > 0) {
          coinJoin.join(address(this), systemCoin.balanceOf(address(this)));
        }
        cdpEngine.transferInternalCoins(address(this), accountingEngine, cdpEngine.coinBalance(address(this)));
    }

    // --- Utils ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }
    /**
     * @notice Join all ERC20 system coins that the treasury has inside CDPEngine
     */
    function joinAllCoins() internal {
        if (systemCoin.balanceOf(address(this)) > 0) {
          coinJoin.join(address(this), systemCoin.balanceOf(address(this)));
        }
    }

    // --- SF Transfer Allowance ---
    /**
     * @notice Modify an address' allowance in order to withdraw SF from the treasury
     * @param account The approved address
     * @param wad The approved amount of SF to withdraw (number with 18 decimals)
     */
    function allow(address account, uint wad) external emitLog isAuthorized {
        require(account != address(0), "StabilityFeeTreasury/null-account");
        allowance[account] = wad;
    }

    // --- Stability Fee Transfer (Governance) ---
    /**
     * @notice Governance transfers SF to an address
     * @param account Address to transfer SF to
     * @param rad Amount of internal system coins to transfer (a number with 45 decimals)
     */
    function giveFunds(address account, uint rad) external emitLog isAuthorized {
        require(account != address(0), "StabilityFeeTreasury/null-account");
        joinAllCoins();
        require(cdpEngine.coinBalance(address(this)) >= rad, "StabilityFeeTreasury/not-enough-funds");

        expensesAccumulator = addition(expensesAccumulator, rad);
        cdpEngine.transferInternalCoins(address(this), account, rad);
    }
    /**
     * @notice Governance takes funds from an address
     * @param account Address to take system coins from
     * @param rad Amount of internal system coins to take from the account (a number with 45 decimals)
     */
    function takeFunds(address account, uint rad) external emitLog isAuthorized {
        cdpEngine.transferInternalCoins(account, address(this), rad);
    }

    // --- Stability Fee Transfer (Approved Accounts) ---
    /**
     * @notice Pull stability fees from the treasury (if your allowance permits)
     * @param dstAccount Address to transfer funds to
     * @param token Address of the token to transfer (in this case it must be the address of the ERC20 system coin).
     *              Used only to adhere to a standard for automated, on-chain treasuries
     * @param wad Amount of system coins (SF) to transfer (expressed as an 18 decimal number but the contract will transfer
              internal system coins that have 45 decimals)
     */
    function pullFunds(address dstAccount, address token, uint wad) external emitLog {
        require(allowance[msg.sender] >= wad, "StabilityFeeTreasury/not-allowed");
        require(dstAccount != address(0), "StabilityFeeTreasury/null-dst");
        require(wad > 0, "StabilityFeeTreasury/null-transfer-amount");
        require(token == address(systemCoin), "StabilityFeeTreasury/token-unavailable");

        joinAllCoins();
        require(cdpEngine.coinBalance(address(this)) >= multiply(wad, RAY), "StabilityFeeTreasury/not-enough-funds");

        // Update allowance and accumulator
        allowance[msg.sender] = subtract(allowance[msg.sender], multiply(wad, RAY));
        expensesAccumulator   = addition(expensesAccumulator, multiply(wad, RAY));

        // Transfer money
        cdpEngine.transferInternalCoins(address(this), dstAccount, multiply(wad, RAY));
    }

    // --- Treasury Maintenance ---
    /**
     * @notice Tranfer surplus stability fees to the AccountingEngine. This is here to make sure that the treasury
               doesn't accumulate too many fees that it doesn't even need in order to pay for allowances. It ensures
               that there are enough funds left in the treasury to account for projected expenses (latest expenses multiplied
               by an expense multiplier)
     */
    function transferSurplusFunds() external emitLog {
        require(now >= addition(latestSurplusTransferTime, surplusTransferDelay), "StabilityFeeTreasury/transfer-cooldown-not-passed");
        // Compute latest expenses
        uint latestExpenses = subtract(expensesAccumulator, accumulatorTag);
        // Check if we need to keep more funds than the total capacity
        uint remainingFunds =
          (treasuryCapacity <= divide(multiply(expensesMultiplier, latestExpenses), HUNDRED)) ?
          divide(multiply(expensesMultiplier, latestExpenses), HUNDRED) : treasuryCapacity;
        // Make sure to keep at least minimum funds
        remainingFunds = (divide(multiply(expensesMultiplier, latestExpenses), HUNDRED) <= minimumFundsRequired) ?
                   minimumFundsRequired : remainingFunds;
        // Set internal vars
        accumulatorTag            = expensesAccumulator;
        latestSurplusTransferTime = now;
        // Join all coins in system
        joinAllCoins();
        // Check if we have too much money
        if (cdpEngine.coinBalance(address(this)) > remainingFunds) {
          // Make sure that we still keep min SF in treasury
          uint fundsToTransfer = subtract(cdpEngine.coinBalance(address(this)), remainingFunds);
          // Transfer surplus to accounting engine
          cdpEngine.transferInternalCoins(address(this), accountingEngine, fundsToTransfer);
          // Emit event
          emit TransferSurplusFunds(accountingEngine, fundsToTransfer);
        }
    }
}
