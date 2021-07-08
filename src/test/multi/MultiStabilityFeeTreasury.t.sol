/// MultiStabilityFeeTreasury.t.sol

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

import {Coin} from '../../shared/Coin.sol';
import {MultiSAFEEngine} from '../../multi/MultiSAFEEngine.sol';
import {MultiStabilityFeeTreasury} from '../../multi/MultiStabilityFeeTreasury.sol';
import {MultiCoinJoin} from '../../shared/BasicTokenAdapters.sol';

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract Usr {
    function approveSAFEModification(bytes32 coinName, address safeEngine, address lad) external {
        MultiSAFEEngine(safeEngine).approveSAFEModification(coinName, lad);
    }
    function giveFunds(bytes32 coinName, address stabilityFeeTreasury, address lad, uint rad) external {
        MultiStabilityFeeTreasury(stabilityFeeTreasury).giveFunds(coinName, lad, rad);
    }
    function takeFunds(bytes32 coinName, address stabilityFeeTreasury, address lad, uint rad) external {
        MultiStabilityFeeTreasury(stabilityFeeTreasury).takeFunds(coinName, lad, rad);
    }
    function pullFunds(bytes32 coinName, address stabilityFeeTreasury, address gal, address tkn, uint wad) external {
        return MultiStabilityFeeTreasury(stabilityFeeTreasury).pullFunds(coinName, gal, tkn, wad);
    }
    function approve(address systemCoin, address gal) external {
        Coin(systemCoin).approve(gal, uint(-1));
    }
}

