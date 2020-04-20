/// vox1.t.sol -- tests for Vox1

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
import {Vow} from '../vow.sol';
import {Vox1, Vox2} from '../vox.sol';
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

        vox = new Vox1(address(spot));
        vox.file("pip", address(stableFeed));
        vox.file("trim", 5 * 10 ** 24);

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
    }

    function test_no_deviation() public {
        hevm.warp(now + 1 seconds);
        vox.back();
        assertEq(vox.fix(), ray(1 ether));
        assertEq(spot.way(), ray(1 ether));
    }

    function testFail_back_same_era() public {
        hevm.warp(now + 1 seconds);
        vox.back();
        vox.back();
    }

    function test_par_bigger_than_fix() public {
        spot.file("par", ray(15 ether));
        stableFeed.poke(8.9587 ether);
        hevm.warp(now + 1 seconds);
        vox.back();
        assertEq(vox.fix(), ray(8.9587 ether));
        assertEq(spot.par(), ray(15 ether));
        assertEq(spot.way(), 1000000016344022011022743085);

        hevm.warp(now + SPY * 1 seconds);

        vox.back();

        assertEq(spot.par(), 25115251096699297888487171340);
        assertEq(spot.way(), 1000000032688044289172541667);

        assertEq(rmul(rpow(1000000032688044289172541667, SPY, RAY), ray(8.9587 ether)), 25115251096699297887771668223);
    }

    function test_par_smaller_than_fix() public {
        spot.file("par", ray(5.521 ether));
        stableFeed.poke(11.34 ether);
        hevm.warp(now + 1 seconds);
        vox.back();
        assertEq(vox.fix(), ray(11.34 ether));
        assertEq(spot.par(), ray(5.521 ether));
        assertEq(spot.way(), 999999977176011440519000573);
        assertEq(rmul(rpow(999999977176011440519000573, SPY, RAY), ray(11.34 ether)), 5520999909299969641079989150);
    }

    function test_back_negative_deviation() public {
        stableFeed.poke(0.995 ether);
        hevm.warp(now + 1 seconds);
        vox.back();
        assertEq(vox.fix(), ray(0.995 ether));
        assertEq(spot.par(), ray(1 ether));
        assertEq(spot.way(), 1000000000158946658547141217);
        hevm.warp(now + SPY * 1 seconds);
        vox.back();
        assertEq(spot.par(), 1005025125628140703501565638);
    }

    function test_back_positive_deviation() public {
        hevm.warp(now + 1 seconds);
        stableFeed.poke(1.1 ether);
        vox.back();
        hevm.warp(now + SPY * 1 seconds);
        stableFeed.poke(1.1 ether);
        vox.back();
        assertEq(vox.fix(), ray(1.1 ether));
        assertEq(spot.par(), 909090908829042986952227407);
        assertEq(spot.way(), 999999993955468021537041335);
        hevm.warp(now + (SPY / 100) * 1 seconds);
        vox.back();
        assertEq(spot.par(), 907359647049325613469016272);
    }

    function test_how_positive_deviation() public {
        vox.file("how", 0.005 ether);
        stableFeed.poke(0.995 ether);
        hevm.warp(now + 1 seconds);
        vox.back();
        assertEq(vox.bowl(), 0);
        assertEq(vox.path(), 1);

        hevm.warp(now + SPY * 1 seconds);
        vox.back();

        assertEq(vox.bowl(), 31536000);
        assertEq(vox.path(), 1);
        assertEq(spot.par(), 1005025125628140703501565638);

        hevm.warp(now + SPY * 1 seconds);
        vox.back();

        assertEq(vox.bowl(), 63072000);
        assertEq(vox.path(), 1);
        assertEq(spot.par(), 1015309731802874375366504590);
    }

    function test_how_negative_deviation() public {
        // First positive deviation
        vox.file("how", 0.005 ether);
        stableFeed.poke(0.995 ether);
        hevm.warp(now + 1 seconds);
        vox.back();
        assertEq(vox.bowl(), 0);
        assertEq(vox.path(), 1);

        hevm.warp(now + SPY * 10 seconds);
        vox.back();

        assertEq(spot.par(), 1051402953210356466797473310);

        // Then negative
        hevm.warp(now + 1 seconds);
        stableFeed.poke(1.11 ether);
        vox.back();
        assertEq(vox.bowl(), 315360000);
        assertEq(vox.path(), -1);

        hevm.warp(now + 1 seconds);
        vox.back();

        hevm.warp(now + (SPY / 10 - 1) * 1 seconds);
        vox.back();

        assertEq(vox.bowl(), 318513600);
        assertEq(vox.path(), -1);
        assertEq(spot.par(), 1045560092677402968993800002);

        hevm.warp(now + (SPY / 10) * 1 seconds);
        vox.back();

        assertEq(vox.bowl(), 321667200);
        assertEq(vox.path(), -1);
        assertEq(spot.par(), 1039169760169358078599943151);
    }

    function test_rates_with_go() public {
        vox.file("go", ray(2 ether));

        stableFeed.poke(0.995 ether);
        hevm.warp(now + 1 seconds);
        vox.back();

        assertEq(spot.way(), 1000000000317100562410225509);

        hevm.warp(now + 1 seconds);
        stableFeed.poke(1.006 ether);
        vox.back();

        assertEq(spot.way(), 999999999621747519118189746);
    }

    function test_mix_default_with_computed_rates() public {
        // Positive default rate
        vox.file("deaf", 1000000000158946658547141217);

        stableFeed.poke(0.995 ether);
        hevm.warp(now + 1 seconds);
        vox.back();

        assertEq(spot.par(), ray(1 ether));
        assertEq(spot.way(), 1000000000317893317094282434);

        stableFeed.poke(1.006 ether);
        hevm.warp(now + 1 seconds);
        vox.back();

        assertEq(spot.par(), 1000000000317893317094282434);
        assertEq(spot.way(), 999999999810309761535340024);

        // Negative default rate
        vox.file("deaf", 999999999841846096162053742);

        hevm.warp(now + 1 seconds);
        vox.back();

        assertEq(spot.par(), 1000000000128203078569321198);
        assertEq(spot.way(), 999999999652155851682355762);

        stableFeed.poke(0.992 ether);
        hevm.warp(now + 1 seconds);
        vox.back();

        assertEq(spot.par(), 999999999780358930207082269);
        assertEq(spot.way(), 1000000000254698486765794018);

        hevm.warp(now + 1 seconds);
        vox.back();

        assertEq(spot.par(), 1000000000035057416916934038);
        assertEq(spot.way(), 1000000000254698494842230053);
        assertEq(rmul(rpow(1000000000254698494842230053, SPY, RAY), ray(0.992 ether)), 1000000000035057416882104091);
    }

    function test_custom_default_per_second_rate() public {
        vox.file("deaf", ray(1 ether) + 1);
        hevm.warp(now + 1 seconds);
        vox.back();
        assertEq(spot.par(), ray(1 ether));
        hevm.warp(now + 1 seconds);
        vox.back();
        assertEq(spot.par(), ray(1 ether) + 1);
    }
}
