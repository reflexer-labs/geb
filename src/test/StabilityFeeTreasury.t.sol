/// StabilityFeeTreasury.t.sol

// Copyright (C) 2015-2020  DappHub, LLC
// Copyright (C) 2020       Reflexer Labs, INC

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program. If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.6.7;

import "ds-test/test.sol";

import {Coin} from '../Coin.sol';
import {SAFEEngine} from '../SAFEEngine.sol';
import {StabilityFeeTreasury} from '../StabilityFeeTreasury.sol';
import {CoinJoin} from '../BasicTokenAdapters.sol';

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract Usr {
    function approveSAFEModification(address safeEngine, address lad) external {
        SAFEEngine(safeEngine).approveSAFEModification(lad);
    }
    function giveFunds(address stabilityFeeTreasury, address lad, uint rad) external {
        StabilityFeeTreasury(stabilityFeeTreasury).giveFunds(lad, rad);
    }
    function takeFunds(address stabilityFeeTreasury, address lad, uint rad) external {
        StabilityFeeTreasury(stabilityFeeTreasury).takeFunds(lad, rad);
    }
    function pullFunds(address stabilityFeeTreasury, address gal, address tkn, uint wad) external {
        return StabilityFeeTreasury(stabilityFeeTreasury).pullFunds(gal, tkn, wad);
    }
    function approve(address systemCoin, address gal) external {
        Coin(systemCoin).approve(gal, uint(-1));
    }
}

