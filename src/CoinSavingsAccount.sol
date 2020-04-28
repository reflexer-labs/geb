/// CoinSavingsAccount.sol

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

pragma solidity ^0.5.15;

import "./Logging.sol";

/*
   "Savings Coin" are obtained when the core coin created by the protocol
   is deposited into this contract. Each "Savings Coin" accrues interest
   at the "Savings Rate". This contract does not implement a user tradeable token
   and is intended to be used with adapters.
         --- `save` your `coin` in the `savings account` ---
   - `savingsRate`: the Savings Rate
   - `savings`: user balance of Savings Coins
   - `deposit`: start saving some coins
   - `withdraw`: remove some coins
   - `updateAccumulatedRate`: perform rate collection
*/

contract CDPEngineLike {
    function transferInternalCoins(address,address,uint256) external;
    function createUnbackedDebt(address,address,uint256) external;
}

contract CoinSavingsAccount is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "CoinSavingsAccount/account-not-authorized");
        _;
    }

    // --- Events ---
    event UpdateAccumulatedRate(uint newAccumulatedRate, uint coinAmount);

    // --- Data ---
    mapping (address => uint256) public savings;

    uint256 public totalSavings;
    uint256 public savingsRate;
    uint256 public accumulatedRate;

    CDPEngineLike public cdpEngine;
    address public accountingEngine;
    uint256 public latestUpdateTime;

    uint256 public contractEnabled;

    // --- Init ---
    constructor(address cdpEngine_) public {
        authorizedAccounts[msg.sender] = 1;
        cdpEngine = CDPEngineLike(cdpEngine_);
        savingsRate = RAY;
        accumulatedRate = RAY;
        latestUpdateTime = now;
        contractEnabled = 1;
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;
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

    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, y) / RAY;
    }

    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, uint256 data) external emitLog isAuthorized {
        require(contractEnabled == 1, "CoinSavingsAccount/contract-not-enabled");
        require(now == latestUpdateTime, "CoinSavingsAccount/accumulation-time-not-updated");
        if (parameter == "savingsRate") savingsRate = data;
        else revert("CoinSavingsAccount/modify-unrecognized-param");
    }

    function modifyParameters(bytes32 parameter, address addr) external emitLog isAuthorized {
        if (parameter == "accountingEngine") accountingEngine = addr;
        else revert("CoinSavingsAccount/modify-unrecognized-param");
    }

    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
        savingsRate = RAY;
    }

    // --- Savings Rate Accumulation ---
    function updateAccumulatedRate() external emitLog returns (uint newAccumulatedRate) {
        if (now <= latestUpdateTime) return accumulatedRate;
        newAccumulatedRate = rmul(rpow(savingsRate, sub(now, latestUpdateTime), RAY), accumulatedRate);
        uint accumulatedRate_ = sub(newAccumulatedRate, accumulatedRate);
        accumulatedRate = newAccumulatedRate;
        latestUpdateTime = now;
        cdpEngine.createUnbackedDebt(address(accountingEngine), address(this), mul(totalSavings, accumulatedRate_));
        emit UpdateAccumulatedRate(newAccumulatedRate, mul(totalSavings, accumulatedRate_));
    }
    function nextAccumulatedRate() external view returns (uint) {
        if (now == latestUpdateTime) return accumulatedRate;
        return rmul(rpow(savingsRate, sub(now, latestUpdateTime), RAY), accumulatedRate);
    }

    // --- Savings Management ---
    function deposit(uint wad) external emitLog {
        require(now == latestUpdateTime, "CoinSavingsAccount/accumulation-time-not-updated");
        savings[msg.sender] = add(savings[msg.sender], wad);
        totalSavings        = add(totalSavings, wad);
        cdpEngine.transferInternalCoins(msg.sender, address(this), mul(accumulatedRate, wad));
    }

    function withdraw(uint wad) external emitLog {
        savings[msg.sender] = sub(savings[msg.sender], wad);
        totalSavings        = sub(totalSavings, wad);
        cdpEngine.transferInternalCoins(address(this), msg.sender, mul(accumulatedRate, wad));
    }
}
