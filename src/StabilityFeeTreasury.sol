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

    bytes32 public constant INTERNAL = bytes32("INTERNAL");

    mapping(address => uint) public allowance;

    CDPEngineLike   public cdpEngine;
    SystemCoinLike  public systemCoin;
    CoinJoinLike    public coinJoin;

    address public accountingEngine;

    uint256 public treasuryCapacity;           // max amount of SF that can be kept in treasury
    uint256 public minimumFundsRequired;       // minimum amount of SF that must be kept in the treasury at all times
    uint256 public expensesMultiplier;         // multiplier for expenses
    uint256 public surplusTransferDelay;       // minimum time between transferSurplusFunds calls
    uint256 public expensesAccumulator;        // expenses accumulator
    uint256 public accumulatorTag;             // latest tagged accumulator price
    uint256 public latestSurplusTransferTime;  // latest timestamp when transferSurplusFunds was called
    uint256 public contractEnabled;

    constructor(
      address cdpEngine_,
      address accountingEngine_,
      address coinJoin_,
      uint surplusTransferDelay_
    ) public {
        require(address(CoinJoinLike(coinJoin_).systemCoin()) != address(0), "StabilityFeeTreasury/null-system-coin");
        authorizedAccounts[msg.sender] = 1;
        cdpEngine                 = CDPEngineLike(cdpEngine_);
        accountingEngine          = accountingEngine_;
        coinJoin                  = CoinJoinLike(coinJoin_);
        systemCoin                = GemLike(coinJoin.systemCoin());
        surplusTransferDelay      = surplusTransferDelay_;
        latestSurplusTransferTime = now;
        expensesMultiplier        = WAD;
        contractEnabled           = 1;
        systemCoin.approve(address(coinJoin), uint(-1));
        cdpEngine.hope(address(coinJoin));
    }

    // --- Math ---
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;

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
        else if (parameter == "treasuryCapacity") treasuryCapacity = val;
        else if (parameter == "minimumFundsRequired") minimumFundsRequired = val;
        else if (parameter == "surplusTransferDelay") surplusTransferDelay = val;
        else revert("StabilityFeeTreasury/modify-unrecognized-param");
    }
    function disableContract() external emitLog isAuthorized {
        if (systemCoin.balanceOf(address(this)) > 0) {
          coinJoin.join(address(this), systemCoin.balanceOf(address(this)));
        }
        cdpEngine.move(address(this), accountingEngine, cdpEngine.good(address(this)));
        contractEnabled = 0;
    }

    // --- Utils ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- SF Transfer Allowance ---
    function allow(address account, uint wad) external emitLog isAuthorized {
        require(account != address(0), "StabilityFeeTreasury/null-account");
        allowance[account] = wad;
    }

    // --- Stability Fee Transfer (Governance) ---
    function giveFunds(bytes32 transferType, address account, uint rad) external emitLog isAuthorized {
        require(account != address(0), "StabilityFeeTreasury/null-account");
        if (transferType == INTERNAL) {
          require(add(mul(systemCoin.balanceOf(address(this)), RAY), cdpEngine.good(address(this))) >= rad, "StabilityFeeTreasury/not-enough-money");
          if (cdpEngine.coinBalance(address(this)) < rad) {
            coinJoin.join(address(this), systemCoin.balanceOf(address(this)));
          }
          expensesAccumulator = add(expensesAccumulator, rad);
          cdpEngine.transferInternalCoins(address(this), account, rad);
        } else {
          require(add(systemCoin.balanceOf(address(this)), div(cdpEngine.good(address(this)), RAY)) >= rad, "StabilityFeeTreasury/not-enough-money");
          if (systemCoin.balanceOf(address(this)) < rad) {
            coinJoin.exit(address(this), div(cdpEngine.good(address(this)), RAY));
          }
          expensesAccumulator = add(expensesAccumulator, mul(RAY, rad));
          systemCoin.transfer(account, rad);
        }
    }
    function takeFunds(bytes32 transferType, address account, uint rad) external emitLog isAuthorized {
        if (transferType == INTERNAL) {
          cdpEngine.move(account, address(this), rad);
        } else {
          systemCoin.transferFrom(account, address(this), rad);
        }
    }

    // --- Stability Fee Transfer (Approved Accounts) ---
    function pullFunds(address dstAccount, address token, uint wad) external emitLog returns (bool) {
        if (
          either(
            add(systemCoin.balanceOf(address(this)), div(cdpEngine.good(address(this)), RAY)) < wad,
            either(
              either(
                allowance[msg.sender] < wad,
                either(dstAccount == address(0), wad == 0)
              ),
              token != address(systemCoin)
            )
          )
        ) {
          return false;
        }
        allowance[msg.sender] = sub(allowance[msg.sender], wad);
        expensesAccumulator = add(expensesAccumulator, mul(wad, RAY));
        if (systemCoin.balanceOf(address(this)) < wad) {
          //TODO: wrap in try/catch
          coinJoin.exit(address(this), div(cdpEngine.good(address(this)), RAY));
        }
        //TODO: wrap in try/catch
        systemCoin.transfer(dstAccount, wad);
        return true;
    }

    // --- Treasury Maintenance ---
    function transferSurplusFunds() external {
        require(now >= add(latestSurplusTransferTime, surplusTransferDelay), "StabilityFeeTreasury/transfer-cooldown-not-passed");
        // Compute current accumulatorTag and minimum reserves
        uint latestExpenses         = sub(expensesAccumulator, accumulatorTag);
        uint minimumFundsRequired_  =
          (both(treasuryCapacity > 0, treasuryCapacity <= div(mul(expensesMultiplier, latestExpenses), WAD))) ?
          treasuryCapacity : div(mul(expensesMultiplier, latestExpenses), WAD);
        // Set internal vars
        accumulatorTag            = expensesAccumulator;
        latestSurplusTransferTime = now;
        // Join all coins in system
        if (systemCoin.balanceOf(address(this)) > 0) {
          coinJoin.join(address(this), systemCoin.balanceOf(address(this)));
        }
        // Check if we have too much money
        if (both(cdpEngine.good(address(this)) > minimumFundsRequired_, cdpEngine.good(address(this)) > minimumFundsRequired)) {
          // Check that we still keep min SF in treasury
          minimumFundsRequired_ =
            (sub(cdpEngine.good(address(this)), sub(cdpEngine.good(address(this)), minimumFundsRequired_)) < minimumFundsRequired) ?
            sub(cdpEngine.good(address(this)), minimumFundsRequired) : sub(cdpEngine.good(address(this)), minimumFundsRequired_);
          // Transfer surplus to accounting engine
          cdpEngine.move(address(this), accountingEngine, minimumFundsRequired_);
        }
    }
}
