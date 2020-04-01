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
    uint public zzz;
    constructor(uint256 initVal, bool initHas) public {
        val = bytes32(initVal);
        has = initHas;
        zzz = now;
    }
    function poke(uint256 val_) external {
        val = bytes32(val_);
        zzz = now;
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
    Vox1    vox;
    Feed    stableFeed;

    GemJoin gemA;
    DSToken gold;
    Feed    goldFeed;

    Hevm    hevm;

    address vow;
    address self;

    uint256 pan  = 3;
    uint256 bowl = 6;
    uint256 mug  = 3;

    uint256 trim = 0.005 ether;

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

        vox = new Vox1(address(spot), pan, bowl, mug);
        vox.file("pip", address(stableFeed));
        vox.file("trim", ray(trim));

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

    function add(uint x, int y) internal pure returns (uint z) {
        z = x + uint(y);
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function mul(int x, uint y) internal pure returns (int z) {
        require(y == 0 || (z = x * int(y)) / int(y) == x);
    }

    // Market price simulations
    function monotonous_deviations(int side_, uint times) internal {
        uint price = 1 ether;
        for (uint i = 0; i <= bowl; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_, trim * times));
          stableFeed.poke(price);
          vox.back();
        }
    }

    function major_one_side_deviations(int side_, uint times) internal {
        uint price = 1 ether; uint i;
        for (i = 0; i <= bowl / 2; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_, trim * times));
          stableFeed.poke(price);
          vox.back();
        }
        for (i = bowl / 2; i <= bowl + 1; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_ * int(-1), trim));
          stableFeed.poke(price);
          vox.back();
        }
    }

    function zig_zag_deviations(int side_, uint times) internal {
        uint price = 1 ether;
        uint i;
        int aux = side_;
        for (i = 0; i <= bowl; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(aux, trim * times));
          stableFeed.poke(price);
          vox.back();
          aux = -aux;
        }
    }

    function subtle_deviations(int side_) internal {
        uint price = 1 ether;
        uint i;
        for (i = 0; i <= bowl + 5; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_, trim / bowl));
          stableFeed.poke(price);
          vox.back();
        }
    }

    function sudden_big_deviation(int side_) internal {
        uint price = 1 ether;
        uint i;
        for (i = 0; i <= bowl; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_, trim / bowl));
          stableFeed.poke(price);
          vox.back();
        }

        hevm.warp(now + 1 seconds);
        price = add(price, mul(side_ * int(-1), trim * 50));
        stableFeed.poke(price);
        vox.back();
    }

    function test_setup() public {
        assertTrue(address(vox.spot()) == address(spot));
    }

    function test_pid_increasing_deviations() public {
        monotonous_deviations(int(1), 1);
        assertEq(vox.way(), 999999990719507378206522849);
        assertEq(vox.rho(), now);
        assertEq(spot.par(), 999999990778722693784613721);
        assertEq(vox.fix(), ray(1.035 ether));
        assertEq(rmul(rpow(999999990778722693784613721, SPY, RAY), 999999990719507378206522849), 747663542458272649607967062);
    }

    function test_pid_decreasing_deviations() public {
        monotonous_deviations(int(-1), 1);
        assertEq(vox.way(), 1000000009280492621793477151);
        assertEq(vox.rho(), now);
        assertEq(spot.par(), 1000000009221277306215386279);
        assertEq(vox.fix(), ray(0.965 ether));
        assertEq(rmul(rpow(1000000009221277306215386279, SPY, RAY), 1000000009280492621793477151), 1337500012412658881605695380);
    }

    function test_major_negative_deviations() public {
        major_one_side_deviations(-1, 2);

        assertEq(vox.way(), 1000000003104524158656075033);
        assertEq(vox.rho(), now);
        assertEq(spot.par(), 1000000019457540831238950507);
        assertEq(vox.fix(), ray(0.985 ether));

        // hevm.warp(now + 1 seconds);
        // stableFeed.poke(vox.fix());
        // vox.back();
    }

    function test_major_positive_deviations() public {
        major_one_side_deviations(1, 3);
        assertEq(vox.way(), 999999993365388542556944540);
        assertEq(vox.rho(), now);
        assertEq(spot.par(), 999999968117093628044091396);
        assertEq(vox.fix(), ray(1.035 ether));
    }

    function test_zig_zag_deviations() public {
        zig_zag_deviations(-1, 5);

        assertEq(vox.way(), 1000000005781378656804591713);
        assertEq(vox.rho(), now);
        assertEq(spot.par(), 1000000001167363430498603316);
        assertEq(vox.fix(), ray(0.975 ether));

        (int P, int I , int D, uint pid) = vox.full(spot.par(), vox.fix(), 1);

        assertEq(vox.fat(), 0);
        assertEq(vox.thin(), 0);

        // assertEq(P, 0);
        // assertEq(I, 0);
        // assertEq(D, 0);
        // assertEq(pid, 0);
    }

    function test_sudden_big_negative_deviation() public {
        sudden_big_deviation(1);
    }

    function test_sudden_big_positive_deviation() public {
        sudden_big_deviation(-1);
    }

    function test_deviation_waves() public {
        monotonous_deviations(-1, 5);
        // monotonous_deviations(1, 1);


    }

    function test_drop_back_to_normal() public {

    }

    // function test_no_deviation() public {
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //     assertEq(vox.fix(), ray(1 ether));
    //     assertEq(vox.way(), ray(1 ether));
    // }
    //
    // function testFail_no_prior_dropping() public {
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //     hevm.warp(now + 1 seconds);
    //     vox.back();
    // }
    //
    // function testFail_back_same_era() public {
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //     jug.drip();
    //     vox.back();
    // }
    //
    // function test_par_bigger_than_fix() public {
    //     spot.file("par", ray(15 ether));
    //     stableFeed.poke(8.9587 ether);
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //     assertEq(vox.fix(), ray(8.9587 ether));
    //     assertEq(spot.par(), ray(15 ether));
    //     assertEq(vox.way(), 1000000016344022011022743085);
    //
    //     hevm.warp(now + SPY * 1 seconds);
    //
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(spot.par(), 25115251096699297888487171340);
    //     assertEq(vox.way(), 1000000032688044289172541667);
    //     assertEq(jug.base(), 1000000032688044289172541667);
    //
    //     assertEq(rmul(rpow(1000000032688044289172541667, SPY, RAY), ray(8.9587 ether)), 25115251096699297887771668223);
    // }
    //
    // function test_par_smaller_than_fix() public {
    //     spot.file("par", ray(5.521 ether));
    //     stableFeed.poke(11.34 ether);
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //     assertEq(vox.fix(), ray(11.34 ether));
    //     assertEq(spot.par(), ray(5.521 ether));
    //     assertEq(vox.way(), 999999977176011440519000573);
    //     assertEq(rmul(rpow(999999977176011440519000573, SPY, RAY), ray(11.34 ether)), 5520999909299969641079989150);
    // }
    //
    // function test_back_negative_deviation() public {
    //     stableFeed.poke(0.995 ether);
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //     assertEq(vox.fix(), ray(0.995 ether));
    //     assertEq(spot.par(), ray(1 ether));
    //     assertEq(vox.way(), 1000000000158946658547141217);
    //     assertEq(jug.base(), 1000000000158946658547141217);
    //     hevm.warp(now + SPY * 1 seconds);
    //     jug.drip();
    //     vox.back();
    //     (, uint rho) = jug.ilks("gold");
    //     assertEq(rho, now);
    //     assertEq(spot.par(), 1005025125628140703501565638);
    //     assertEq(vat.good(address(vow)), 25125628140703517507828190000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.good(address(vox)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 5025125628140703517507828190000000000000000000);
    // }
    //
    // function test_back_positive_deviation() public {
    //     // First negative
    //     stableFeed.poke(0.995 ether);
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //     hevm.warp(now + SPY * 1 seconds);
    //     jug.drip();
    //     vox.back();
    //     // Then positive
    //     hevm.warp(now + 1 seconds);
    //     stableFeed.poke(1.1 ether);
    //     jug.drip();
    //     vox.back();
    //     assertEq(vox.fix(), ray(1.1 ether));
    //     assertEq(spot.par(), 1005025125947631474475984204);
    //     assertEq(vox.way(), 999999997136680688985199591);
    //     assertEq(jug.base(), 999999997136680688985199591);
    //     hevm.warp(now + (SPY / 100) * 1 seconds);
    //     jug.drip();
    //     vox.back();
    //     assertEq(spot.par(), 1004118021606915573096466642);
    //     assertEq(vat.good(address(vow)), 20590108034577865482333210000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.good(address(vox)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 5020590108034577865482333210000000000000000000);
    // }
    //
    // function test_rate_spread() public {
    //     vox.file("span", ray(2 ether));
    //
    //     stableFeed.poke(0.995 ether);
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(spot.par(), ray(1 ether));
    //     assertEq(vox.way(), 1000000000158946658547141217);
    //     assertEq(jug.base(), 1000000000079572920012861247);
    //
    //     hevm.warp(now + SPY * 1 seconds);
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(spot.par(), 1005025125628140703501565638);
    //     assertEq(vat.good(address(vow)), 12562814070351758813927905000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.good(address(vox)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 5012562814070351758813927905000000000000000000);
    //
    //     hevm.warp(now + SPY * 1 seconds);
    //     stableFeed.poke(1.060 ether);
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(vox.way(), 999999998629145018931543664);
    //     assertEq(jug.base(), 999999999307165109112261485);
    //
    //     hevm.warp(now + (SPY / 100) * 1 seconds);
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(spot.par(), 1014712491379499956218936761);
    //     assertEq(vat.good(address(vow)), 36714256191198617561597915000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.good(address(vox)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 5036714256191198617561597915000000000000000000);
    // }
    //
    // function test_how_positive_deviation() public {
    //     vox.file("how", 0.005 ether);
    //     stableFeed.poke(0.995 ether);
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //     assertEq(vox.bowl(), 0);
    //     assertEq(vox.path(), 1);
    //
    //     hevm.warp(now + SPY * 1 seconds);
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(vox.bowl(), 31536000);
    //     assertEq(vox.path(), 1);
    //     assertEq(spot.par(), 1005025125628140703501565638);
    //     assertEq(vat.good(address(vow)), 25125628140703517507828190000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.good(address(vox)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 5025125628140703517507828190000000000000000000);
    //
    //     hevm.warp(now + SPY * 1 seconds);
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(vox.bowl(), 63072000);
    //     assertEq(vox.path(), 1);
    //     assertEq(spot.par(), 1015309731802874375366504590);
    //     assertEq(vat.good(address(vow)), 76548659014371876832522950000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.good(address(vox)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 5076548659014371876832522950000000000000000000);
    // }
    //
    // function test_how_negative_deviation() public {
    //     // First positive deviation
    //     vox.file("how", 0.005 ether);
    //     stableFeed.poke(0.995 ether);
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //     assertEq(vox.bowl(), 0);
    //     assertEq(vox.path(), 1);
    //
    //     hevm.warp(now + SPY * 10 seconds);
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(spot.par(), 1051402953210356466797473310);
    //
    //     // Then negative
    //     hevm.warp(now + 1 seconds);
    //     stableFeed.poke(1.11 ether);
    //     jug.drip();
    //     vox.back();
    //     assertEq(vox.bowl(), 315360000);
    //     assertEq(vox.path(), -1);
    //
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //
    //     hevm.warp(now + (SPY / 10 - 1) * 1 seconds);
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(vox.bowl(), 318513600);
    //     assertEq(vox.path(), -1);
    //     assertEq(spot.par(), 1045560092677402968993800002);
    //     assertEq(vat.good(address(vow)), 227800463387014844969000010000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.good(address(vox)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 5227800463387014844969000010000000000000000000);
    //
    //     hevm.warp(now + (SPY / 10) * 1 seconds);
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(vox.bowl(), 321667200);
    //     assertEq(vox.path(), -1);
    //     assertEq(spot.par(), 1039169760169358078599943151);
    //     assertEq(vat.good(address(vow)), 195848800846790392999715755000000000000000000);
    //     assertEq(vat.sin(address(vow)), 0);
    //     assertEq(vat.good(address(vox)), 0);
    //     assertEq(vat.vice(), 0);
    //     assertEq(vat.debt(), 5195848800846790392999715755000000000000000000);
    // }
    //
    // function test_rates_with_go() public {
    //     vox.file("go", ray(2 ether));
    //     vox.file("span", ray(2 ether));
    //
    //     stableFeed.poke(0.995 ether);
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(vox.way(), 1000000000317100562410225509);
    //     assertEq(jug.base(), 1000000000158946658547141217);
    //
    //     hevm.warp(now + 1 seconds);
    //     stableFeed.poke(1.006 ether);
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(vox.way(), 999999999621747519118189746);
    //     assertEq(jug.base(), 999999999810309761510201938);
    // }
    //
    // function test_mix_default_with_computed_rates() public {
    //     // Positive dawn & dusk
    //     vox.file("dawn", 1000000000158946658547141217);
    //     vox.file("dusk", 1000000000158946658547141217);
    //
    //     stableFeed.poke(0.995 ether);
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(spot.par(), ray(1 ether));
    //     assertEq(vox.way(), 1000000000317893317094282434);
    //     assertEq(jug.base(), 1000000000317893317094282434);
    //
    //     stableFeed.poke(1.006 ether);
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(spot.par(), 1000000000317893317094282434);
    //     assertEq(vox.way(), 999999999810309761535340024);
    //     assertEq(jug.base(), 999999999810309761535340024);
    //
    //     // Negative dawn & dusk
    //     vox.file("dawn", 999999999841846096162053742);
    //     vox.file("dusk", 999999999841846096162053742);
    //
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(spot.par(), 1000000000128203078569321198);
    //     assertEq(vox.way(), 999999999652155851682355762);
    //     assertEq(jug.base(), 999999999652155851682355762);
    //
    //     stableFeed.poke(0.992 ether);
    //     hevm.warp(now + 1 seconds);
    //     assertTrue(!jug.lap());
    //     vox.back();
    //
    //     assertEq(spot.par(), 999999999780358930207082269);
    //     assertEq(vox.way(), 1000000000254698486765794018);
    //     assertEq(jug.base(), 1000000000254698486765794018);
    //
    //     hevm.warp(now + 1 seconds);
    //     assertTrue(jug.lap());
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(spot.par(), 1000000000035057416916934038);
    //     assertEq(vox.way(), 1000000000254698494842230053);
    //     assertEq(jug.base(), 1000000000254698494842230053);
    //     assertEq(rmul(rpow(1000000000254698494842230053, SPY, RAY), ray(0.992 ether)), 1000000000035057416882104091);
    //
    //     // Mixed
    //     vox.file("dawn", 999999999841846096162053742);
    //     vox.file("dusk", 1000000000158946658547141217);
    //
    //     hevm.warp(now + 1 seconds);
    //     assertTrue(jug.lap());
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(spot.par(), 1000000000289755911768093162);
    //     assertEq(vox.way(), 1000000000413645161465807561);
    //     assertEq(jug.base(), 1000000000254698502918666344);
    //
    //     stableFeed.poke(1.005 ether);
    //     hevm.warp(now + 1 seconds);
    //
    //     jug.drip();
    //     vox.back();
    //
    //     assertEq(spot.par(), 1000000000703401073353756853);
    //     assertEq(vox.way(), 1000000000158946658547141217);
    //     assertEq(jug.base(), 999999999841846096162053742);
    // }
    //
    // function test_jug_no_drip_lap() public {
    //     stableFeed.poke(1.1 ether);
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //     assertEq(vox.fix(), ray(1.1 ether));
    //     assertEq(spot.par(), 1000000000000000000000000000);
    //     assertEq(vox.way(), 999999996977734019902612350);
    //     assertEq(jug.base(), 999999996977734019902612350);
    //     hevm.warp(now + (SPY / 100) * 1 seconds);
    //
    //     assertTrue(!jug.lap());
    //     vox.back();
    //
    //     assertEq(spot.par(), 999047352256331966915930340);
    //     assertEq(vox.way(), 999999996947511359964170393);
    //     assertEq(jug.base(), 999999996947511359964170393);
    // }
    //
    // function test_bounded_base() public {
    //     vox.file("up", ray(1 ether));
    //     vox.file("down", 999999999999999999999999999);
    //     stableFeed.poke(1.005 ether);
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //     assertEq(jug.base(), 999999999999999999999999999);
    //     stableFeed.poke(0.995 ether);
    //     hevm.warp(now + 1 seconds);
    //     assertTrue(!jug.lap());
    //     vox.back();
    //     assertEq(jug.base(), ray(1 ether));
    // }
    //
    // function test_custom_default_per_second_rates() public {
    //     vox.file("dawn", 1000000000158153903837946258);
    //     vox.file("dusk", ray(1 ether) + 1);
    //     hevm.warp(now + 1 seconds);
    //     jug.drip();
    //     vox.back();
    //     assertEq(vox.way(), ray(1 ether) + 1);
    //     assertEq(jug.base(), 1000000000158153903837946258);
    // }
}
