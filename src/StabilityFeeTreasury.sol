/// StabilityFeeTreasury.sol

// Copyright (C) 2020 Stefan C. Ionescu <stefanionescu@protonmail.com>

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

contract CDPEngineLike {
    function approveCDPModification(address) external;
    function denyCDPModification(address) external;
    function transferInternalCoins(address,address,uint) external;
    function coinBalance(address) external view returns (uint);
}
contract SystemCoinLike {
    function balanceOf(address) external view returns (uint);
    function approve(address, uint) external returns (uint);
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
}
contract CoinJoinLike {
    function systemCoin() external view returns (address);
    function join(address, uint) external;
    function exit(address, uint) external;
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
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function div(uint x, uint y) internal pure returns (uint z) {
        require(y > 0);
        z = x / y;
        require(z <= x);
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, address addr) external emitLog isAuthorized {
        require(contractEnabled == 1, "StabilityFeeTreasury/contract-not-enabled");
        require(addr != address(0), "StabilityFeeTreasury/null-addr");
        if (parameter == "accountingEngine") accountingEngine = addr;
        else revert("StabilityFeeTreasury/modify-unrecognized-param");
    }
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
    function joinAllCoins() internal {
        if (systemCoin.balanceOf(address(this)) > 0) {
          coinJoin.join(address(this), systemCoin.balanceOf(address(this)));
        }
    }

    // --- SF Transfer Allowance ---
    function allow(address account, uint wad) external emitLog isAuthorized {
        require(account != address(0), "StabilityFeeTreasury/null-account");
        allowance[account] = wad;
    }

    // --- Stability Fee Transfer (Governance) ---
    function giveFunds(address account, uint rad) external emitLog isAuthorized {
        require(account != address(0), "StabilityFeeTreasury/null-account");
        joinAllCoins();
        require(cdpEngine.coinBalance(address(this)) >= rad, "StabilityFeeTreasury/not-enough-funds");

        expensesAccumulator = add(expensesAccumulator, rad);
        cdpEngine.transferInternalCoins(address(this), account, rad);
    }
    function takeFunds(address account, uint rad) external emitLog isAuthorized {
        cdpEngine.transferInternalCoins(account, address(this), rad);
    }

    // --- Stability Fee Transfer (Approved Accounts) ---
    function pullFunds(address dstAccount, address token, uint wad) external emitLog {
        require(allowance[msg.sender] >= wad, "StabilityFeeTreasury/not-allowed");
        require(dstAccount != address(0), "StabilityFeeTreasury/null-dst");
        require(wad > 0, "StabilityFeeTreasury/null-transfer-amount");
        require(token == address(systemCoin), "StabilityFeeTreasury/token-unavailable");

        joinAllCoins();
        require(cdpEngine.coinBalance(address(this)) >= mul(wad, RAY), "StabilityFeeTreasury/not-enough-funds");

        // Update allowance and accumulator
        allowance[msg.sender] = sub(allowance[msg.sender], mul(wad, RAY));
        expensesAccumulator   = add(expensesAccumulator, mul(wad, RAY));

        // Transfer money
        cdpEngine.transferInternalCoins(address(this), dstAccount, mul(wad, RAY));
    }

    // --- Treasury Maintenance ---
    function transferSurplusFunds() external emitLog {
        require(now >= add(latestSurplusTransferTime, surplusTransferDelay), "StabilityFeeTreasury/transfer-cooldown-not-passed");
        // Compute latestExpenses and capacity
        uint latestExpenses = sub(expensesAccumulator, accumulatorTag);
        // Check if we need to keep more funds than the total capacity
        uint remainingFunds =
          (treasuryCapacity <= div(mul(expensesMultiplier, latestExpenses), HUNDRED)) ?
          div(mul(expensesMultiplier, latestExpenses), HUNDRED) : treasuryCapacity;
        // Make sure to keep at least minimum funds
        remainingFunds = (div(mul(expensesMultiplier, latestExpenses), HUNDRED) <= minimumFundsRequired) ?
                   minimumFundsRequired : remainingFunds;
        // Set internal vars
        accumulatorTag            = expensesAccumulator;
        latestSurplusTransferTime = now;
        // Join all coins in system
        joinAllCoins();
        // Check if we have too much money
        if (cdpEngine.coinBalance(address(this)) > remainingFunds) {
          // Make sure that we still keep min SF in treasury
          uint fundsToTransfer = sub(cdpEngine.coinBalance(address(this)), remainingFunds);
          // Transfer surplus to accounting engine
          cdpEngine.transferInternalCoins(address(this), accountingEngine, fundsToTransfer);
          // Emit event
          emit TransferSurplusFunds(accountingEngine, fundsToTransfer);
        }
    }
}
