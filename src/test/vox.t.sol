/// vox.t.sol -- test for vox.sol

// Copyright (C) 2015-2020  DappHub, LLC
// Copyright (C) 2020       Stefan C. Ionescu <stefanionescu@protonmail.com>

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

import "ds-test/test.sol";
import "ds-token/token.sol";

import {Mai} from "../mai.sol";
import {Vat} from '../vat.sol';
import {Jug} from "../jug.sol";
import {Vow} from '../vow.sol';
import {Vox} from '../vox.sol';
import {GemJoin} from '../join.sol';
import {Spotter} from '../spot.sol';
import {Exp} from "../exp.sol";

contract Feed {
    bytes32 public val;
    bool public has;
    constructor(uint256 initVal, bool initHas) public {
        val = bytes32(initVal);
        has = initHas;
    }
    function poke(uint256 val_) external {
        val = bytes32(val_);
    }
    function peek() external view returns (bytes32, bool) {
        return (val, has);
    }
}

contract Hevm {
    function warp(uint256) public;
}

contract VoxTest is DSTest {
    Vat     vat;
    Spotter spot;
    Jug     jug;
    Vox     vox;
    Feed    stableFeed;

    GemJoin gemA;
    DSToken gold;
    Feed    goldFeed;

    Mai     token;
    Hevm    hevm;

    address vow;
    address self;

    uint constant SPY = 31536000;

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }

    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        vow = address(0x123456789);

        vat = new Vat();
        spot = new Spotter(address(vat));
        vat.rely(address(spot));

        jug = new Jug(address(vat));
        vat.rely(address(jug));
        jug.init("gold");
        jug.file("gold", "duty", 0);
        jug.file("base", ray(1 ether));
        jug.file("vow", address(vow));

        gold = new DSToken("GEM");
        gold.mint(1000 ether);
        vat.init("gold");
        goldFeed = new Feed(1 ether, true);
        spot.file("gold", "pip", address(goldFeed));
        spot.file("gold", "tam", 1000000000000000000000000000);
        spot.file("gold", "mat", 1000000000000000000000000000);
        spot.poke("gold");
        gemA = new GemJoin(address(vat), "gold", address(gold));

        vat.file("gold", "line", rad(1000 ether));
        vat.file("Line",         rad(1000 ether));

        gold.approve(address(gemA));
        gold.approve(address(vat));

        vat.rely(address(gemA));

        gemA.join(address(this), 1000 ether);

        token = createToken();
        stableFeed = new Feed(1 ether, true);

        vox = new Vox(address(token), address(spot));
        vox.file("pip", address(stableFeed));
        vox.file("jug", address(jug));
        vox.file("trim", 5 * 10 ** 24);
        token.rely(address(vox));
        jug.rely(address(vox));

        spot.rely(address(token));
        vat.rely(address(token));

        token.file("vow", address(vow));
        token.file("spot", address(spot));

        self = address(this);

        vat.frob("gold", self, self, self, 10 ether, 5 ether);
        token.mint(self, 5 ether);
    }

    function gem(bytes32 ilk, address urn) internal view returns (uint) {
        return vat.gem(ilk, urn);
    }
    function ink(bytes32 ilk, address urn) internal view returns (uint) {
        (uint ink_, uint art_) = vat.urns(ilk, urn); art_;
        return ink_;
    }
    function art(bytes32 ilk, address urn) internal view returns (uint) {
        (uint ink_, uint art_) = vat.urns(ilk, urn); ink_;
        return art_;
    }

    function createToken() internal returns (Mai) {
        return new Mai(99, address(vat));
    }

    function testSetup() public {
        assertTrue(address(vox.tkn()) == address(token));
        assertTrue(address(vox.jug()) == address(jug));
        assertTrue(address(vox.spot()) == address(spot));
    }

    function testProdNoDeviation() public {
        token.drip();
        jug.drip();
        vox.back();
        assertEq(vox.mpr(), ray(1 ether));
        assertEq(token.msr(), ray(1 ether));
    }

    function testFailNoDripping() public {
        token.drip();
        jug.drip();
        vox.back();
        hevm.warp(now + 1 seconds);
        vox.back();
    }

    function testFailRestBetweenBacks() public {
        vox.file("rest", 600);
        token.drip();
        jug.drip();
        vox.back();
        token.drip();
        jug.drip();
        vox.back();
    }

    function testRestBetweenBacks() public {
        vox.file("rest", 600);
        vox.back();
        hevm.warp(now + 600 seconds);
        token.drip();
        jug.drip();
        vox.back();
    }

    function testBackNegativeDeviation() public {
        stableFeed.poke(0.995 ether);
        token.drip();
        jug.drip();
        vox.back();
        assertEq(token.rho(), now);
        assertEq(vox.mpr(), ray(0.995 ether));
        assertEq(spot.par(), ray(1 ether));
        assertEq(token.msr(), 1000000000158153903837946258);
        assertEq(jug.base(), 1000000000158153903837946258);
        hevm.warp(now + SPY * 1 seconds);
        assertTrue(now > token.rho());
        token.drip();
        jug.drip();
        (, uint rho) = jug.ilks("gold");
        assertEq(rho, now);
        assertEq(spot.par(), 1004999999999999999993941765);
        assertEq(vat.mai(address(vow)), 24999999999999999969708825000000000000000000);
        assertEq(vat.sin(address(vow)), 24999999999999999969708825000000000000000000);
        assertEq(vat.mai(address(token)), 24999999999999999969708825000000000000000000);
        assertEq(vat.vice(), 24999999999999999969708825000000000000000000);
        assertEq(vat.debt(), 5049999999999999999939417650000000000000000000);
    }

    function testBackPositiveDeviation() public {
        stableFeed.poke(1.005 ether);
        vox.back();
        assertEq(token.rho(), now);
        assertEq(vox.mpr(), ray(1.005 ether));
        assertEq(spot.par(), ray(1 ether));
        assertEq(token.msr(), 999999999841846096162053742);
        assertEq(jug.base(), 999999999841846096162053742);
        hevm.warp(now + SPY * 1 seconds);
        assertTrue(now > token.rho());
        token.drip();
        jug.drip();
        (, uint rho) = jug.ilks("gold");
        assertEq(rho, now);
        assertEq(spot.par(), 995024875621105672471661507);
        assertEq(vat.mai(address(vow)), -24875621894471637641692465000000000000000000);
        assertEq(vat.sin(address(vow)), -24875621894471637641692465000000000000000000);
        assertEq(vat.mai(address(token)), -24875621894471637641692465000000000000000000);
        assertEq(vat.vice(), -24875621894471637641692465000000000000000000);
        assertEq(vat.debt(), 4950248756211056724716615070000000000000000000);
    }

    function testRateSpread() public {
        vox.file("span", ray(2 ether));

        stableFeed.poke(0.995 ether);
        vox.back();

        assertEq(spot.par(), ray(1 ether));
        assertEq(token.msr(), 1000000000079175551708715275);
        assertEq(jug.base(), 1000000000158153903837946258);
        hevm.warp(now + SPY * 1 seconds);

        jug.drip();
        token.drip();

        assertEq(spot.par(), 1002499999999999999998720538);
        assertEq(vat.mai(address(vow)), 24999999999999999969708825000000000000000000);
        assertEq(vat.sin(address(vow)), 12499999999999999993602690000000000000000000);
        assertEq(vat.mai(address(token)), 12499999999999999993602690000000000000000000);
        assertEq(vat.vice(), 12499999999999999993602690000000000000000000);
        assertEq(vat.debt(), 5037499999999999999963311515000000000000000000);

        stableFeed.poke(1.005 ether);
        vox.back();

        assertEq(token.msr(), 999999999841846096162053742);
        assertEq(jug.base(), 999999999920824448291284725);

        hevm.warp(now + SPY * 1 seconds);
        jug.drip();
        token.drip();

        assertEq(spot.par(), 997512437810158436651567564);
        assertEq(vat.mai(address(vow)), 12468827929183639250826420000000000000000000);
        assertEq(vat.sin(address(vow)), -12437810949207816742162180000000000000000000);
        assertEq(vat.mai(address(token)), -12437810949207816742162180000000000000000000);
        assertEq(vat.vice(), -12437810949207816742162180000000000000000000);
        assertEq(vat.debt(), 5000031016979975822508664240000000000000000000);
    }

    function testMultiHikePositiveDeviation() public {
        vox.file("hike", ray(1.00000005 ether));
        stableFeed.poke(0.995 ether);
        vox.back();
        assertEq(vox.bowl(), 0);
        assertEq(vox.path(), 1);

        hevm.warp(now + SPY * 1 seconds);
        jug.drip();
        token.drip();
        vox.back();

        assertEq(vox.bowl(), 31536000);
        assertEq(vox.path(), 1);
        assertEq(spot.par(), 1004999999999999999993941765);
        assertEq(vat.mai(address(vow)), 24999999999999999969708825000000000000000000);
        assertEq(vat.sin(address(vow)), 24999999999999999969708825000000000000000000);
        assertEq(vat.mai(address(token)), 24999999999999999969708825000000000000000000);
        assertEq(vat.vice(), 24999999999999999969708825000000000000000000);
        assertEq(vat.debt(), 5049999999999999999939417650000000000000000000);

        hevm.warp(now + SPY * 1 seconds);
        jug.drip();
        token.drip();
        vox.back();

        assertEq(vox.bowl(), 63072000);
        assertEq(vox.path(), 1);
        assertEq(spot.par(), 4839323606636171096946428139);
        assertEq(vat.mai(address(vow)), 19196618033180855484732140695000000000000000000);
        assertEq(vat.sin(address(vow)), 19196618033180855484732140695000000000000000000);
        assertEq(vat.mai(address(token)), 19196618033180855484732140695000000000000000000);
        assertEq(vat.vice(), 19196618033180855484732140695000000000000000000);
        assertEq(vat.debt(), 43393236066361710969464281390000000000000000000);
    }

    function testMultiHikeNegativeDeviation() public {
        vox.file("hike", ray(1.00000005 ether));
        stableFeed.poke(1.005 ether);
        vox.back();
        assertEq(vox.bowl(), 0);
        assertEq(vox.path(), -1);

        hevm.warp(now + SPY * 1 seconds);
        jug.drip();
        token.drip();
        vox.back();

        assertEq(vox.bowl(), 31536000);
        assertEq(vox.path(), -1);
        assertEq(spot.par(), 995024875621105672471661507);
        assertEq(vat.mai(address(vow)), -24875621894471637641692465000000000000000000);
        assertEq(vat.sin(address(vow)), -24875621894471637641692465000000000000000000);
        assertEq(vat.mai(address(token)), -24875621894471637641692465000000000000000000);
        assertEq(vat.vice(), -24875621894471637641692465000000000000000000);
        assertEq(vat.debt(), 4950248756211056724716615070000000000000000000);

        hevm.warp(now + SPY * 1 seconds);
        jug.drip();
        token.drip();
        vox.back();

        assertEq(vox.bowl(), 63072000);
        assertEq(vox.path(), -1);
        assertEq(spot.par(), 204584308297806743096017755);
        assertEq(vat.mai(address(vow)), -3977078458510966284519911225000000000000000000);
        assertEq(vat.sin(address(vow)), -3977078458510966284519911225000000000000000000);
        assertEq(vat.mai(address(token)), -3977078458510966284519911225000000000000000000);
        assertEq(vat.vice(), -3977078458510966284519911225000000000000000000);
        assertEq(vat.debt(), -2954156917021932569039822450000000000000000000);
    }

    function test_bounded_stability_fee() public {
        vox.file("up", ray(1 ether));
        vox.file("down", 999999999999999999999999999);
        stableFeed.poke(1.005 ether);
        vox.back();
        assertEq(jug.base(), 999999999999999999999999999);
        stableFeed.poke(0.995 ether);
        vox.back();
        assertEq(jug.base(), ray(1 ether));
    }

    function test_custom_default_per_second_rates() public {
        vox.file("dawn", 1000000000158153903837946258);
        vox.file("dusk", ray(1 ether) + 1);
        vox.back();
        assertEq(token.msr(), ray(1 ether) + 1);
        assertEq(jug.base(), 1000000000158153903837946258);
    }
}
