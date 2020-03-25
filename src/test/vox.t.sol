/// vox.t.sol -- tests for vox.sol

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

import {Pot} from "../pot.sol";
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

    Pot     pot;
    Hevm    hevm;

    address vow;
    address self;

    uint constant SPY = 31536000;
    uint constant RAY = 10 ** 27;

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }

    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }

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

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, y) / RAY;
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

        pot = new Pot(address(vat), address(spot));
        stableFeed = new Feed(1 ether, true);

        vox = new Vox(address(pot), address(jug), address(spot));
        vox.file("pip", address(stableFeed));
        vox.file("trim", 5 * 10 ** 24);

        pot.rely(address(vox));
        jug.rely(address(vox));

        spot.rely(address(pot));
        vat.rely(address(pot));

        pot.file("vow", address(vow));

        self = address(this);

        vat.frob("gold", self, self, self, 10 ether, 5 ether);
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

    function testSetup() public {
        assertTrue(address(vox.pot()) == address(pot));
        assertTrue(address(vox.jug()) == address(jug));
    }

    function testProdNoDeviation() public {
        pot.drip();
        jug.drip();
        vox.back();
        assertEq(vox.fix(), ray(1 ether));
        assertEq(pot.way(), ray(1 ether));
    }

    function testFailNoDripping() public {
        pot.drip();
        jug.drip();
        vox.back();
        hevm.warp(now + 1 seconds);
        vox.back();
    }

    function testFailRestBetweenBacks() public {
        vox.file("rest", 600);
        pot.drip();
        jug.drip();
        vox.back();
        pot.drip();
        jug.drip();
        vox.back();
    }

    function testRestBetweenBacks() public {
        vox.file("rest", 600);
        vox.back();
        hevm.warp(now + 600 seconds);
        pot.drip();
        jug.drip();
        vox.back();
    }

    function testParSmallerThanRay() public {
        spot.file("par", ray(0.9 ether));
        stableFeed.poke(0.1 ether);
        pot.drip();
        jug.drip();
        vox.back();
        assertEq(pot.rho(), now);
        // assertEq(vox.fix(), ray(0.8 ether));
        // assertEq(spot.par(), ray(0.9 ether));
        assertEq(pot.way(), 1000000069673536716147327665);

        // hevm.warp(now + SPY * 1 seconds);
        //
        // pot.drip();
        // jug.drip();
        // vox.back();
        //
        //
        // assertEq(spot.par(), 0);
        //
        // assertEq(mul(ray(0.995 ether), RAY) / ray(1 ether), 0);

        //assertEq((mul(ray(0.9 ether), RAY) / ray(0.8 ether)), 0);
        //assertEq((mul(spot.par(), RAY) / vox.fix() * ray(0.005 ether) / RAY) + ray(1 ether), 0);
        //assertEq((mul(vox.fix(), RAY) / spot.par() * ray(0.005 ether) / RAY) + ray(1 ether), 0);
        //assertEq(jug.base(), 999999999841053342340732959);
        //assertEq(rmul(rpow(1000000069673536716147327665, SPY, RAY), ray(0.1 ether)), 0);
    }

    // function testBackNegativeDeviation() public {
    //     stableFeed.poke(0.995 ether);
    //     pot.drip();
    //     jug.drip();
    //     vox.back();
    //     assertEq(pot.rho(), now);
    //     assertEq(vox.fix(), ray(0.995 ether));
    //     assertEq(spot.par(), ray(1 ether));
    //     assertEq(pot.way(), 1000000000158153903837946258);
    //     assertEq(jug.base(), 1000000000158153903837946258);
    //     hevm.warp(now + SPY * 1 seconds);
    //     assertTrue(now > pot.rho());
    //     pot.drip();
    //     jug.drip();
    //     (, uint rho) = jug.ilks("gold");
    //     assertEq(rho, now);
    //     assertEq(spot.par(), 1004999999999999999993941765);
    //     assertEq(vat.mai(address(vow)), 24999999999999999969708825000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.mai(address(pot)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 5024999999999999999969708825000000000000000000);
    // }
    //
    // function testBackPositiveDeviation() public {
    //     // First negative
    //     stableFeed.poke(0.995 ether);
    //     pot.drip();
    //     jug.drip();
    //     vox.back();
    //     hevm.warp(now + SPY * 1 seconds);
    //     pot.drip();
    //     jug.drip();
    //     // Then positive
    //     stableFeed.poke(1.005 ether);
    //     vox.back();
    //     assertEq(pot.rho(), now);
    //     assertEq(vox.fix(), ray(1.005 ether));
    //     assertEq(spot.par(), 1004999999999999999993941765);
    //     assertEq(pot.way(), 999999999841846096162053742);
    //     assertEq(jug.base(), 999999999841846096162053742);
    //     hevm.warp(now + (SPY - 100) * 1 seconds);
    //     assertTrue(now > pot.rho());
    //     pot.drip();
    //     jug.drip();
    //     (, uint rho) = jug.ilks("gold");
    //     assertEq(rho, now);
    //     assertEq(spot.par(), 1000000015814601710924062409);
    //     assertEq(vat.mai(address(vow)), 79073008554620312045000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.mai(address(pot)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 5000000079073008554620312045000000000000000000);
    // }
    //
    // function testRateSpread() public {
    //     vox.file("span", ray(2 ether));
    //
    //     stableFeed.poke(0.995 ether);
    //     vox.back();
    //
    //     assertEq(spot.par(), ray(1 ether));
    //     assertEq(pot.way(), 1000000000079175551708715275);
    //     assertEq(jug.base(), 1000000000158153903837946258);
    //     hevm.warp(now + SPY * 1 seconds);
    //
    //     jug.drip();
    //     pot.drip();
    //
    //     assertEq(spot.par(), 1002499999999999999998720538);
    //     assertEq(vat.mai(address(vow)), 24999999999999999969708825000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.mai(address(pot)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 5024999999999999999969708825000000000000000000);
    //
    //     stableFeed.poke(1.005 ether);
    //     vox.back();
    //
    //     assertEq(pot.way(), 999999999841846096162053742);
    //     assertEq(jug.base(), 999999999920824448291284725);
    //
    //     hevm.warp(now + (SPY - 100) * 1 seconds);
    //     jug.drip();
    //     pot.drip();
    //
    //     assertEq(spot.par(), 997512453586207179309588326);
    //     assertEq(vat.mai(address(vow)), 12468867615682285335000435000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.mai(address(pot)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 5012468867615682285335000435000000000000000000);
    // }
    //
    // function testMultiHikePositiveDeviation() public {
    //     vox.file("how", ray(1.00000005 ether));
    //     stableFeed.poke(0.995 ether);
    //     vox.back();
    //     assertEq(vox.bowl(), 0);
    //     assertEq(vox.path(), 1);
    //
    //     hevm.warp(now + SPY * 1 seconds);
    //     jug.drip();
    //     pot.drip();
    //     vox.back();
    //
    //     assertEq(vox.bowl(), 31536000);
    //     assertEq(vox.path(), 1);
    //     assertEq(spot.par(), 1004999999999999999993941765);
    //     assertEq(vat.mai(address(vow)), 24999999999999999969708825000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.mai(address(pot)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 5024999999999999999969708825000000000000000000);
    //
    //     hevm.warp(now + SPY * 1 seconds);
    //     jug.drip();
    //     pot.drip();
    //     vox.back();
    //
    //     assertEq(vox.bowl(), 63072000);
    //     assertEq(vox.path(), 1);
    //     assertEq(spot.par(), 4839323606636171096946428139);
    //     assertEq(vat.mai(address(vow)), 19196618033180855484732140695000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.mai(address(pot)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 24196618033180855484732140695000000000000000000);
    // }

    // function testMultiHikeNegativeDeviation() public {
    //     vox.file("how", ray(1.00000005 ether));
    //     stableFeed.poke(1.005 ether);
    //     vox.back();
    //     assertEq(vox.bowl(), 0);
    //     assertEq(vox.path(), -1);
    //
    //     hevm.warp(now + SPY * 1 seconds);
    //     jug.drip();
    //     pot.drip();
    //     vox.back();
    //
    //     assertEq(vox.bowl(), 31536000);
    //     assertEq(vox.path(), -1);
    //     assertEq(spot.par(), 995024875621105672471661507);
    //     assertEq(vat.mai(address(vow)), -24875621894471637641692465000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.mai(address(pot)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 4975124378105528362358307535000000000000000000);
    //
    //     hevm.warp(now + SPY * 1 seconds);
    //     jug.drip();
    //     pot.drip();
    //     vox.back();
    //
    //     assertEq(vox.bowl(), 63072000);
    //     assertEq(vox.path(), -1);
    //     assertEq(spot.par(), 204584308297806743096017755);
    //     assertEq(vat.mai(address(vow)), -3977078458510966284519911225000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.mai(address(pot)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 1022921541489033715480088775000000000000000000);
    // }

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
        assertEq(pot.way(), ray(1 ether) + 1);
        assertEq(jug.base(), 1000000000158153903837946258);
    }
}
