// CoinSavingsAccount.t.sol

// Copyright (C) 2017  DappHub, LLC
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

import "ds-test/test.sol";
import {SAFEEngine} from '../SAFEEngine.sol';
import {CoinSavingsAccount} from '../CoinSavingsAccount.sol';

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract CoinSavingsAccountTest is DSTest {
    Hevm hevm;

    SAFEEngine safeEngine;
    CoinSavingsAccount coinSavingsAccount;

    address accountingEngine;
    address self;
    address coinSavingsAccountB;

    function rad(uint wad_) internal pure returns (uint) {
        return wad_ * 10 ** 27;
    }
    function wad(uint rad_) internal pure returns (uint) {
        return rad_ / 10 ** 27;
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine = new SAFEEngine();
        coinSavingsAccount = new CoinSavingsAccount(address(safeEngine));
        safeEngine.addAuthorization(address(coinSavingsAccount));
        self = address(this);
        coinSavingsAccountB = address(coinSavingsAccount);

        accountingEngine = address(bytes20("accountingEngine"));
        coinSavingsAccount.modifyParameters("accountingEngine", accountingEngine);

        safeEngine.createUnbackedDebt(self, self, rad(100 ether));
        safeEngine.approveSAFEModification(address(coinSavingsAccount));
    }
    function test_save_0d() public {
        assertEq(safeEngine.coinBalance(self), rad(100 ether));

        coinSavingsAccount.deposit(100 ether);
        assertEq(wad(safeEngine.coinBalance(self)), 0 ether);
        assertEq(coinSavingsAccount.savings(self), 100 ether);

        coinSavingsAccount.updateAccumulatedRate();

        coinSavingsAccount.withdraw(100 ether);
        assertEq(wad(safeEngine.coinBalance(self)), 100 ether);
    }
    function test_save_1d() public {
        coinSavingsAccount.deposit(100 ether);
        coinSavingsAccount.modifyParameters("savingsRate", uint(1000000564701133626865910626));  // 5% / day
        hevm.warp(now + 1 days);
        coinSavingsAccount.updateAccumulatedRate();
        assertEq(coinSavingsAccount.savings(self), 100 ether);
        coinSavingsAccount.withdraw(100 ether);
        assertEq(wad(safeEngine.coinBalance(self)), 105 ether);
    }
    function test_update_rate_multi() public {
        coinSavingsAccount.deposit(100 ether);
        coinSavingsAccount.modifyParameters("savingsRate", uint(1000000564701133626865910626));  // 5% / day
        hevm.warp(now + 1 days);
        coinSavingsAccount.updateAccumulatedRate();
        assertEq(wad(safeEngine.coinBalance(coinSavingsAccountB)),   105 ether);
        coinSavingsAccount.modifyParameters("savingsRate", uint(1000001103127689513476993127));  // 10% / day
        hevm.warp(now + 1 days);
        coinSavingsAccount.updateAccumulatedRate();
        assertEq(wad(safeEngine.debtBalance(accountingEngine)), 15.5 ether);
        assertEq(wad(safeEngine.coinBalance(coinSavingsAccountB)), 115.5 ether);
        assertEq(coinSavingsAccount.totalSavings(), 100   ether);
        assertEq(coinSavingsAccount.accumulatedRate() / 10 ** 9, 1.155 ether);
    }
    function test_update_rate_multi_inBlock() public {
        coinSavingsAccount.updateAccumulatedRate();
        uint latestUpdateTime = coinSavingsAccount.latestUpdateTime();
        assertEq(latestUpdateTime, now);
        hevm.warp(now + 1 days);
        latestUpdateTime = coinSavingsAccount.latestUpdateTime();
        assertEq(latestUpdateTime, now - 1 days);
        coinSavingsAccount.updateAccumulatedRate();
        latestUpdateTime = coinSavingsAccount.latestUpdateTime();
        assertEq(latestUpdateTime, now);
        coinSavingsAccount.updateAccumulatedRate();
        latestUpdateTime = coinSavingsAccount.latestUpdateTime();
        assertEq(latestUpdateTime, now);
    }
    function test_save_multi() public {
        coinSavingsAccount.deposit(100 ether);
        coinSavingsAccount.modifyParameters("savingsRate", uint(1000000564701133626865910626));  // 5% / day
        hevm.warp(now + 1 days);
        coinSavingsAccount.updateAccumulatedRate();
        coinSavingsAccount.withdraw(50 ether);
        assertEq(wad(safeEngine.coinBalance(self)), 52.5 ether);
        assertEq(coinSavingsAccount.totalSavings(),          50.0 ether);

        coinSavingsAccount.modifyParameters("savingsRate", uint(1000001103127689513476993127));  // 10% / day
        hevm.warp(now + 1 days);
        coinSavingsAccount.updateAccumulatedRate();
        coinSavingsAccount.withdraw(50 ether);
        assertEq(wad(safeEngine.coinBalance(self)), 110.25 ether);
        assertEq(coinSavingsAccount.totalSavings(), 0);
    }
    function test_fresh_accumulatedRate() public {
        uint rho = coinSavingsAccount.latestUpdateTime();
        assertEq(rho, now);
        hevm.warp(now + 1 days);
        assertEq(rho, now - 1 days);
        coinSavingsAccount.updateAccumulatedRate();
        coinSavingsAccount.deposit(100 ether);
        assertEq(coinSavingsAccount.savings(self), 100 ether);
        coinSavingsAccount.withdraw(100 ether);
        // if we withdraw in the same transaction we should not earn interest
        assertEq(wad(safeEngine.coinBalance(self)), 100 ether);
    }
    function testFail_stale_accumulatedRate() public {
        coinSavingsAccount.modifyParameters("savingsRate", uint(1000000564701133626865910626));  // 5% / day
        coinSavingsAccount.updateAccumulatedRate();
        hevm.warp(now + 1 days);
        coinSavingsAccount.deposit(100 ether);
    }
    function test_modifyParameters() public {
        hevm.warp(now + 1);
        coinSavingsAccount.updateAccumulatedRate();
        coinSavingsAccount.modifyParameters("savingsRate", uint(1));
    }
    function testFail_modifyParameters() public {
        hevm.warp(now + 1);
        coinSavingsAccount.modifyParameters("savingsRate", uint(1));
    }
}
