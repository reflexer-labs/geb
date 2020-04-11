/// vox2.t.sol -- tests for Vox2

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
import {Vox2} from '../vox.sol';
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

contract Vox2Test is DSTest {
    Vat     vat;
    Spotter spot;
    Vox2    vox;
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

        vox = new Vox2(address(spot), pan, bowl, mug);
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
    function add(int x, int y) internal pure returns (int z) {
        z = x + y;
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function mul(int x, uint y) internal pure returns (int z) {
        require(y == 0 || (z = x * int(y)) / int(y) == x);
    }
    function mul(int x, int y) internal pure returns (int z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // Market price simulations
    function monotonous_deviations(uint start, int side_, uint times) internal {
        uint price = start;
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
        uint i;
        uint price;
        int aux = side_;
        for (i = 0; i <= bowl * 2; i++) {
          hevm.warp(now + 1 seconds);
          price = add(uint(1 ether), mul(aux, trim * times));
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

    function sudden_big_deviation(int side_, uint times) internal {
        uint price = 1 ether;
        uint i;
        for (i = 0; i <= bowl; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_, trim / bowl));
          stableFeed.poke(price);
          vox.back();
        }

        hevm.warp(now + 1 seconds);
        price = add(price, mul(side_ * int(-1), trim * times));

        stableFeed.poke(price);
        vox.back();
    }

    function test_setup() public {
        assertTrue(address(vox.spot()) == address(spot));
    }

    function test_pid_increasing_deviations() public {
        monotonous_deviations(1 ether, int(1), 1);

        assertEq(vox.cron(1), int(ray(0.005 ether)));
        assertEq(vox.cron(2), int(ray(0.01 ether)));
        assertEq(vox.cron(3), int(ray(0.015 ether)));
        assertEq(vox.cron(4), int(ray(0.02 ether)));
        assertEq(vox.cron(5), int(ray(0.025 ether)));
        assertEq(vox.cron(6), int(ray(0.03 ether)));

        assertEq(vox.site(), -1);
        assertEq(spot.way(), 999999987371733779393155516);
        assertEq(spot.rho(), now);
        assertEq(spot.par(), 999999987411027217746836585);
        assertEq(vox.fix(), ray(1.035 ether));

        (int P, int I , int D, uint pid) = vox.full(vox.fix(), spot.par(), vox.site(), vox.road());

        assertEq(P, -35000012588972782253163415);
        assertEq(I, -135000012588972782253163415);
        assertEq(D, 2000000279754950716736964777);
        assertEq(pid, 1489208842898923378006058609);

        assertTrue(vox.fix() > spot.par());
        assertEq(mul(add(P, I), D) / int(RAY), -340000097914239794512858219);
        assertEq(add(vox.fix(), (mul(add(P, I), D) / int(RAY))), 694999902085760205487141781);
        assertEq(mul(vox.fix(), RAY) / add(vox.fix(), (mul(add(P, I), D) / int(RAY))), 1489208842898923378006058609);

        assertEq(rmul(rpow(spot.way(), SPY, RAY), spot.par()), 671497478107411469930891270);
    }

    function test_pid_decreasing_deviations() public {
        monotonous_deviations(1 ether, int(-1), 1);

        assertEq(vox.cron(1), int(-ray(0.005 ether)));
        assertEq(vox.cron(2), int(-ray(0.01 ether)));
        assertEq(vox.cron(3), int(-ray(0.015 ether)));
        assertEq(vox.cron(4), int(-ray(0.02 ether)));
        assertEq(vox.cron(5), int(-ray(0.025 ether)));
        assertEq(vox.cron(6), int(-ray(0.03 ether)));

        assertEq(vox.site(), 1);
        assertEq(spot.way(), 1000000008441244421221367546);
        assertEq(spot.rho(), now);
        assertEq(spot.par(), 1000000008501931700174301437);
        assertEq(vox.fix(), ray(0.965 ether));

        (int P, int I , int D, uint pid) = vox.full(spot.par(), vox.fix(), vox.site(), vox.road());

        assertEq(P, 35000008501931700174301437);
        assertEq(I, 135000008501931700174301437);
        assertEq(D, 2000000188931815559428920822);
        assertEq(pid, 1305000055031117321772641810);

        assertTrue(spot.par() > vox.fix());
        assertEq(mul(add(P, I), D) / int(RAY), 340000066126138658370906040);
        assertEq(add(vox.fix(), (mul(add(P, I), D) / int(RAY))), 1305000066126138658370906040);
        assertEq(add(vox.fix(), (mul(add(P, I), D) / int(RAY))) * RAY / spot.par(), 1305000055031117321772641810);

        assertEq(rmul(rpow(spot.way(), SPY, RAY), spot.par()), 1305000066126138658335048834);
    }

    function test_major_negative_deviations() public {
        major_one_side_deviations(-1, 3);

        assertEq(vox.cron(1), int(-ray(0.015 ether)));
        assertEq(vox.cron(2), int(-ray(0.03 ether)));
        assertEq(vox.cron(3), int(-ray(0.045 ether)));
        assertEq(vox.cron(4), int(-ray(0.06 ether)));
        assertEq(vox.cron(5), int(-ray(0.055 ether)));
        assertEq(vox.cron(6), int(-ray(0.05 ether)));

        assertEq(vox.site(), 1);

        assertEq(spot.way(), 1000000005721269429381730438);
        assertEq(spot.rho(), now);
        assertEq(spot.par(), 1000000028783058593493768971);
        assertEq(vox.fix(), ray(0.965 ether));

        assertEq(vox.fat(), int(-ray(0.165 ether)));
        assertEq(int(vox.thin()), int(-120000063727530115134064360));
        assertEq(vox.fit(), int(-285000063727530115134064360));

        (int P, int I , int D, uint pid) = vox.full(spot.par(), vox.fix(), vox.site(), vox.road());

        assertTrue(spot.par() > vox.fix());
        assertEq(mul(add(P, I), D) / int(RAY), 232727463600522286967081774);
        assertEq(add(vox.fix(), (mul(add(P, I), D) / int(RAY))), 1197727463600522286967081774);
        assertEq(mul(spot.par(), RAY) / add(vox.fix(), (mul(add(P, I), D) / int(RAY))), 834914501982721779955648188);

        assertEq(rmul(rpow(spot.way(), SPY, RAY), spot.par()), 1197727463600522286967648980);
    }

    function test_major_positive_deviations() public {
        major_one_side_deviations(1, 2);

        assertEq(vox.site(), -1);

        assertEq(spot.way(), 999999996611890187221936158);
        assertEq(spot.rho(), now);
        assertEq(spot.par(), 999999975378377593818819806);
        assertEq(vox.fix(), ray(1.015 ether));

        assertEq(vox.cron(1), int(ray(0.01 ether)));
        assertEq(vox.cron(2), int(ray(0.020 ether)));
        assertEq(vox.cron(3), int(ray(0.030 ether)));
        assertEq(vox.cron(4), int(ray(0.040 ether)));
        assertEq(vox.cron(5), int(ray(0.035 ether)));
        assertEq(vox.cron(6), int(ray(0.030 ether)));

        assertEq(vox.fat(), int(ray(0.105 ether)));
        assertEq(int(vox.thin()), int(60000057219766193509306514));
        assertEq(vox.fit(), int(165000057219766193509306514));

        (int P, int I , int D, uint pid) = vox.full(vox.fix(), spot.par(), vox.site(), vox.road());

        assertEq(P, -15000024621622406181180194);
        assertEq(I, -165000057219766193509306514);
        assertEq(D, 571429116378725652469585847);
        assertEq(pid, 1112764468026088748374379377);
        assertEq(int(ray(1 ether)) + P + I, 819999918158611400309513292);
    }

    function test_zig_zag_deviations() public {
        zig_zag_deviations(-1, 20);

        assertEq(vox.site(), 0);

        assertEq(spot.way(), ray(1 ether));
        assertEq(spot.rho(), now);
        assertEq(spot.par(), ray(1 ether));
        assertEq(vox.fix(), ray(0.9 ether));

        assertEq(vox.cron(1), int(-ray(0.1 ether)));
        assertEq(vox.cron(2), int(ray(0.1 ether)));
        assertEq(vox.cron(3), int(-ray(0.1 ether)));
        assertEq(vox.cron(4), int(ray(0.1 ether)));
        assertEq(vox.cron(5), int(-ray(0.1 ether)));
        assertEq(vox.cron(6), int(ray(0.1 ether)));
        assertEq(vox.cron(7), int(-ray(0.1 ether)));
        assertEq(vox.cron(8), int(ray(0.1 ether)));
        assertEq(vox.cron(9), int(-ray(0.1 ether)));
        assertEq(vox.cron(10), int(ray(0.1 ether)));
        assertEq(vox.cron(11), int(-ray(0.1 ether)));
        assertEq(vox.cron(12), int(ray(0.1 ether)));

        assertEq(vox.fat(), int(ray(0.1 ether)));
        assertEq(int(vox.thin()), int(-ray(0.1 ether)));
        assertEq(vox.fit(), 0);

        (int P, int I , int D, uint pid) = vox.full(spot.par(), vox.fix(), vox.site(), vox.road());

        assertEq(P, 0);
        assertEq(I, 0);
        assertEq(D, int(-ray(1 ether)));
        assertEq(pid, ray(1 ether));
    }

    function test_sudden_big_negative_deviation() public {
        sudden_big_deviation(1, 20);

        assertEq(vox.site(), 1);

        assertEq(spot.way(), 1000000026434345167789949754);
        assertEq(spot.par(), ray(1 ether));
        assertEq(vox.fix(), 905833333333333331000000000);

        assertEq(vox.cron(1), int(833333333333333000000000));
        assertEq(vox.cron(2), int(1666666666666666000000000));
        assertEq(vox.cron(3), int(2499999999999999000000000));
        assertEq(vox.cron(4), int(3333333333333332000000000));
        assertEq(vox.cron(5), int(4166666666666665000000000));
        assertEq(vox.cron(6), int(4999999999999998000000000));
        assertEq(vox.cron(7), int(5833333333333331000000000));
        assertEq(vox.cron(8), int(-94166666666666669000000000));

        assertEq(vox.fat(), int(9999999999999996000000000));
        assertEq(int(vox.thin()), int(-83333333333333340000000000));
        assertEq(vox.fit(), -73333333333333344000000000);

        // Push more prices in order to test reaction to big deviation
        hevm.warp(now + 1 seconds);
        stableFeed.poke(1.005 ether);
        vox.back();

        assertEq(spot.way(), 1000000011380137982592083044);
        assertEq(spot.par(), 1000000026434345167789949754);

        hevm.warp(now + 1 seconds);
        stableFeed.poke(1.005 ether);
        vox.back();

        assertEq(spot.way(), 1000000009593222078580520730);
        assertEq(spot.par(), 1000000037814483451208528286);

        hevm.warp(now + 1 seconds);
        stableFeed.poke(1.005 ether);
        vox.back();

        assertEq(spot.way(), 1000000000201292473137013550);
        assertEq(spot.par(), 1000000047407705892551786550);

        hevm.warp(now + 1 seconds);
        stableFeed.poke(1.005 ether);
        vox.back();

        assertEq(spot.way(), 1000000000201292131336386858);
        assertEq(spot.par(), 1000000047608998375231614464);

        hevm.warp(now + 1 seconds);
        stableFeed.poke(1.005 ether);
        vox.back();

        assertEq(spot.way(), 1000000000202409475952048060);
        assertEq(spot.par(), 1000000047810290516151318075);

        hevm.warp(now + 1 seconds);
        stableFeed.poke(1.005 ether);
        vox.back();

        assertEq(spot.way(), 1000000000000000000000000000);
        assertEq(spot.par(), 1000000048012700001780621983);
    }

    function test_sudden_big_positive_deviation() public {
        sudden_big_deviation(-1, 20);

        assertEq(vox.site(), -1);
        assertEq(vox.road(), -1);

        assertEq(spot.way(), RAY);
        assertEq(spot.par(), ray(1 ether));
        assertEq(vox.fix(), 1094166666666666669000000000);

        assertEq(vox.cron(1), -int(833333333333333000000000));
        assertEq(vox.cron(2), -int(1666666666666666000000000));
        assertEq(vox.cron(3), -int(2499999999999999000000000));
        assertEq(vox.cron(4), -int(3333333333333332000000000));
        assertEq(vox.cron(5), -int(4166666666666665000000000));
        assertEq(vox.cron(6), -int(4999999999999998000000000));
        assertEq(vox.cron(7), -int(5833333333333331000000000));
        assertEq(vox.cron(8), int(94166666666666669000000000));

        assertEq(vox.fat(), int(-9999999999999996000000000));
        assertEq(int(vox.thin()), int(83333333333333340000000000));
        assertEq(vox.fit(), 73333333333333344000000000);

        // Push more prices in order to test reaction to big deviation
        hevm.warp(now + 1 seconds);
        stableFeed.poke(0.995 ether);
        vox.back();

        assertEq(spot.way(), 999999981676929878779197921);
        assertEq(spot.par(), 1000000000000000000000000000);

        hevm.warp(now + 1 seconds);
        stableFeed.poke(0.995 ether);
        vox.back();

        assertEq(spot.way(), 999999985846020406211282846);
        assertEq(spot.par(), 999999981676929878779197921);

        hevm.warp(now + 1 seconds);
        stableFeed.poke(0.995 ether);
        vox.back();

        assertEq(spot.way(), 999999999636432819784832491);
        assertEq(spot.par(), 999999967522950544334841358);

        hevm.warp(now + 1 seconds);
        stableFeed.poke(0.995 ether);
        vox.back();

        assertEq(spot.way(), 999999999636433428513951286);
        assertEq(spot.par(), 999999967159383375927263141);
    }

    // TODO: simplify test
    function test_deviation_waves() public {
        monotonous_deviations(1 ether, -1, 5);

        assertEq(vox.site(), 1);
        assertEq(vox.road(), 1);

        assertEq(spot.par(), 1000000029527503745421310299);
        assertEq(vox.fix(), 825000000000000000000000000);
        assertEq(spot.way(), 1000000029370913805045019395);

        assertEq(vox.thin(), -450000029527503745421310299);
        assertEq(vox.fat(), -225000000000000000000000000);
        assertEq(vox.fit(), -675000029527503745421310299);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.poke(1.006 ether);
        vox.back();

        assertEq(vox.site(), 1);
        assertEq(vox.road(), -1);

        assertEq(spot.par(), 1000000058898418417716097078);
        assertEq(vox.fix(), 1006000000000000000000000000);
        assertEq(spot.way(), 1000000015724819266824747955);

        assertEq(vox.thin(), -319000088425922163137407377);
        assertEq(vox.fat(), -300000000000000000000000000);
        assertEq(vox.fit(), -619000088425922163137407377);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.poke(1.035 ether);
        vox.back();

        assertEq(vox.cron(9), int(34999925376761389292170247));

        assertEq(vox.site(), 1);
        assertEq(vox.road(), -1);

        assertEq(spot.par(), 1000000074623238610707829753);
        assertEq(vox.fix(), 1035000000000000000000000000);
        assertEq(spot.way(), 1000000003870787652425589541);

        assertEq(vox.thin(), -134000163049160773845237130);
        assertEq(vox.fat(), -375000000000000000000000000);
        assertEq(vox.fit(), -509000163049160773845237130);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.poke(1.075 ether);
        vox.back();

        assertEq(vox.cron(10), int(74999921505973448015870108));

        assertEq(spot.par(), 1000000078494026551984129892);
        assertEq(vox.fix(), 1075000000000000000000000000);

        assertEq(spot.way(), 1000000000242001321791172359);

        assertEq(vox.thin(), 115999787984316419591943277);
        assertEq(vox.fat(), -450000029527503745421310299);
        assertEq(vox.fit(), -334000241543187325829367022);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.poke(1.075 ether);
        vox.back();

        assertEq(vox.cron(11), int(74999921263972107229039571));

        assertEq(spot.par(), 1000000078736027892770960429);
        assertEq(vox.fix(), 1075000000000000000000000000);
        assertEq(spot.way(), 1000000001180750080709243029);

        assertEq(vox.thin(), 184999768146706944537079926);
        assertEq(vox.fat(), -319000088425922163137407377);
        assertEq(vox.fit(), -134000320279215218600327451);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.poke(1.075 ether);
        vox.back();

        assertEq(vox.cron(12), int(74999920083221933552225253));

        assertEq(spot.par(), 1000000079916778066447774747);
        assertEq(vox.fix(), 1075000000000000000000000000);
        assertEq(spot.way(), 999999990482702392239753688);

        assertEq(vox.thin(), 224999762853167488797134932);
        assertEq(vox.fat(), -134000163049160773845237130);
        assertEq(vox.fit(), 90999599804006714951897802);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.poke(0.990 ether);
        vox.back();

        assertEq(vox.cron(13), int(-10000070399479698095767723));

        assertEq(spot.par(), 1000000070399479698095767723);
        assertEq(vox.fix(), ray(0.990 ether));
        assertEq(spot.way(), 999999988830212436175464411);

        assertEq(vox.thin(), 139999770947714342685497101);
        assertEq(vox.fat(), 115999787984316419591943277);
        assertEq(vox.fit(), 255999558932030762277440378);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.poke(0.995 ether);
        vox.back();

        assertEq(vox.cron(14), int(-5000059229691347923999302));

        assertEq(spot.par(), 1000000059229691347923999302);
        assertEq(vox.fix(), ray(0.995 ether));
        assertEq(spot.way(), 999999997430434422546000846);

        assertEq(vox.thin(), 59999790454050887532458228);
        assertEq(vox.fat(), 184999768146706944537079926);
        assertEq(vox.fit(), 244999558600757832069538154);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.poke(0.995 ether);
        vox.back();

        assertEq(vox.cron(15), int(-5000056660125618275424097));

        assertEq(spot.par(), 1000000056660125618275424097);
        assertEq(vox.fix(), ray(0.995 ether));
        assertEq(spot.way(), 999999999431194701844308122);

        assertEq(vox.thin(), -20000186289296664295191122);
        assertEq(vox.fat(), 224999762853167488797134932);
        assertEq(vox.fit(), 204999576563870824501943810);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.poke(0.995 ether);
        vox.back();

        assertEq(vox.cron(16), int(-5000056091320287891152573));

        assertEq(spot.par(), 1000000056091320287891152573);
        assertEq(vox.fix(), ray(0.995 ether));
        assertEq(spot.way(), 999999999589655264660387835);

        assertEq(vox.thin(), -15000171981137254090575972);
        assertEq(vox.fat(), 139999770947714342685497101);
        assertEq(vox.fit(), 124999598966577088594921129);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.poke(0.985 ether);
        vox.back();

        assertEq(vox.cron(17), int(-15000055680975529534762429));

        assertEq(spot.par(), 1000000055680975529534762429);
        assertEq(vox.fix(), ray(0.985 ether));
        assertEq(spot.way(), 999999999734647610462053644);

        assertEq(vox.thin(), -25000168432421435701339099);
        assertEq(vox.fat(), 59999790454050887532458228);
        assertEq(vox.fit(), 34999622021629451831119129);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.poke(0.985 ether);
        vox.back();

        assertEq(vox.cron(18), int(-15000055415623125221736164));

        assertEq(spot.par(), 1000000055415623125221736164);
        assertEq(vox.fix(), ray(0.985 ether));
        assertEq(spot.way(), 1000000003237738200330359969);

        assertEq(vox.thin(), -35000167187918942647651166);
        assertEq(vox.fat(), -20000186289296664295191122);
        assertEq(vox.fit(), -55000353477215606942842288);
    }

    function test_mixed_deviations() public {
        sudden_big_deviation(1, 30);
        sudden_big_deviation(-1, 40);
        major_one_side_deviations(1, 4);
        major_one_side_deviations(-1, 3);
        zig_zag_deviations(-1, 20);
    }
}