contract StabilityFeeTreasuryTest is DSTest {
    Hevm hevm;

    SAFEEngine safeEngine;
    StabilityFeeTreasury stabilityFeeTreasury;

    Coin systemCoin;
    CoinJoin systemCoinA;

    Usr usr;

    address alice = address(0x1);
    address bob = address(0x2);

    uint constant HUNDRED = 10 ** 2;
    uint constant RAY     = 10 ** 27;

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }
    function rad(uint wad) internal pure returns (uint) {
        return wad * RAY;
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        usr = new Usr();

        safeEngine  = new SAFEEngine();
        systemCoin = new Coin("Coin", "COIN", 99);
        systemCoinA = new CoinJoin(address(safeEngine), address(systemCoin));
        stabilityFeeTreasury = new StabilityFeeTreasury(address(safeEngine), alice, address(systemCoinA));

        systemCoin.addAuthorization(address(systemCoinA));
        stabilityFeeTreasury.addAuthorization(address(systemCoinA));

        safeEngine.createUnbackedDebt(bob, address(stabilityFeeTreasury), rad(200 ether));
        safeEngine.createUnbackedDebt(bob, address(this), rad(100 ether));

        safeEngine.approveSAFEModification(address(systemCoinA));
        systemCoinA.exit(address(this), 100 ether);

        usr.approveSAFEModification(address(safeEngine), address(stabilityFeeTreasury));
    }

    function test_setup() public {
        assertEq(stabilityFeeTreasury.surplusTransferDelay(), 0);
        assertEq(address(stabilityFeeTreasury.safeEngine()), address(safeEngine));
        assertEq(address(stabilityFeeTreasury.extraSurplusReceiver()), alice);
        assertEq(stabilityFeeTreasury.latestSurplusTransferTime(), now);
        assertEq(stabilityFeeTreasury.expensesMultiplier(), HUNDRED);
        assertEq(systemCoin.balanceOf(address(this)), 100 ether);
        assertEq(safeEngine.coinBalance(address(alice)), 0);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(200 ether));
    }
    function test_modify_accounting_engine() public {
        stabilityFeeTreasury.modifyParameters("extraSurplusReceiver", bob);
        assertEq(stabilityFeeTreasury.extraSurplusReceiver(), bob);
    }
    function test_modify_params() public {
        stabilityFeeTreasury.modifyParameters("expensesMultiplier", 5 * HUNDRED);
        stabilityFeeTreasury.modifyParameters("treasuryCapacity", rad(50 ether));
        stabilityFeeTreasury.modifyParameters("surplusTransferDelay", 10 minutes);
        assertEq(stabilityFeeTreasury.expensesMultiplier(), 5 * HUNDRED);
        assertEq(stabilityFeeTreasury.treasuryCapacity(), rad(50 ether));
        assertEq(stabilityFeeTreasury.surplusTransferDelay(), 10 minutes);
    }
    function test_transferSurplusFunds_no_expenses_no_minimumFundsRequired() public {
        hevm.warp(now + 1 seconds);
        stabilityFeeTreasury.transferSurplusFunds();
        assertEq(stabilityFeeTreasury.accumulatorTag(), 0);
        assertEq(stabilityFeeTreasury.latestSurplusTransferTime(), now);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(address(alice)), rad(200 ether));
    }
    function test_transferSurplusFunds_no_expenses_with_minimumFundsRequired() public {
        stabilityFeeTreasury.modifyParameters("treasuryCapacity", rad(50 ether));
        stabilityFeeTreasury.modifyParameters("minimumFundsRequired", rad(50 ether));
        hevm.warp(now + 1 seconds);
        stabilityFeeTreasury.transferSurplusFunds();
        assertEq(stabilityFeeTreasury.accumulatorTag(), 0);
        assertEq(stabilityFeeTreasury.latestSurplusTransferTime(), now);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(50 ether));
        assertEq(safeEngine.coinBalance(address(alice)), rad(150 ether));
    }
    function test_transferSurplusFunds_no_expenses_both_internal_and_external_coins() public {
        assertEq(stabilityFeeTreasury.treasuryCapacity(), 0);
        assertEq(stabilityFeeTreasury.expensesMultiplier(), HUNDRED);
        assertEq(stabilityFeeTreasury.expensesAccumulator(), 0);
        assertEq(stabilityFeeTreasury.minimumFundsRequired(), 0);
        systemCoin.transfer(address(stabilityFeeTreasury), 1 ether);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 1 ether);
        hevm.warp(now + 1 seconds);
        stabilityFeeTreasury.transferSurplusFunds();
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(address(alice)), rad(201 ether));
    }
    function test_transferSurplusFunds_no_expenses_with_minimumFundsRequired_both_internal_and_external_coins() public {
        stabilityFeeTreasury.modifyParameters("treasuryCapacity", rad(50 ether));
        stabilityFeeTreasury.modifyParameters("minimumFundsRequired", rad(50 ether));
        assertEq(stabilityFeeTreasury.treasuryCapacity(), rad(50 ether));
        assertEq(stabilityFeeTreasury.expensesMultiplier(), HUNDRED);
        assertEq(stabilityFeeTreasury.expensesAccumulator(), 0);
        assertEq(stabilityFeeTreasury.minimumFundsRequired(), rad(50 ether));
        systemCoin.transfer(address(stabilityFeeTreasury), 1 ether);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 1 ether);
        hevm.warp(now + 1 seconds);
        stabilityFeeTreasury.transferSurplusFunds();
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(50 ether));
        assertEq(safeEngine.coinBalance(address(alice)), rad(151 ether));
    }
    function test_setTotalAllowance() public {
        stabilityFeeTreasury.setTotalAllowance(alice, 10 ether);
        (uint total, uint perBlock) = stabilityFeeTreasury.getAllowance(alice);
        assertEq(total, 10 ether);
        assertEq(perBlock, 0);
    }
    function test_setPerBlockAllowance() public {
        stabilityFeeTreasury.setPerBlockAllowance(alice, 1 ether);
        (uint total, uint perBlock) = stabilityFeeTreasury.getAllowance(alice);
        assertEq(total, 0);
        assertEq(perBlock, 1 ether);
    }
    function testFail_give_non_relied() public {
        usr.giveFunds(address(stabilityFeeTreasury), address(usr), rad(5 ether));
    }
    function testFail_take_non_relied() public {
        stabilityFeeTreasury.giveFunds(address(usr), rad(5 ether));
        usr.takeFunds(address(stabilityFeeTreasury), address(usr), rad(2 ether));
    }
    function test_give_take() public {
        assertEq(safeEngine.coinBalance(address(usr)), 0);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(200 ether));
        stabilityFeeTreasury.giveFunds(address(usr), rad(5 ether));
        assertEq(safeEngine.coinBalance(address(usr)), rad(5 ether));
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(195 ether));
        stabilityFeeTreasury.takeFunds(address(usr), rad(2 ether));
        assertEq(safeEngine.coinBalance(address(usr)), rad(3 ether));
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(197 ether));
        assertEq(stabilityFeeTreasury.expensesAccumulator(), rad(5 ether));
    }
    function testFail_give_more_debt_than_coin() public {
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(address(stabilityFeeTreasury)) + 1);

        assertEq(safeEngine.coinBalance(address(usr)), 0);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(200 ether));
        stabilityFeeTreasury.giveFunds(address(usr), rad(5 ether));
    }
    function testFail_give_more_debt_than_coin_after_join() public {
        systemCoin.transfer(address(stabilityFeeTreasury), 100 ether);
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(address(stabilityFeeTreasury)) + rad(100 ether) + 1);

        assertEq(safeEngine.coinBalance(address(usr)), 0);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(200 ether));
        stabilityFeeTreasury.giveFunds(address(usr), rad(5 ether));
    }
    function testFail_pull_above_setTotalAllowance() public {
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), rad(11 ether));
    }
    function testFail_pull_null_tkn_amount() public {
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(
          address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 0
        );
    }
    function testFail_pull_null_account() public {
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(
          address(stabilityFeeTreasury), address(0), address(stabilityFeeTreasury.systemCoin()), rad(1 ether)
        );
    }
    function testFail_pull_random_token() public {
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(0x3), rad(1 ether));
    }
    function test_pull_funds_no_block_limit() public {
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 1 ether);
        (uint total, ) = stabilityFeeTreasury.getAllowance(address(usr));
        assertEq(total, rad(9 ether));
        assertEq(systemCoin.balanceOf(address(usr)), 0);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(address(usr)), rad(1 ether));
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(199 ether));
        assertEq(stabilityFeeTreasury.expensesAccumulator(), rad(1 ether));
    }
    function test_pull_funds_to_treasury_no_block_limit() public {
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(200 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(stabilityFeeTreasury), address(stabilityFeeTreasury.systemCoin()), 1 ether);
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(200 ether));
    }
    function test_pull_funds_under_block_limit() public {
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 0.9 ether);
        (uint total, ) = stabilityFeeTreasury.getAllowance(address(usr));
        assertEq(total, rad(9.1 ether));
        assertEq(stabilityFeeTreasury.pulledPerBlock(address(usr), block.number), rad(0.9 ether));
        assertEq(systemCoin.balanceOf(address(usr)), 0);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(address(usr)), rad(0.9 ether));
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(199.1 ether));
        assertEq(stabilityFeeTreasury.expensesAccumulator(), rad(0.9 ether));
    }
    function testFail_pull_funds_when_funds_below_pull_threshold() public {
        stabilityFeeTreasury.modifyParameters("pullFundsMinThreshold", safeEngine.coinBalance(address(stabilityFeeTreasury)) + 1);
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 0.9 ether);
    }
    function testFail_pull_funds_more_debt_than_coin() public {
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(address(stabilityFeeTreasury)) + 1);
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 0.9 ether);
    }
    function testFail_pull_funds_more_debt_than_coin_post_join() public {
        systemCoin.transfer(address(stabilityFeeTreasury), 100 ether);
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(address(stabilityFeeTreasury)) + rad(100 ether) + 1);
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 0.9 ether);
    }
    function test_pull_funds_less_debt_than_coin() public {
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(address(stabilityFeeTreasury)) - rad(1 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 0.9 ether);

        (uint total, ) = stabilityFeeTreasury.getAllowance(address(usr));
        assertEq(total, rad(9.1 ether));
        assertEq(stabilityFeeTreasury.pulledPerBlock(address(usr), block.number), rad(0.9 ether));
        assertEq(systemCoin.balanceOf(address(usr)), 0);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(address(usr)), rad(0.9 ether));
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(0.1 ether));
    }
    function test_less_debt_than_coin_post_join() public {
        systemCoin.transfer(address(stabilityFeeTreasury), 100 ether);
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(address(stabilityFeeTreasury)) - rad(1 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 0.9 ether);

        (uint total, ) = stabilityFeeTreasury.getAllowance(address(usr));
        assertEq(total, rad(9.1 ether));
        assertEq(stabilityFeeTreasury.pulledPerBlock(address(usr), block.number), rad(0.9 ether));
        assertEq(systemCoin.balanceOf(address(usr)), 0);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(address(usr)), rad(0.9 ether));
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(100.1 ether));
    }
    function testFail_pull_funds_above_block_limit() public {
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(stabilityFeeTreasury.systemCoin()), 10 ether);
    }
    function testFail_transferSurplusFunds_before_surplusTransferDelay() public {
        stabilityFeeTreasury.modifyParameters("surplusTransferDelay", 10 minutes);
        hevm.warp(now + 9 minutes);
        stabilityFeeTreasury.transferSurplusFunds();
    }
    function test_transferSurplusFunds_after_expenses() public {
        address charlie = address(0x12345);
        stabilityFeeTreasury.modifyParameters("extraSurplusReceiver", charlie);

        stabilityFeeTreasury.modifyParameters("surplusTransferDelay", 10 minutes);
        stabilityFeeTreasury.giveFunds(alice, rad(40 ether));
        hevm.warp(now + 10 minutes);
        stabilityFeeTreasury.transferSurplusFunds();
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(40 ether));
        assertEq(safeEngine.coinBalance(address(alice)), rad(40 ether));
        assertEq(safeEngine.coinBalance(address(charlie)), rad(120 ether));
        hevm.warp(now + 10 minutes);
        stabilityFeeTreasury.transferSurplusFunds();
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(address(alice)), rad(40 ether));
        assertEq(safeEngine.coinBalance(address(charlie)), rad(160 ether));
    }
    function test_transferSurplusFunds_after_expenses_with_treasuryCapacity_and_minimumFundsRequired() public {
        address charlie = address(0x12345);
        stabilityFeeTreasury.modifyParameters("extraSurplusReceiver", charlie);

        stabilityFeeTreasury.modifyParameters("treasuryCapacity", rad(30 ether));
        stabilityFeeTreasury.modifyParameters("minimumFundsRequired", rad(10 ether));
        stabilityFeeTreasury.modifyParameters("surplusTransferDelay", 10 minutes);
        stabilityFeeTreasury.giveFunds(alice, rad(40 ether));
        hevm.warp(now + 10 minutes);
        stabilityFeeTreasury.transferSurplusFunds();
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(40 ether));
        assertEq(safeEngine.coinBalance(address(alice)), rad(40 ether));
        assertEq(safeEngine.coinBalance(address(charlie)), rad(120 ether));
        hevm.warp(now + 10 minutes);
        stabilityFeeTreasury.transferSurplusFunds();
        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(10 ether));
        assertEq(safeEngine.coinBalance(address(alice)), rad(40 ether));
        assertEq(safeEngine.coinBalance(address(charlie)), rad(150 ether));
    }
    function testFail_transferSurplusFunds_more_debt_than_coin() public {
        address charlie = address(0x12345);
        stabilityFeeTreasury.modifyParameters("extraSurplusReceiver", charlie);

        stabilityFeeTreasury.modifyParameters("treasuryCapacity", rad(30 ether));
        stabilityFeeTreasury.modifyParameters("minimumFundsRequired", rad(10 ether));
        stabilityFeeTreasury.modifyParameters("surplusTransferDelay", 10 minutes);

        stabilityFeeTreasury.giveFunds(alice, rad(40 ether));
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), rad(161 ether));

        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(160 ether));
        assertEq(safeEngine.debtBalance(address(stabilityFeeTreasury)), rad(161 ether));

        hevm.warp(now + 10 minutes);
        stabilityFeeTreasury.transferSurplusFunds();
    }
    function test_transferSurplusFunds_less_debt_than_coin() public {
        address charlie = address(0x12345);
        stabilityFeeTreasury.modifyParameters("extraSurplusReceiver", charlie);

        stabilityFeeTreasury.modifyParameters("treasuryCapacity", rad(30 ether));
        stabilityFeeTreasury.modifyParameters("minimumFundsRequired", rad(10 ether));
        stabilityFeeTreasury.modifyParameters("surplusTransferDelay", 10 minutes);

        stabilityFeeTreasury.giveFunds(alice, rad(40 ether));
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), rad(50 ether));

        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(160 ether));
        assertEq(safeEngine.debtBalance(address(stabilityFeeTreasury)), rad(50 ether));

        hevm.warp(now + 10 minutes);
        stabilityFeeTreasury.transferSurplusFunds();

        assertEq(safeEngine.coinBalance(address(stabilityFeeTreasury)), rad(40 ether));
        assertEq(safeEngine.coinBalance(address(alice)), rad(40 ether));
        assertEq(safeEngine.coinBalance(address(charlie)), rad(70 ether));
    }
}