contract SingleMultiStabilityFeeTreasuryTest is DSTest {
    Hevm hevm;

    MultiSAFEEngine safeEngine;
    MultiStabilityFeeTreasury stabilityFeeTreasury;

    Coin systemCoin;
    Coin secondSystemCoin;

    MultiCoinJoin systemCoinJoinA;
    MultiCoinJoin systemCoinJoinB;

    Usr usr;

    address alice = address(0x1);
    address bob = address(0x2);

    bytes32 coinName = "MAI";
    bytes32 secondCoinName = "BAI";

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

        safeEngine  = new MultiSAFEEngine();
        safeEngine.initializeCoin(coinName, uint(-1));
        safeEngine.initializeCoin(secondCoinName, uint(-1));

        systemCoin  = new Coin("Coin", "COIN", 99);
        secondSystemCoin = new Coin("Coin", "COIN", 99);

        systemCoinJoinA = new MultiCoinJoin(coinName, address(safeEngine), address(systemCoin));
        systemCoinJoinB = new MultiCoinJoin(secondCoinName, address(safeEngine), address(secondSystemCoin));

        stabilityFeeTreasury = new MultiStabilityFeeTreasury(address(safeEngine));
        stabilityFeeTreasury.initializeCoin(
          coinName,
          address(systemCoinJoinA),
          alice,
          HUNDRED,
          uint(-1),
          1,
          1,
          1
        );
        stabilityFeeTreasury.initializeCoin(
          secondCoinName,
          address(systemCoinJoinB),
          alice,
          HUNDRED,
          uint(-1),
          1,
          1,
          1
        );

        systemCoin.addAuthorization(address(systemCoinJoinA));
        stabilityFeeTreasury.addAuthorization(coinName, address(systemCoinJoinA));

        secondSystemCoin.addAuthorization(address(systemCoinJoinB));
        stabilityFeeTreasury.addAuthorization(secondCoinName, address(systemCoinJoinB));

        safeEngine.createUnbackedDebt(coinName, bob, address(stabilityFeeTreasury), rad(200 ether));
        safeEngine.createUnbackedDebt(coinName, bob, address(this), rad(100 ether));

        safeEngine.createUnbackedDebt(secondCoinName, bob, address(stabilityFeeTreasury), rad(200 ether));
        safeEngine.createUnbackedDebt(secondCoinName, bob, address(this), rad(100 ether));

        safeEngine.approveSAFEModification(coinName, address(systemCoinJoinA));
        safeEngine.approveSAFEModification(secondCoinName, address(systemCoinJoinB));

        systemCoinJoinA.exit(address(this), 100 ether);
        systemCoinJoinB.exit(address(this), 100 ether);

        usr.approveSAFEModification(coinName, address(safeEngine), address(stabilityFeeTreasury));
        usr.approveSAFEModification(secondCoinName, address(safeEngine), address(stabilityFeeTreasury));
    }

    function test_setup() public {
        assertEq(stabilityFeeTreasury.surplusTransferDelay(coinName), 1);
        assertEq(address(stabilityFeeTreasury.safeEngine()), address(safeEngine));
        assertEq(address(stabilityFeeTreasury.extraSurplusReceiver(coinName)), alice);
        assertEq(stabilityFeeTreasury.latestSurplusTransferTime(coinName), now);
        assertEq(stabilityFeeTreasury.expensesMultiplier(coinName), HUNDRED);
        assertEq(systemCoin.balanceOf(address(this)), 100 ether);
        assertEq(safeEngine.coinBalance(coinName, address(alice)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(200 ether));

        assertEq(stabilityFeeTreasury.surplusTransferDelay(secondCoinName), 1);
        assertEq(address(stabilityFeeTreasury.extraSurplusReceiver(secondCoinName)), alice);
        assertEq(stabilityFeeTreasury.latestSurplusTransferTime(secondCoinName), now);
        assertEq(stabilityFeeTreasury.expensesMultiplier(secondCoinName), HUNDRED);
        assertEq(secondSystemCoin.balanceOf(address(this)), 100 ether);
        assertEq(safeEngine.coinBalance(secondCoinName, address(alice)), 0);
        assertEq(safeEngine.coinBalance(secondCoinName, address(stabilityFeeTreasury)), rad(200 ether));
    }
    function test_modify_extra_surplus_receiver() public {
        stabilityFeeTreasury.modifyParameters(coinName, "extraSurplusReceiver", bob);
        stabilityFeeTreasury.modifyParameters(secondCoinName, "extraSurplusReceiver", bob);
        assertEq(stabilityFeeTreasury.extraSurplusReceiver(coinName), bob);
        assertEq(stabilityFeeTreasury.extraSurplusReceiver(secondCoinName), bob);
    }
    function test_modify_params() public {
        stabilityFeeTreasury.modifyParameters(coinName, "expensesMultiplier", 5 * HUNDRED);
        stabilityFeeTreasury.modifyParameters(coinName, "treasuryCapacity", rad(50 ether));
        stabilityFeeTreasury.modifyParameters(coinName, "surplusTransferDelay", 10 minutes);

        stabilityFeeTreasury.modifyParameters(secondCoinName, "expensesMultiplier", 5 * HUNDRED);
        stabilityFeeTreasury.modifyParameters(secondCoinName, "treasuryCapacity", rad(50 ether));
        stabilityFeeTreasury.modifyParameters(secondCoinName, "surplusTransferDelay", 10 minutes);

        assertEq(stabilityFeeTreasury.expensesMultiplier(coinName), 5 * HUNDRED);
        assertEq(stabilityFeeTreasury.treasuryCapacity(coinName), rad(50 ether));
        assertEq(stabilityFeeTreasury.surplusTransferDelay(coinName), 10 minutes);

        assertEq(stabilityFeeTreasury.expensesMultiplier(secondCoinName), 5 * HUNDRED);
        assertEq(stabilityFeeTreasury.treasuryCapacity(secondCoinName), rad(50 ether));
        assertEq(stabilityFeeTreasury.surplusTransferDelay(secondCoinName), 10 minutes);
    }
    function test_transferSurplusFunds_no_expenses_no_minimumFundsRequired() public {
        hevm.warp(now + 1 seconds);
        stabilityFeeTreasury.transferSurplusFunds(coinName);
        stabilityFeeTreasury.transferSurplusFunds(secondCoinName);

        assertEq(stabilityFeeTreasury.accumulatorTag(coinName), 0);
        assertEq(stabilityFeeTreasury.latestSurplusTransferTime(coinName), now);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), 1);
        assertEq(safeEngine.coinBalance(coinName, address(alice)), rad(200 ether) - 1);

        assertEq(stabilityFeeTreasury.accumulatorTag(secondCoinName), 0);
        assertEq(stabilityFeeTreasury.latestSurplusTransferTime(secondCoinName), now);
        assertEq(safeEngine.coinBalance(secondCoinName, address(stabilityFeeTreasury)), 1);
        assertEq(safeEngine.coinBalance(secondCoinName, address(alice)), rad(200 ether) - 1);
    }
    function test_transferSurplusFunds_no_expenses_with_minimumFundsRequired() public {
        stabilityFeeTreasury.modifyParameters(coinName, "treasuryCapacity", rad(50 ether));
        stabilityFeeTreasury.modifyParameters(coinName, "minimumFundsRequired", rad(50 ether));

        stabilityFeeTreasury.modifyParameters(secondCoinName, "treasuryCapacity", rad(50 ether));
        stabilityFeeTreasury.modifyParameters(secondCoinName, "minimumFundsRequired", rad(50 ether));

        hevm.warp(now + 1 seconds);

        stabilityFeeTreasury.transferSurplusFunds(coinName);
        stabilityFeeTreasury.transferSurplusFunds(secondCoinName);

        assertEq(stabilityFeeTreasury.accumulatorTag(coinName), 0);
        assertEq(stabilityFeeTreasury.latestSurplusTransferTime(coinName), now);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(50 ether));
        assertEq(safeEngine.coinBalance(coinName, address(alice)), rad(150 ether));

        assertEq(stabilityFeeTreasury.accumulatorTag(secondCoinName), 0);
        assertEq(stabilityFeeTreasury.latestSurplusTransferTime(secondCoinName), now);
        assertEq(safeEngine.coinBalance(secondCoinName, address(stabilityFeeTreasury)), rad(50 ether));
        assertEq(safeEngine.coinBalance(secondCoinName, address(alice)), rad(150 ether));
    }
    function test_transferSurplusFunds_no_expenses_both_internal_and_external_coins() public {
        assertEq(stabilityFeeTreasury.treasuryCapacity(coinName), uint(-1));
        assertEq(stabilityFeeTreasury.expensesMultiplier(coinName), HUNDRED);
        assertEq(stabilityFeeTreasury.expensesAccumulator(coinName), 0);
        assertEq(stabilityFeeTreasury.minimumFundsRequired(coinName), 1);

        assertEq(stabilityFeeTreasury.treasuryCapacity(secondCoinName), uint(-1));
        assertEq(stabilityFeeTreasury.expensesMultiplier(secondCoinName), HUNDRED);
        assertEq(stabilityFeeTreasury.expensesAccumulator(secondCoinName), 0);
        assertEq(stabilityFeeTreasury.minimumFundsRequired(secondCoinName), 1);

        systemCoin.transfer(address(stabilityFeeTreasury), 1 ether);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 1 ether);

        secondSystemCoin.transfer(address(stabilityFeeTreasury), 1 ether);
        assertEq(secondSystemCoin.balanceOf(address(stabilityFeeTreasury)), 1 ether);

        hevm.warp(now + 1 seconds);

        stabilityFeeTreasury.transferSurplusFunds(coinName);
        stabilityFeeTreasury.transferSurplusFunds(secondCoinName);

        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), 1);
        assertEq(safeEngine.coinBalance(coinName, address(alice)), rad(201 ether) - 1);

        assertEq(secondSystemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(secondCoinName, address(stabilityFeeTreasury)), 1);
        assertEq(safeEngine.coinBalance(secondCoinName, address(alice)), rad(201 ether) - 1);
    }
    function test_transferSurplusFunds_no_expenses_with_minimumFundsRequired_both_internal_and_external_coins() public {
        stabilityFeeTreasury.modifyParameters(coinName, "treasuryCapacity", rad(50 ether));
        stabilityFeeTreasury.modifyParameters(coinName, "minimumFundsRequired", rad(50 ether));

        stabilityFeeTreasury.modifyParameters(secondCoinName, "treasuryCapacity", rad(50 ether));
        stabilityFeeTreasury.modifyParameters(secondCoinName, "minimumFundsRequired", rad(50 ether));

        assertEq(stabilityFeeTreasury.treasuryCapacity(coinName), rad(50 ether));
        assertEq(stabilityFeeTreasury.expensesMultiplier(coinName), HUNDRED);
        assertEq(stabilityFeeTreasury.expensesAccumulator(coinName), 0);
        assertEq(stabilityFeeTreasury.minimumFundsRequired(coinName), rad(50 ether));

        assertEq(stabilityFeeTreasury.treasuryCapacity(secondCoinName), rad(50 ether));
        assertEq(stabilityFeeTreasury.expensesMultiplier(secondCoinName), HUNDRED);
        assertEq(stabilityFeeTreasury.expensesAccumulator(secondCoinName), 0);
        assertEq(stabilityFeeTreasury.minimumFundsRequired(secondCoinName), rad(50 ether));

        systemCoin.transfer(address(stabilityFeeTreasury), 1 ether);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 1 ether);

        secondSystemCoin.transfer(address(stabilityFeeTreasury), 1 ether);
        assertEq(secondSystemCoin.balanceOf(address(stabilityFeeTreasury)), 1 ether);

        hevm.warp(now + 1 seconds);

        stabilityFeeTreasury.transferSurplusFunds(coinName);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(50 ether));
        assertEq(safeEngine.coinBalance(coinName, address(alice)), rad(151 ether));

        stabilityFeeTreasury.transferSurplusFunds(secondCoinName);
        assertEq(secondSystemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(secondCoinName, address(stabilityFeeTreasury)), rad(50 ether));
        assertEq(safeEngine.coinBalance(secondCoinName, address(alice)), rad(151 ether));
    }
    function test_setTotalAllowance() public {
        stabilityFeeTreasury.setTotalAllowance(coinName, alice, 10 ether);
        stabilityFeeTreasury.setTotalAllowance(secondCoinName, alice, 10 ether);

        (uint total, uint perBlock) = stabilityFeeTreasury.getAllowance(coinName, alice);
        assertEq(total, 10 ether);
        assertEq(perBlock, 0);

        (total, perBlock) = stabilityFeeTreasury.getAllowance(secondCoinName, alice);
        assertEq(total, 10 ether);
        assertEq(perBlock, 0);
    }
    function test_setPerBlockAllowance() public {
        stabilityFeeTreasury.setPerBlockAllowance(coinName, alice, 1 ether);
        stabilityFeeTreasury.setPerBlockAllowance(secondCoinName, alice, 1 ether);

        (uint total, uint perBlock) = stabilityFeeTreasury.getAllowance(coinName, alice);
        assertEq(total, 0);
        assertEq(perBlock, 1 ether);

        (total, perBlock) = stabilityFeeTreasury.getAllowance(secondCoinName, alice);
        assertEq(total, 0);
        assertEq(perBlock, 1 ether);
    }
    function testFail_give_non_relied_coin() public {
        usr.giveFunds(coinName, address(stabilityFeeTreasury), address(usr), rad(5 ether));
    }
    function testFail_give_non_relied_second_coin() public {
        usr.giveFunds(secondCoinName, address(stabilityFeeTreasury), address(usr), rad(5 ether));
    }
    function testFail_take_non_relied_coin() public {
        stabilityFeeTreasury.giveFunds(coinName, address(usr), rad(5 ether));
        usr.takeFunds(coinName, address(stabilityFeeTreasury), address(usr), rad(2 ether));
    }
    function testFail_take_non_relied_second_coin() public {
        stabilityFeeTreasury.giveFunds(secondCoinName, address(usr), rad(5 ether));
        usr.takeFunds(secondCoinName, address(stabilityFeeTreasury), address(usr), rad(2 ether));
    }
    function test_give_take() public {
        assertEq(safeEngine.coinBalance(coinName, address(usr)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(200 ether));

        assertEq(safeEngine.coinBalance(secondCoinName, address(usr)), 0);
        assertEq(safeEngine.coinBalance(secondCoinName, address(stabilityFeeTreasury)), rad(200 ether));

        stabilityFeeTreasury.giveFunds(coinName, address(usr), rad(5 ether));
        assertEq(safeEngine.coinBalance(coinName, address(usr)), rad(5 ether));
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(195 ether));

        stabilityFeeTreasury.giveFunds(secondCoinName, address(usr), rad(5 ether));
        assertEq(safeEngine.coinBalance(secondCoinName, address(usr)), rad(5 ether));
        assertEq(safeEngine.coinBalance(secondCoinName, address(stabilityFeeTreasury)), rad(195 ether));

        stabilityFeeTreasury.takeFunds(coinName, address(usr), rad(2 ether));
        assertEq(safeEngine.coinBalance(coinName, address(usr)), rad(3 ether));
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(197 ether));
        assertEq(stabilityFeeTreasury.expensesAccumulator(coinName), rad(5 ether));

        stabilityFeeTreasury.takeFunds(secondCoinName, address(usr), rad(2 ether));
        assertEq(safeEngine.coinBalance(secondCoinName, address(usr)), rad(3 ether));
        assertEq(safeEngine.coinBalance(secondCoinName, address(stabilityFeeTreasury)), rad(197 ether));
        assertEq(stabilityFeeTreasury.expensesAccumulator(secondCoinName), rad(5 ether));
    }
    function testFail_give_more_debt_than_coin() public {
        safeEngine.createUnbackedDebt(coinName, address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)) + 1);

        assertEq(safeEngine.coinBalance(coinName, address(usr)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(200 ether));
        stabilityFeeTreasury.giveFunds(coinName, address(usr), rad(5 ether));
    }
    function testFail_give_more_debt_than_second_coin() public {
        safeEngine.createUnbackedDebt(secondCoinName, address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(secondCoinName, address(stabilityFeeTreasury)) + 1);

        assertEq(safeEngine.coinBalance(secondCoinName, address(usr)), 0);
        assertEq(safeEngine.coinBalance(secondCoinName, address(stabilityFeeTreasury)), rad(200 ether));
        stabilityFeeTreasury.giveFunds(secondCoinName, address(usr), rad(5 ether));
    }
    function testFail_give_more_debt_than_coin_after_join() public {
        systemCoin.transfer(address(stabilityFeeTreasury), 100 ether);
        safeEngine.createUnbackedDebt(coinName, address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)) + rad(100 ether) + 1);

        assertEq(safeEngine.coinBalance(coinName, address(usr)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(200 ether));
        stabilityFeeTreasury.giveFunds(coinName, address(usr), rad(5 ether));
    }
    function testFail_give_more_debt_than_second_coin_after_join() public {
        secondSystemCoin.transfer(address(stabilityFeeTreasury), 100 ether);
        safeEngine.createUnbackedDebt(secondCoinName, address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(secondCoinName, address(stabilityFeeTreasury)) + rad(100 ether) + 1);

        assertEq(safeEngine.coinBalance(secondCoinName, address(usr)), 0);
        assertEq(safeEngine.coinBalance(secondCoinName, address(stabilityFeeTreasury)), rad(200 ether));
        stabilityFeeTreasury.giveFunds(secondCoinName, address(usr), rad(5 ether));
    }
    function testFail_pull_above_setTotalAllowance_coin() public {
        stabilityFeeTreasury.setTotalAllowance(coinName, address(usr), rad(10 ether));
        usr.pullFunds(coinName, address(stabilityFeeTreasury), address(usr), address(systemCoin), rad(11 ether));
    }
    function testFail_pull_above_setTotalAllowance_second_coin() public {
        stabilityFeeTreasury.setTotalAllowance(secondCoinName, address(usr), rad(10 ether));
        usr.pullFunds(secondCoinName, address(stabilityFeeTreasury), address(usr), address(systemCoin), rad(11 ether));
    }
    function testFail_pull_null_tkn_amount() public {
        stabilityFeeTreasury.setTotalAllowance(coinName, address(usr), rad(10 ether));
        usr.pullFunds(
          coinName, address(stabilityFeeTreasury), address(usr), address(systemCoin), 0
        );
    }
    function testFail_pull_null_account() public {
        stabilityFeeTreasury.setTotalAllowance(coinName, address(usr), rad(10 ether));
        usr.pullFunds(
          coinName, address(stabilityFeeTreasury), address(0), address(systemCoin), rad(1 ether)
        );
    }
    function testFail_pull_random_token() public {
        stabilityFeeTreasury.setTotalAllowance(coinName, address(usr), rad(10 ether));
        usr.pullFunds(coinName, address(stabilityFeeTreasury), address(usr), address(0x3), rad(1 ether));
    }
    function test_pull_funds_no_block_limit() public {
        stabilityFeeTreasury.setTotalAllowance(coinName, address(usr), rad(10 ether));
        stabilityFeeTreasury.setTotalAllowance(secondCoinName, address(usr), rad(10 ether));

        usr.pullFunds(coinName, address(stabilityFeeTreasury), address(usr), address(systemCoin), 1 ether);
        usr.pullFunds(secondCoinName, address(stabilityFeeTreasury), address(usr), address(secondSystemCoin), 1 ether);

        (uint total, ) = stabilityFeeTreasury.getAllowance(coinName, address(usr));
        assertEq(total, rad(9 ether));
        assertEq(systemCoin.balanceOf(address(usr)), 0);
        assertEq(systemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(coinName, address(usr)), rad(1 ether));
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(199 ether));
        assertEq(stabilityFeeTreasury.expensesAccumulator(coinName), rad(1 ether));

        (total, ) = stabilityFeeTreasury.getAllowance(secondCoinName, address(usr));
        assertEq(total, rad(9 ether));
        assertEq(secondSystemCoin.balanceOf(address(usr)), 0);
        assertEq(secondSystemCoin.balanceOf(address(stabilityFeeTreasury)), 0);
        assertEq(safeEngine.coinBalance(secondCoinName, address(usr)), rad(1 ether));
        assertEq(safeEngine.coinBalance(secondCoinName, address(stabilityFeeTreasury)), rad(199 ether));
        assertEq(stabilityFeeTreasury.expensesAccumulator(secondCoinName), rad(1 ether));
    }
    function test_pull_funds_to_treasury_no_block_limit() public {
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(200 ether));
        assertEq(safeEngine.coinBalance(secondCoinName, address(stabilityFeeTreasury)), rad(200 ether));

        stabilityFeeTreasury.setTotalAllowance(coinName, address(usr), rad(10 ether));
        usr.pullFunds(coinName, address(stabilityFeeTreasury), address(stabilityFeeTreasury), address(systemCoin), 1 ether);
        assertEq(safeEngine.coinBalance(coinName, address(stabilityFeeTreasury)), rad(200 ether));

        stabilityFeeTreasury.setTotalAllowance(secondCoinName, address(usr), rad(10 ether));
        usr.pullFunds(secondCoinName, address(stabilityFeeTreasury), address(stabilityFeeTreasury), address(secondSystemCoin), 1 ether);
        assertEq(safeEngine.coinBalance(secondCoinName, address(stabilityFeeTreasury)), rad(200 ether));
    }


    /* function test_pull_funds_under_block_limit() public {
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(systemCoin), 0.9 ether);
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
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(systemCoin), 0.9 ether);
    }
    function testFail_pull_funds_more_debt_than_coin() public {
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(address(stabilityFeeTreasury)) + 1);
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(systemCoin), 0.9 ether);
    }
    function testFail_pull_funds_more_debt_than_coin_post_join() public {
        systemCoin.transfer(address(stabilityFeeTreasury), 100 ether);
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(address(stabilityFeeTreasury)) + rad(100 ether) + 1);
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(systemCoin), 0.9 ether);
    }
    function test_pull_funds_less_debt_than_coin() public {
        stabilityFeeTreasury.setPerBlockAllowance(address(usr), rad(1 ether));
        stabilityFeeTreasury.setTotalAllowance(address(usr), rad(10 ether));
        safeEngine.createUnbackedDebt(address(stabilityFeeTreasury), address(this), safeEngine.coinBalance(address(stabilityFeeTreasury)) - rad(1 ether));
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(systemCoin), 0.9 ether);

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
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(systemCoin), 0.9 ether);

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
        usr.pullFunds(address(stabilityFeeTreasury), address(usr), address(systemCoin), 10 ether);
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
    } */
}
