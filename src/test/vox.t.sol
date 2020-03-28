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

import {Vat} from '../vat.sol';
import {Jug} from "../jug.sol";
import {Vow} from '../vow.sol';
import {Vox1} from '../vox.sol';
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

contract Vox1Test is DSTest {
    Vat     vat;
    Spotter spot;
    Jug     jug;
    Vox1     vox;
    Feed    stableFeed;

    GemJoin gemA;
    DSToken gold;
    Feed    goldFeed;

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

        stableFeed = new Feed(1 ether, true);

        vox = new Vox1(address(jug), address(spot));
        vox.file("pip", address(stableFeed));
        vox.file("trim", 5 * 10 ** 24);

        jug.rely(address(vox));
        spot.rely(address(vox));

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

    function test_setup() public {
        assertTrue(address(vox.spot()) == address(spot));
        assertTrue(address(vox.jug()) == address(jug));
    }

    function test_no_deviation() public {
        vox.drip();
        jug.drip();
        vox.back();
        assertEq(vox.fix(), ray(1 ether));
        assertEq(vox.way(), ray(1 ether));
    }

    function testFail_no_prior_dropping() public {
        vox.drip();
        jug.drip();
        vox.back();
        hevm.warp(now + 1 seconds);
        vox.back();
    }

    function testFail_rest_between_backs() public {
        vox.file("rest", 600);
        vox.drip();
        jug.drip();
        vox.back();
        vox.drip();
        jug.drip();
        vox.back();
    }

    function test_rest_between_backs() public {
        vox.file("rest", 600);
        vox.back();
        hevm.warp(now + 600 seconds);
        vox.drip();
        jug.drip();
        vox.back();
    }

    function test_par_bigger_than_fix() public {
        spot.file("par", ray(15 ether));
        stableFeed.poke(8.9587 ether);
        vox.drip();
        jug.drip();
        vox.back();
        assertEq(vox.rho(), now);
        assertEq(vox.fix(), ray(8.9587 ether));
        assertEq(spot.par(), ray(15 ether));
        assertEq(vox.way(), 1000000016344022011022743085);

        hevm.warp(now + SPY * 1 seconds);

        vox.drip();
        jug.drip();
        vox.back();

        assertEq(spot.par(), 25115251096699297888487171340);
        assertEq(vox.way(), 1000000032688044289172541667);
        assertEq(jug.base(), 1000000032688044289172541667);
    }

    function test_par_smaller_than_fix() public {
        spot.file("par", ray(5.521 ether));
        stableFeed.poke(11.34 ether);
        vox.drip();
        jug.drip();
        vox.back();
        assertEq(vox.rho(), now);
        assertEq(vox.fix(), ray(11.34 ether));
        assertEq(spot.par(), ray(5.521 ether));
        assertEq(vox.way(), 999999977176011440519000573);
        assertEq(rmul(rpow(999999977176011440519000573, SPY, RAY), ray(11.34 ether)), 5520999909299969641079989150);
    }

    function test_back_negative_deviation() public {
        stableFeed.poke(0.995 ether);
        vox.drip();
        jug.drip();
        vox.back();
        assertEq(vox.rho(), now);
        assertEq(vox.fix(), ray(0.995 ether));
        assertEq(spot.par(), ray(1 ether));
        assertEq(vox.way(), 1000000000158946658547141217);
        assertEq(jug.base(), 1000000000158946658547141217);
        hevm.warp(now + SPY * 1 seconds);
        assertTrue(now > vox.rho());
        vox.drip();
        jug.drip();
        (, uint rho) = jug.ilks("gold");
        assertEq(rho, now);
        assertEq(spot.par(), 1005025125628140703501565638);
        assertEq(vat.good(address(vow)), 25125628140703517507828190000000000000000000);
        assertEq(vat.sin(address(vow)), 0);
        assertEq(vat.good(address(vox)), 0);
        assertEq(vat.vice(), 0);
        assertEq(vat.debt(), 5025125628140703517507828190000000000000000000);
    }

    function test_back_positive_deviation() public {
        // First negative
        stableFeed.poke(0.995 ether);
        vox.drip();
        jug.drip();
        vox.back();
        hevm.warp(now + SPY * 1 seconds);
        vox.drip();
        jug.drip();
        // Then positive
        stableFeed.poke(1.1 ether);
        vox.back();
        assertEq(vox.rho(), now);
        assertEq(vox.fix(), ray(1.1 ether));
        assertEq(spot.par(), 1005025125628140703501565638);
        assertEq(vox.way(), 999999997136680678904868605);
        assertEq(jug.base(), 999999997136680678904868605);
        hevm.warp(now + (SPY / 100) * 1 seconds);
        assertTrue(now > vox.rho());
        vox.drip();
        jug.drip();
        assertEq(spot.par(), 1004118021284521140426492813);
        assertEq(vat.good(address(vow)), 20590106422605702132464065000000000000000000);
        assertEq(vat.sin(address(vow)), 0);
        assertEq(vat.good(address(vox)), 0);
        assertEq(vat.vice(), 0);
        assertEq(vat.debt(), 5020590106422605702132464065000000000000000000);
    }

    function test_rate_spread() public {
        vox.file("span", ray(2 ether));

        stableFeed.poke(0.995 ether);
        vox.back();

        assertEq(spot.par(), ray(1 ether));
        assertEq(vox.way(), 1000000000158946658547141217);
        assertEq(jug.base(), 1000000000079572920012861247);
        hevm.warp(now + SPY * 1 seconds);

        jug.drip();
        vox.drip();

        assertEq(spot.par(), 1005025125628140703501565638);
        assertEq(vat.good(address(vow)), 12562814070351758813927905000000000000000000);
        assertEq(vat.sin(address(vow)), 0);
        assertEq(vat.good(address(vox)), 0);
        assertEq(vat.vice(), 0);
        assertEq(vat.debt(), 5012562814070351758813927905000000000000000000);

        stableFeed.poke(1.060 ether);
        vox.back();

        assertEq(vox.way(), 999999998311251701376211553);
        assertEq(jug.base(), 999999999144385104596960528);

        hevm.warp(now + (SPY / 100) * 1 seconds);
        jug.drip();
        vox.drip();

        assertEq(spot.par(), 1004490028264274453595667799);
        assertEq(vat.good(address(vow)), 11210473176924140255537500000000000000000000);
        assertEq(vat.sin(address(vow)), 0);
        assertEq(vat.good(address(vox)), 0);
        assertEq(vat.vice(), 0);
        assertEq(vat.debt(), 5011210473176924140255537500000000000000000000);
    }

    function test_how_positive_deviation() public {
        vox.file("how", 0.005 ether);
        stableFeed.poke(0.995 ether);
        vox.back();
        assertEq(vox.bowl(), 0);
        assertEq(vox.path(), 1);

        hevm.warp(now + SPY * 1 seconds);
        jug.drip();
        vox.drip();
        vox.back();

        assertEq(vox.bowl(), 31536000);
        assertEq(vox.path(), 1);
        assertEq(spot.par(), 1005025125628140703501565638);
        assertEq(vat.good(address(vow)), 25125628140703517507828190000000000000000000);
        assertEq(vat.sin(address(vow)), 0);
        assertEq(vat.good(address(vox)), 0);
        assertEq(vat.vice(), 0);
        assertEq(vat.debt(), 5025125628140703517507828190000000000000000000);

        hevm.warp(now + SPY * 1 seconds);
        jug.drip();
        vox.drip();
        vox.back();

        assertEq(vox.bowl(), 63072000);
        assertEq(vox.path(), 1);
        assertEq(spot.par(), 1015309731802874375366504590);
        assertEq(vat.good(address(vow)), 76548659014371876832522950000000000000000000);
        assertEq(vat.sin(address(vow)), 0);
        assertEq(vat.good(address(vox)), 0);
        assertEq(vat.vice(), 0);
        assertEq(vat.debt(), 5076548659014371876832522950000000000000000000);
    }

    function test_how_negative_deviation() public {
        // First positive deviation
        vox.file("how", 0.005 ether);
        stableFeed.poke(0.995 ether);
        vox.back();
        assertEq(vox.bowl(), 0);
        assertEq(vox.path(), 1);

        hevm.warp(now + SPY * 10 seconds);
        jug.drip();
        vox.drip();

        assertEq(spot.par(), 1051402953210356466797473310);

        // Then negative
        stableFeed.poke(1.11 ether);
        vox.back();
        assertEq(vox.bowl(), 0);
        assertEq(vox.path(), -1);

        hevm.warp(now + (SPY / 10) * 1 seconds);
        jug.drip();
        vox.drip();
        vox.back();

        assertEq(vox.bowl(), 3153600);
        assertEq(vox.path(), -1);
        assertEq(spot.par(), 1045716146668382614395389356);
        assertEq(vat.good(address(vow)), 228580733341913071976946780000000000000000000);
        assertEq(vat.sin(address(vow)), 0);
        assertEq(vat.good(address(vox)), 0);
        assertEq(vat.vice(), 0);
        assertEq(vat.debt(), 5228580733341913071976946780000000000000000000);

        hevm.warp(now + (SPY / 10) * 1 seconds);
        jug.drip();
        vox.drip();
        vox.back();

        assertEq(vox.bowl(), 6307200);
        assertEq(vox.path(), -1);
        assertEq(spot.par(), 1039494635194017352999843859);
        assertEq(vat.good(address(vow)), 197473175970086764999219295000000000000000000);
        assertEq(vat.sin(address(vow)), 0);
        assertEq(vat.good(address(vox)), 0);
        assertEq(vat.vice(), 0);
        assertEq(vat.debt(), 5197473175970086764999219295000000000000000000);
    }

    function test_rates_with_go() public {
        vox.file("go", ray(2 ether));
        vox.file("span", ray(2 ether));

        stableFeed.poke(0.995 ether);
        vox.back();

        assertEq(vox.way(), 1000000000317100562410225509);
        assertEq(jug.base(), 1000000000158946658547141217);

        stableFeed.poke(1.005 ether);
        vox.back();

        assertEq(vox.way(), 999999999684477078426627931);
        assertEq(jug.base(), 999999999841846096162053742);
    }

    function test_mix_default_with_computed_rates() public {
        // Positive dawn & dusk
        vox.file("dawn", 1000000000158946658547141217);
        vox.file("dusk", 1000000000158946658547141217);

        stableFeed.poke(0.995 ether);
        vox.back();

        assertEq(vox.way(), 1000000000317893317094282434);
        assertEq(jug.base(), 1000000000317893317094282434);

        stableFeed.poke(1.005 ether);
        vox.back();

        assertEq(vox.way(), 999999999841846096162053742);
        assertEq(jug.base(), 999999999841846096162053742);

        // Negative dawn & dusk
        vox.file("dawn", 999999999841846096162053742);
        vox.file("dusk", 999999999841846096162053742);

        vox.back();

        assertEq(vox.way(), 999999999683692192324107484);
        assertEq(jug.base(), 999999999683692192324107484);

        stableFeed.poke(0.995 ether);
        vox.back();

        assertEq(vox.way(), 1000000000158946658547141217);
        assertEq(jug.base(), 1000000000158946658547141217);

        // Mixed
        vox.file("dawn", 999999999841846096162053742);
        vox.file("dusk", 1000000000158946658547141217);

        vox.back();

        assertEq(vox.way(), 1000000000317893317094282434);
        assertEq(jug.base(), 1000000000158946658547141217);

        stableFeed.poke(1.005 ether);
        vox.back();

        assertEq(vox.way(), 999999999841846096162053742);
        assertEq(jug.base(), 999999999683692192324107484);
    }

    function test_jug_no_drip_lap() public {
        stableFeed.poke(1.1 ether);
        vox.back();
        assertEq(vox.rho(), now);
        assertEq(vox.fix(), ray(1.1 ether));
        assertEq(spot.par(), 1000000000000000000000000000);
        assertEq(vox.way(), 999999996977734019902612350);
        assertEq(jug.base(), 999999996977734019902612350);
        hevm.warp(now + (SPY / 100) * 1 seconds);

        vox.drip();
        assertTrue(!jug.lap());
        vox.back();

        assertEq(spot.par(), 999047352256331966915930340);
        assertEq(vox.way(), 999999996947511359964170393);
        assertEq(jug.base(), 999999996947511359964170393);
    }

    function test_bounded_base() public {
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
        assertEq(vox.way(), ray(1 ether) + 1);
        assertEq(jug.base(), 1000000000158153903837946258);
    }
}
