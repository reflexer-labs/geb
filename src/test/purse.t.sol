// /// purse.t.sol -- tests for purse.sol
//
// // Copyright (C) 2015-2020  DappHub, LLC
// // Copyright (C) 2020       Stefan C. Ionescu <stefanionescu@protonmail.com>
//
// // This program is free software: you can redistribute it and/or modify
// // it under the terms of the GNU General Public License as published by
// // the Free Software Foundation, either version 3 of the License, or
// // (at your option) any later version.
//
// // This program is distributed in the hope that it will be useful,
// // but WITHOUT ANY WARRANTY; without even the implied warranty of
// // MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// // GNU General Public License for more details.
//
// // You should have received a copy of the GNU General Public License
// // along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// pragma solidity ^0.5.15;
//
// import "ds-test/test.sol";
//
// import {Coin}  from '../coin.sol';
// import {Vat}  from '../vat.sol';
// import {Purse}  from '../purse.sol';
// import {CoinJoin} from '../join.sol';
//
// contract Hevm {
//     function warp(uint256) public;
// }
//
// contract Usr {
//     function hope(address vat, address lad) external {
//         Vat(vat).hope(lad);
//     }
//     function give(address purse, bytes32 form, address lad, uint val) external {
//         Purse(purse).give(form, lad, val);
//     }
//     function take(address purse, bytes32 form, address lad, uint val) external {
//         Purse(purse).take(form, lad, val);
//     }
//     function pull(address purse, address gal, address tkn, uint val) external returns (bool) {
//         return Purse(purse).pull(gal, tkn, val);
//     }
//     function approve(address coin, address gal) external {
//         Coin(coin).approve(gal, uint(-1));
//     }
// }
//
// contract PurseTest is DSTest {
//     Hevm hevm;
//
//     Vat   vat;
//     Purse purse;
//
//     Coin coin;
//     CoinJoin coinA;
//
//     Usr usr;
//
//     address alice = address(0x1);
//     address bob = address(0x2);
//
//     uint constant WAD = 10 ** 18;
//     uint constant RAY = 10 ** 27;
//
//     function ray(uint wad) internal pure returns (uint) {
//         return wad * 10 ** 9;
//     }
//     function rad(uint wad) internal pure returns (uint) {
//         return wad * RAY;
//     }
//
//     function setUp() public {
//         hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
//         hevm.warp(604411200);
//
//         usr  = new Usr();
//
//         vat  = new Vat();
//         coin = new Coin("Coin", "COIN", 99);
//         coinA = new CoinJoin(address(vat), address(coin));
//         purse = new Purse(address(vat), alice, address(coinA), 0);
//
//         coin.rely(address(coinA));
//         purse.rely(address(coinA));
//
//         vat.suck(bob, address(purse), rad(100 ether));
//         vat.suck(bob, address(this), rad(100 ether));
//
//         vat.hope(address(coinA));
//         coinA.exit(address(this), 100 ether);
//
//         usr.hope(address(vat), address(purse));
//     }
//
//     function test_setup() public {
//         assertEq(purse.gap(), 0);
//         assertEq(address(purse.vat()), address(vat));
//         assertEq(address(purse.vow()), alice);
//         assertEq(purse.rho(), now);
//         assertEq(purse.times(), WAD);
//         assertEq(coin.balanceOf(address(this)), 100 ether);
//         assertEq(vat.good(address(alice)), 0);
//         assertEq(vat.good(address(purse)), rad(100 ether));
//     }
//     function test_file_vow() public {
//         purse.file("vow", bob);
//         assertEq(purse.vow(), bob);
//     }
//     function test_file_params() public {
//         purse.file("times", 5 * WAD);
//         purse.file("full", rad(50 ether));
//         purse.file("gap", 10 minutes);
//         assertEq(purse.times(), 5 * WAD);
//         assertEq(purse.full(), rad(50 ether));
//         assertEq(purse.gap(), 10 minutes);
//     }
//     function test_keep_no_expenses_no_min() public {
//         hevm.warp(now + 1 seconds);
//         purse.keep();
//         assertEq(purse.pin(), 0);
//         assertEq(purse.rho(), now);
//         assertEq(vat.good(address(purse)), 0);
//         assertEq(vat.good(address(alice)), rad(100 ether));
//     }
//     function test_keep_no_expenses_with_min() public {
//         purse.file("min", rad(50 ether));
//         hevm.warp(now + 1 seconds);
//         purse.keep();
//         assertEq(purse.pin(), 0);
//         assertEq(purse.rho(), now);
//         assertEq(vat.good(address(purse)), rad(50 ether));
//         assertEq(vat.good(address(alice)), rad(50 ether));
//     }
//     function test_keep_no_expenses_both_good_and_coins() public {
//         assertEq(purse.full(), 0);
//         assertEq(purse.times(), WAD);
//         assertEq(purse.cron(), 0);
//         assertEq(purse.min(), 0);
//         coin.transfer(address(purse), 1 ether);
//         assertEq(coin.balanceOf(address(purse)), 1 ether);
//         hevm.warp(now + 1 seconds);
//         purse.keep();
//         assertEq(coin.balanceOf(address(purse)), 0);
//         assertEq(vat.good(address(purse)), 0);
//         assertEq(vat.good(address(alice)), rad(101 ether));
//     }
//     function test_keep_no_expenses_with_min_both_good_and_coins() public {
//         purse.file("min", rad(50 ether));
//         assertEq(purse.full(), 0);
//         assertEq(purse.times(), WAD);
//         assertEq(purse.cron(), 0);
//         assertEq(purse.min(), rad(50 ether));
//         coin.transfer(address(purse), 1 ether);
//         assertEq(coin.balanceOf(address(purse)), 1 ether);
//         hevm.warp(now + 1 seconds);
//         purse.keep();
//         assertEq(coin.balanceOf(address(purse)), 0);
//         assertEq(vat.good(address(purse)), rad(50 ether));
//         assertEq(vat.good(address(alice)), rad(51 ether));
//     }
//     function test_allow() public {
//         purse.allow(alice, 10 ether);
//         assertEq(purse.allowance(alice), 10 ether);
//     }
//     function testFail_give_non_relied() public {
//         usr.give(address(purse), bytes32("INTERNAL"), address(usr), rad(5 ether));
//     }
//     function testFail_take_non_relied() public {
//         purse.give(bytes32("INTERNAL"), address(usr), rad(5 ether));
//         usr.take(address(purse), bytes32("INTERNAL"), address(usr), rad(2 ether));
//     }
//     function test_give_take_internal() public {
//         assertEq(vat.good(address(usr)), 0);
//         assertEq(vat.good(address(purse)), rad(100 ether));
//         purse.give(bytes32("INTERNAL"), address(usr), rad(5 ether));
//         assertEq(vat.good(address(usr)), rad(5 ether));
//         assertEq(vat.good(address(purse)), rad(95 ether));
//         purse.take(bytes32("INTERNAL"), address(usr), rad(2 ether));
//         assertEq(vat.good(address(usr)), rad(3 ether));
//         assertEq(vat.good(address(purse)), rad(97 ether));
//         assertEq(purse.cron(), rad(5 ether));
//     }
//     function test_give_take_external() public {
//         assertEq(vat.good(address(usr)), 0);
//         assertEq(vat.good(address(purse)), rad(100 ether));
//         purse.give(bytes32("EXTERNAL"), address(usr), 5 ether);
//         assertEq(coin.balanceOf(address(usr)), 5 ether);
//         assertEq(coin.balanceOf(address(purse)), 95 ether);
//         assertEq(vat.good(address(purse)), 0);
//         usr.approve(address(coin), address(purse));
//         purse.take(bytes32("EXTERNAL"), address(usr), 2 ether);
//         assertEq(coin.balanceOf(address(usr)), 3 ether);
//         assertEq(coin.balanceOf(address(purse)), 97 ether);
//         assertEq(purse.cron(), rad(5 ether));
//     }
//     function test_pull_above_allowance() public {
//         purse.allow(address(usr), rad(10 ether));
//         bool ok = usr.pull(address(purse), address(usr), address(purse.coin()), rad(11 ether));
//         assertTrue(!ok);
//         assertEq(purse.allowance(address(usr)), rad(10 ether));
//         assertEq(vat.good(address(usr)), 0);
//         assertEq(vat.good(address(purse)), rad(100 ether));
//     }
//     function test_pull_null_val() public {
//         purse.allow(address(usr), rad(10 ether));
//         bool ok = usr.pull(address(purse), address(usr), address(purse.coin()), 0);
//         assertTrue(!ok);
//         assertEq(purse.allowance(address(usr)), rad(10 ether));
//         assertEq(vat.good(address(usr)), 0);
//         assertEq(vat.good(address(purse)), rad(100 ether));
//     }
//     function test_pull_null_gal() public {
//         purse.allow(address(usr), rad(10 ether));
//         bool ok = usr.pull(address(purse), address(0), address(purse.coin()), rad(1 ether));
//         assertTrue(!ok);
//         assertEq(purse.allowance(address(usr)), rad(10 ether));
//         assertEq(vat.good(address(usr)), 0);
//         assertEq(vat.good(address(purse)), rad(100 ether));
//     }
//     function test_pull_random_tkn() public {
//         purse.allow(address(usr), rad(10 ether));
//         bool ok = usr.pull(address(purse), address(usr), address(0x3), rad(1 ether));
//         assertTrue(!ok);
//         assertEq(purse.allowance(address(usr)), rad(10 ether));
//         assertEq(vat.good(address(usr)), 0);
//         assertEq(vat.good(address(purse)), rad(100 ether));
//     }
//     function test_pull() public {
//         purse.allow(address(usr), 10 ether);
//         bool ok = usr.pull(address(purse), address(usr), address(purse.coin()), 1 ether);
//         assertTrue(ok);
//         assertEq(purse.allowance(address(usr)), 9 ether);
//         assertEq(coin.balanceOf(address(usr)), 1 ether);
//         assertEq(coin.balanceOf(address(purse)), 99 ether);
//         assertEq(vat.good(address(purse)), 0);
//         assertEq(purse.cron(), rad(1 ether));
//     }
//     function testFail_keep_before_gap() public {
//         purse.file("gap", 10 minutes);
//         hevm.warp(now + 9 minutes);
//         purse.keep();
//     }
//     function test_keep_after_expenses() public {
//         purse.file("gap", 10 minutes);
//         purse.give(bytes32("INTERNAL"), alice, rad(40 ether));
//         hevm.warp(now + 10 minutes);
//         purse.keep();
//         assertEq(vat.good(address(purse)), rad(40 ether));
//         assertEq(vat.good(address(alice)), rad(60 ether));
//         hevm.warp(now + 10 minutes);
//         purse.keep();
//         assertEq(vat.good(address(purse)), 0);
//         assertEq(vat.good(address(alice)), rad(100 ether));
//     }
//     function test_keep_after_expenses_with_min() public {
//         purse.file("min", rad(30 ether));
//         purse.file("gap", 10 minutes);
//         purse.give(bytes32("INTERNAL"), alice, rad(40 ether));
//         hevm.warp(now + 10 minutes);
//         purse.keep();
//         assertEq(vat.good(address(purse)), rad(40 ether));
//         assertEq(vat.good(address(alice)), rad(60 ether));
//         hevm.warp(now + 10 minutes);
//         purse.keep();
//         assertEq(vat.good(address(purse)), rad(30 ether));
//         assertEq(vat.good(address(alice)), rad(70 ether));
//     }
//     function test_keep_after_expenses_with_full_and_min() public {
//         purse.file("full", rad(20 ether));
//         purse.file("min", rad(30 ether));
//         purse.file("gap", 10 minutes);
//         purse.give(bytes32("INTERNAL"), alice, rad(40 ether));
//         hevm.warp(now + 10 minutes);
//         purse.keep();
//         assertEq(vat.good(address(purse)), rad(30 ether));
//         assertEq(vat.good(address(alice)), rad(70 ether));
//         hevm.warp(now + 10 minutes);
//         purse.keep();
//         assertEq(vat.good(address(purse)), rad(30 ether));
//         assertEq(vat.good(address(alice)), rad(70 ether));
//     }
//     function test_full_and_min_bigger_than_treasury_amount() public {
//         purse.file("full", rad(120 ether));
//         purse.file("min", rad(130 ether));
//         purse.file("gap", 10 minutes);
//         purse.give(bytes32("INTERNAL"), alice, rad(40 ether));
//         hevm.warp(now + 10 minutes);
//         purse.keep();
//         assertEq(vat.good(address(purse)), rad(60 ether));
//         assertEq(vat.good(address(alice)), rad(40 ether));
//         hevm.warp(now + 10 minutes);
//         purse.keep();
//         assertEq(vat.good(address(purse)), rad(60 ether));
//         assertEq(vat.good(address(alice)), rad(40 ether));
//     }
// }
