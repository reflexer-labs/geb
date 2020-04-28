/// RedemptionRateSetter.t.sol

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

import {CDPEngine} from '../CDPEngine.sol';
import '../RedemptionRateSetter.sol';
import {CollateralJoin} from '../BasicTokenAdapters.sol';
import {OracleRelayer} from '../OracleRelayer.sol';

contract Feed {
    bytes32 public price;
    bool public validPrice;
    uint public lastUpdateTime;
    constructor(uint256 price_, bool validPrice_) public {
        price = bytes32(price_);
        validPrice = validPrice_;
        lastUpdateTime = now;
    }
    function updateCollateralPrice(uint256 price_) external {
        price = bytes32(price_);
        lastUpdateTime = now;
    }
    function getPriceWithValidity() external view returns (bytes32, bool) {
        return (price, validPrice);
    }
}

contract Hevm {
    function warp(uint256) public;
}

contract RedemptionRateSetterOneTest is DSTest {
    CDPEngine cdpEngine;
    OracleRelayer oracleRelayer;
    RedemptionRateSetterOne redemptionRateSetter;
    Feed stableFeed;

    CollateralJoin collateralType;
    DSToken gold;
    Feed goldFeed;

    Hevm hevm;

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

        cdpEngine = new CDPEngine();
        oracleRelayer = new OracleRelayer(address(cdpEngine));
        cdpEngine.addAuthorization(address(oracleRelayer));

        gold = new DSToken("GEM");
        gold.mint(1000 ether);
        cdpEngine.initializeCollateralType("gold");
        goldFeed = new Feed(1 ether, true);
        oracleRelayer.modifyParameters("gold", "orcl", address(goldFeed));
        oracleRelayer.modifyParameters("gold", "liquidationCRatio", 1000000000000000000000000000);
        oracleRelayer.modifyParameters("gold", "safetyCRatio", 1000000000000000000000000000);
        oracleRelayer.updateCollateralPrice("gold");
        collateralType = new CollateralJoin(address(cdpEngine), "gold", address(gold));

        cdpEngine.modifyParameters("gold", "debtCeiling", rad(1000 ether));
        cdpEngine.modifyParameters("globalDebtCeiling", rad(1000 ether));

        gold.approve(address(collateralType));
        gold.approve(address(cdpEngine));

        cdpEngine.addAuthorization(address(collateralType));

        collateralType.join(address(this), 1000 ether);

        stableFeed = new Feed(1 ether, true);

        redemptionRateSetter = new RedemptionRateSetterOne(address(oracleRelayer));
        redemptionRateSetter.modifyParameters("orcl", address(stableFeed));
        redemptionRateSetter.modifyParameters("noiseBarrier", 5 * 10 ** 24);

        oracleRelayer.addAuthorization(address(redemptionRateSetter));

        self = address(this);

        cdpEngine.modifyCDPCollateralization("gold", self, self, self, 10 ether, 5 ether);
    }

    function test_setup() public {
        assertTrue(address(redemptionRateSetter.oracleRelayer()) == address(oracleRelayer));
    }
    function test_no_deviation() public {
        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(1 ether));
        assertEq(oracleRelayer.redemptionRate(), ray(1 ether));
    }
    function testFail_update_rate_same_timestamp() public {
        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();
        redemptionRateSetter.updateRedemptionRate();
    }
    function test_redemptionPrice_bigger_than_latestMarketPrice() public {
        oracleRelayer.modifyParameters("redemptionPrice", ray(15 ether));
        stableFeed.updateCollateralPrice(8.9587 ether);
        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(8.9587 ether));
        assertEq(oracleRelayer.redemptionPrice(), ray(15 ether));
        assertEq(oracleRelayer.redemptionRate(), 1000000016344022011022743085);

        hevm.warp(now + SPY * 1 seconds);

        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionPrice(), 25115251096699297888487171340);
        assertEq(oracleRelayer.redemptionRate(), 1000000032688044289172541667);

        assertEq(rmul(rpow(1000000032688044289172541667, SPY, RAY), ray(8.9587 ether)), 25115251096699297887771668223);
    }
    function test_redemptionPrice_smaller_than_latestMarketPrice() public {
        oracleRelayer.modifyParameters("redemptionPrice", ray(5.521 ether));
        stableFeed.updateCollateralPrice(11.34 ether);
        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(11.34 ether));
        assertEq(oracleRelayer.redemptionPrice(), ray(5.521 ether));
        assertEq(oracleRelayer.redemptionRate(), 999999977176011440519000573);
        assertEq(rmul(rpow(999999977176011440519000573, SPY, RAY), ray(11.34 ether)), 5520999909299969641079989150);
    }
    function test_back_negative_deviation() public {
        stableFeed.updateCollateralPrice(0.995 ether);
        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(0.995 ether));
        assertEq(oracleRelayer.redemptionPrice(), ray(1 ether));
        assertEq(oracleRelayer.redemptionRate(), 1000000000158946658547141217);
        hevm.warp(now + SPY * 1 seconds);
        redemptionRateSetter.updateRedemptionRate();
        assertEq(oracleRelayer.redemptionPrice(), 1005025125628140703501565638);
    }
    function test_back_positive_deviation() public {
        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(1.1 ether);
        redemptionRateSetter.updateRedemptionRate();
        hevm.warp(now + SPY * 1 seconds);
        stableFeed.updateCollateralPrice(1.1 ether);
        redemptionRateSetter.updateRedemptionRate();
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(1.1 ether));
        assertEq(oracleRelayer.redemptionPrice(), 909090908829042986952227407);
        assertEq(oracleRelayer.redemptionRate(), 999999993955468021537041335);
        hevm.warp(now + (SPY / 100) * 1 seconds);
        redemptionRateSetter.updateRedemptionRate();
        assertEq(oracleRelayer.redemptionPrice(), 907359647049325613469016272);
    }
    function test_integralSensitivity_positive_deviation() public {
        redemptionRateSetter.modifyParameters("integralSensitivity", 0.005 ether);
        stableFeed.updateCollateralPrice(0.995 ether);
        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();
        assertEq(redemptionRateSetter.accruedTimeSinceDeviated(), 0);
        assertEq(redemptionRateSetter.latestDeviationType(), 1);

        hevm.warp(now + SPY * 1 seconds);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(redemptionRateSetter.accruedTimeSinceDeviated(), 31536000);
        assertEq(redemptionRateSetter.latestDeviationType(), 1);
        assertEq(oracleRelayer.redemptionPrice(), 1005025125628140703501565638);

        hevm.warp(now + SPY * 1 seconds);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(redemptionRateSetter.accruedTimeSinceDeviated(), 63072000);
        assertEq(redemptionRateSetter.latestDeviationType(), 1);
        assertEq(oracleRelayer.redemptionPrice(), 1015309731802874375366504590);
    }

    function test_integralSensitivity_negative_deviation() public {
        // First positive deviation
        redemptionRateSetter.modifyParameters("integralSensitivity", 0.005 ether);
        stableFeed.updateCollateralPrice(0.995 ether);
        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();
        assertEq(redemptionRateSetter.accruedTimeSinceDeviated(), 0);
        assertEq(redemptionRateSetter.latestDeviationType(), 1);

        hevm.warp(now + SPY * 10 seconds);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionPrice(), 1051402953210356466797473310);

        // Then negative
        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(1.11 ether);
        redemptionRateSetter.updateRedemptionRate();
        assertEq(redemptionRateSetter.accruedTimeSinceDeviated(), 315360000);
        assertEq(redemptionRateSetter.latestDeviationType(), -1);

        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();

        hevm.warp(now + (SPY / 10 - 1) * 1 seconds);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(redemptionRateSetter.accruedTimeSinceDeviated(), 318513600);
        assertEq(redemptionRateSetter.latestDeviationType(), -1);
        assertEq(oracleRelayer.redemptionPrice(), 1045560092677402968993800002);

        hevm.warp(now + (SPY / 10) * 1 seconds);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(redemptionRateSetter.accruedTimeSinceDeviated(), 321667200);
        assertEq(redemptionRateSetter.latestDeviationType(), -1);
        assertEq(oracleRelayer.redemptionPrice(), 1039169760169358078599943151);
    }

    function test_rates_with_non_null_proportional_sensitivity() public {
        redemptionRateSetter.modifyParameters("proportionalSensitivity", ray(2 ether));

        stableFeed.updateCollateralPrice(0.995 ether);
        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionRate(), 1000000000317100562410225509);

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(1.006 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionRate(), 999999999621747519118189746);
    }

    function test_mix_default_with_computed_rates() public {
        // Positive default rate
        redemptionRateSetter.modifyParameters("defaultRedemptionRate", 1000000000158946658547141217);

        stableFeed.updateCollateralPrice(0.995 ether);
        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionPrice(), ray(1 ether));
        assertEq(oracleRelayer.redemptionRate(), 1000000000317893317094282434);

        stableFeed.updateCollateralPrice(1.006 ether);
        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionPrice(), 1000000000317893317094282434);
        assertEq(oracleRelayer.redemptionRate(), 999999999810309761535340024);

        // Negative default rate
        redemptionRateSetter.modifyParameters("defaultRedemptionRate", 999999999841846096162053742);

        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionPrice(), 1000000000128203078569321198);
        assertEq(oracleRelayer.redemptionRate(), 999999999652155851682355762);

        stableFeed.updateCollateralPrice(0.992 ether);
        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionPrice(), 999999999780358930207082269);
        assertEq(oracleRelayer.redemptionRate(), 1000000000254698486765794018);

        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionPrice(), 1000000000035057416916934038);
        assertEq(oracleRelayer.redemptionRate(), 1000000000254698494842230053);
        assertEq(rmul(rpow(1000000000254698494842230053, SPY, RAY), ray(0.992 ether)), 1000000000035057416882104091);
    }

    function test_custom_default_per_second_rate() public {
        redemptionRateSetter.modifyParameters("defaultRedemptionRate", ray(1 ether) + 1);
        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();
        assertEq(oracleRelayer.redemptionPrice(), ray(1 ether));
        hevm.warp(now + 1 seconds);
        redemptionRateSetter.updateRedemptionRate();
        assertEq(oracleRelayer.redemptionPrice(), ray(1 ether) + 1);
    }
}

contract RedemptionRateSetterTwoTest is DSTest {
    CDPEngine cdpEngine;
    OracleRelayer oracleRelayer;
    RedemptionRateSetterTwo redemptionRateSetter;
    Feed    stableFeed;

    CollateralJoin collateralA;
    DSToken gold;
    Feed    goldFeed;

    Hevm    hevm;

    address self;

    uint256 oldLength  = 3;
    uint256 integralLength = 6;
    uint256 rawLength  = 3;

    uint256 noiseBarrier = 0.005 ether;

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

        cdpEngine = new CDPEngine();
        oracleRelayer = new OracleRelayer(address(cdpEngine));
        cdpEngine.addAuthorization(address(oracleRelayer));

        gold = new DSToken("GEM");
        gold.mint(1000 ether);
        cdpEngine.initializeCollateralType("gold");
        goldFeed = new Feed(1 ether, true);
        oracleRelayer.modifyParameters("gold", "orcl", address(goldFeed));
        oracleRelayer.modifyParameters("gold", "liquidationCRatio", 1000000000000000000000000000);
        oracleRelayer.modifyParameters("gold", "safetyCRatio", 1000000000000000000000000000);
        oracleRelayer.updateCollateralPrice("gold");
        collateralA = new CollateralJoin(address(cdpEngine), "gold", address(gold));

        cdpEngine.modifyParameters("gold", "debtCeiling", rad(1000 ether));
        cdpEngine.modifyParameters("globalDebtCeiling", rad(1000 ether));

        gold.approve(address(collateralA));
        gold.approve(address(cdpEngine));

        cdpEngine.addAuthorization(address(collateralA));

        collateralA.join(address(this), 1000 ether);

        stableFeed = new Feed(1 ether, true);

        redemptionRateSetter = new RedemptionRateSetterTwo(address(oracleRelayer), oldLength, integralLength, rawLength);
        redemptionRateSetter.modifyParameters("orcl", address(stableFeed));
        redemptionRateSetter.modifyParameters("noiseBarrier", ray(noiseBarrier));

        oracleRelayer.addAuthorization(address(redemptionRateSetter));

        self = address(this);

        cdpEngine.modifyCDPCollateralization("gold", self, self, self, 10 ether, 5 ether);
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
    function monotonous_deviations(uint start, int side_, uint deviationMultiplier) internal {
        uint price = start;
        for (uint i = 0; i <= integralLength; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_, noiseBarrier * deviationMultiplier));
          stableFeed.updateCollateralPrice(price);
          redemptionRateSetter.updateRedemptionRate();
        }
    }
    function major_one_side_deviations(int side_, uint deviationMultiplier) internal {
        uint price = 1 ether; uint i;
        for (i = 0; i <= integralLength / 2; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_, noiseBarrier * deviationMultiplier));
          stableFeed.updateCollateralPrice(price);
          redemptionRateSetter.updateRedemptionRate();
        }
        for (i = integralLength / 2; i <= integralLength + 1; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_ * int(-1), noiseBarrier));
          stableFeed.updateCollateralPrice(price);
          redemptionRateSetter.updateRedemptionRate();
        }
    }
    function zig_zag_deviations(int side_, uint deviationMultiplier) internal {
        uint i;
        uint price;
        int aux = side_;
        for (i = 0; i <= integralLength * 2; i++) {
          hevm.warp(now + 1 seconds);
          price = add(uint(1 ether), mul(aux, noiseBarrier * deviationMultiplier));
          stableFeed.updateCollateralPrice(price);
          redemptionRateSetter.updateRedemptionRate();
          aux = -aux;
        }
    }
    function subtle_deviations(int side_) internal {
        uint price = 1 ether;
        uint i;
        for (i = 0; i <= integralLength + 5; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_, noiseBarrier / integralLength));
          stableFeed.updateCollateralPrice(price);
          redemptionRateSetter.updateRedemptionRate();
        }
    }
    function sudden_big_deviation(int side_, uint deviationMultiplier) internal {
        uint price = 1 ether;
        uint i;
        for (i = 0; i <= integralLength; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_, noiseBarrier / integralLength));
          stableFeed.updateCollateralPrice(price);
          redemptionRateSetter.updateRedemptionRate();
        }

        hevm.warp(now + 1 seconds);
        price = add(price, mul(side_ * int(-1), noiseBarrier * deviationMultiplier));

        stableFeed.updateCollateralPrice(price);
        redemptionRateSetter.updateRedemptionRate();
    }

    function test_setup() public {
        assertTrue(address(redemptionRateSetter.oracleRelayer()) == address(oracleRelayer));
    }
    function test_pid_increasing_deviations() public {
        monotonous_deviations(1 ether, int(1), 1);

        assertEq(redemptionRateSetter.deviationHistory(1), int(ray(0.005 ether)));
        assertEq(redemptionRateSetter.deviationHistory(2), int(ray(0.01 ether)));
        assertEq(redemptionRateSetter.deviationHistory(3), int(ray(0.015 ether)));
        assertEq(redemptionRateSetter.deviationHistory(4), int(ray(0.02 ether)));
        assertEq(redemptionRateSetter.deviationHistory(5), int(ray(0.025 ether)));
        assertEq(redemptionRateSetter.deviationHistory(6), int(ray(0.03 ether)));

        assertEq(redemptionRateSetter.trendDeviationType(), -1);
        assertEq(oracleRelayer.redemptionRate(), 999999987371733779393155516);
        assertEq(redemptionRateSetter.lastUpdateTime(), now);
        assertEq(oracleRelayer.redemptionPrice(), 999999987411027217746836585);
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(1.035 ether));

        (int P, int I , int D, uint pid)
          = redemptionRateSetter.calculatePIDRate(
              redemptionRateSetter.latestMarketPrice(),
              oracleRelayer.redemptionPrice(),
              redemptionRateSetter.trendDeviationType(),
              redemptionRateSetter.latestDeviationType()
          );

        assertEq(P, -35000012588972782253163415);
        assertEq(I, -135000012588972782253163415);
        assertEq(D, 2000000279754950716736964777);
        assertEq(pid, 1489208842898923378006058609);

        assertTrue(redemptionRateSetter.latestMarketPrice() > oracleRelayer.redemptionPrice());
        assertEq(mul(add(P, I), D) / int(RAY), -340000097914239794512858219);
        assertEq(
          add(redemptionRateSetter.latestMarketPrice(), (mul(add(P, I), D) / int(RAY))),
          694999902085760205487141781
        );
        assertEq(
          mul(redemptionRateSetter.latestMarketPrice(), RAY) / add(redemptionRateSetter.latestMarketPrice(),
          (mul(add(P, I), D) / int(RAY))), 1489208842898923378006058609
        );

        assertEq(
          rmul(rpow(oracleRelayer.redemptionRate(), SPY, RAY), oracleRelayer.redemptionPrice()),
          671497478107411469930891270
        );
    }
    function test_pid_decreasing_deviations() public {
        monotonous_deviations(1 ether, int(-1), 1);

        assertEq(redemptionRateSetter.deviationHistory(1), int(-ray(0.005 ether)));
        assertEq(redemptionRateSetter.deviationHistory(2), int(-ray(0.01 ether)));
        assertEq(redemptionRateSetter.deviationHistory(3), int(-ray(0.015 ether)));
        assertEq(redemptionRateSetter.deviationHistory(4), int(-ray(0.02 ether)));
        assertEq(redemptionRateSetter.deviationHistory(5), int(-ray(0.025 ether)));
        assertEq(redemptionRateSetter.deviationHistory(6), int(-ray(0.03 ether)));

        assertEq(redemptionRateSetter.trendDeviationType(), 1);
        assertEq(oracleRelayer.redemptionRate(), 1000000008441244421221367546);
        assertEq(redemptionRateSetter.lastUpdateTime(), now);
        assertEq(oracleRelayer.redemptionPrice(), 1000000008501931700174301437);
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(0.965 ether));

        (int P, int I , int D, uint pid) = redemptionRateSetter.calculatePIDRate(oracleRelayer.redemptionPrice(), redemptionRateSetter.latestMarketPrice(), redemptionRateSetter.trendDeviationType(), redemptionRateSetter.latestDeviationType());

        assertEq(P, 35000008501931700174301437);
        assertEq(I, 135000008501931700174301437);
        assertEq(D, 2000000188931815559428920822);
        assertEq(pid, 1305000055031117321772641810);

        assertTrue(oracleRelayer.redemptionPrice() > redemptionRateSetter.latestMarketPrice());
        assertEq(mul(add(P, I), D) / int(RAY), 340000066126138658370906040);
        assertEq(add(redemptionRateSetter.latestMarketPrice(), (mul(add(P, I), D) / int(RAY))), 1305000066126138658370906040);
        assertEq(add(redemptionRateSetter.latestMarketPrice(), (mul(add(P, I), D) / int(RAY))) * RAY / oracleRelayer.redemptionPrice(), 1305000055031117321772641810);

        assertEq(rmul(rpow(oracleRelayer.redemptionRate(), SPY, RAY), oracleRelayer.redemptionPrice()), 1305000066126138658335048834);
    }
    function test_major_negative_deviations() public {
        major_one_side_deviations(-1, 3);

        assertEq(redemptionRateSetter.deviationHistory(1), int(-ray(0.015 ether)));
        assertEq(redemptionRateSetter.deviationHistory(2), int(-ray(0.03 ether)));
        assertEq(redemptionRateSetter.deviationHistory(3), int(-ray(0.045 ether)));
        assertEq(redemptionRateSetter.deviationHistory(4), int(-ray(0.06 ether)));
        assertEq(redemptionRateSetter.deviationHistory(5), int(-ray(0.055 ether)));
        assertEq(redemptionRateSetter.deviationHistory(6), int(-ray(0.05 ether)));

        assertEq(redemptionRateSetter.trendDeviationType(), 1);

        assertEq(oracleRelayer.redemptionRate(), 1000000005721269429381730438);
        assertEq(redemptionRateSetter.lastUpdateTime(), now);
        assertEq(oracleRelayer.redemptionPrice(), 1000000028783058593493768971);
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(0.965 ether));

        assertEq(redemptionRateSetter.oldAccumulator(), int(-ray(0.165 ether)));
        assertEq(int(redemptionRateSetter.rawAccumulator()), int(-120000063727530115134064360));
        assertEq(redemptionRateSetter.integralAccumulator(), int(-285000063727530115134064360));

        (int P, int I , int D, uint pid) = redemptionRateSetter.calculatePIDRate(oracleRelayer.redemptionPrice(), redemptionRateSetter.latestMarketPrice(), redemptionRateSetter.trendDeviationType(), redemptionRateSetter.latestDeviationType());

        assertTrue(oracleRelayer.redemptionPrice() > redemptionRateSetter.latestMarketPrice());
        assertEq(mul(add(P, I), D) / int(RAY), 232727463600522286967081774);
        assertEq(add(redemptionRateSetter.latestMarketPrice(), (mul(add(P, I), D) / int(RAY))), 1197727463600522286967081774);
        assertEq(mul(oracleRelayer.redemptionPrice(), RAY) / add(redemptionRateSetter.latestMarketPrice(), (mul(add(P, I), D) / int(RAY))), 834914501982721779955648188);

        assertEq(rmul(rpow(oracleRelayer.redemptionRate(), SPY, RAY), oracleRelayer.redemptionPrice()), 1197727463600522286967648980);
    }
    function test_major_positive_deviations() public {
        major_one_side_deviations(1, 2);

        assertEq(redemptionRateSetter.trendDeviationType(), -1);

        assertEq(oracleRelayer.redemptionRate(), 999999996611890187221936158);
        assertEq(redemptionRateSetter.lastUpdateTime(), now);
        assertEq(oracleRelayer.redemptionPrice(), 999999975378377593818819806);
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(1.015 ether));

        assertEq(redemptionRateSetter.deviationHistory(1), int(ray(0.01 ether)));
        assertEq(redemptionRateSetter.deviationHistory(2), int(ray(0.020 ether)));
        assertEq(redemptionRateSetter.deviationHistory(3), int(ray(0.030 ether)));
        assertEq(redemptionRateSetter.deviationHistory(4), int(ray(0.040 ether)));
        assertEq(redemptionRateSetter.deviationHistory(5), int(ray(0.035 ether)));
        assertEq(redemptionRateSetter.deviationHistory(6), int(ray(0.030 ether)));

        assertEq(redemptionRateSetter.oldAccumulator(), int(ray(0.105 ether)));
        assertEq(int(redemptionRateSetter.rawAccumulator()), int(60000057219766193509306514));
        assertEq(redemptionRateSetter.integralAccumulator(), int(165000057219766193509306514));

        (int P, int I , int D, uint pid) = redemptionRateSetter.calculatePIDRate(redemptionRateSetter.latestMarketPrice(), oracleRelayer.redemptionPrice(), redemptionRateSetter.trendDeviationType(), redemptionRateSetter.latestDeviationType());

        assertEq(P, -15000024621622406181180194);
        assertEq(I, -165000057219766193509306514);
        assertEq(D, 571429116378725652469585847);
        assertEq(pid, 1112764468026088748374379377);
        assertEq(int(ray(1 ether)) + P + I, 819999918158611400309513292);
    }
    function test_zig_zag_deviations() public {
        zig_zag_deviations(-1, 20);

        assertEq(redemptionRateSetter.trendDeviationType(), 0);

        assertEq(oracleRelayer.redemptionRate(), ray(1 ether));
        assertEq(redemptionRateSetter.lastUpdateTime(), now);
        assertEq(oracleRelayer.redemptionPrice(), ray(1 ether));
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(0.9 ether));

        assertEq(redemptionRateSetter.deviationHistory(1), int(-ray(0.1 ether)));
        assertEq(redemptionRateSetter.deviationHistory(2), int(ray(0.1 ether)));
        assertEq(redemptionRateSetter.deviationHistory(3), int(-ray(0.1 ether)));
        assertEq(redemptionRateSetter.deviationHistory(4), int(ray(0.1 ether)));
        assertEq(redemptionRateSetter.deviationHistory(5), int(-ray(0.1 ether)));
        assertEq(redemptionRateSetter.deviationHistory(6), int(ray(0.1 ether)));
        assertEq(redemptionRateSetter.deviationHistory(7), int(-ray(0.1 ether)));
        assertEq(redemptionRateSetter.deviationHistory(8), int(ray(0.1 ether)));
        assertEq(redemptionRateSetter.deviationHistory(9), int(-ray(0.1 ether)));
        assertEq(redemptionRateSetter.deviationHistory(10), int(ray(0.1 ether)));
        assertEq(redemptionRateSetter.deviationHistory(11), int(-ray(0.1 ether)));
        assertEq(redemptionRateSetter.deviationHistory(12), int(ray(0.1 ether)));

        assertEq(redemptionRateSetter.oldAccumulator(), int(ray(0.1 ether)));
        assertEq(int(redemptionRateSetter.rawAccumulator()), int(-ray(0.1 ether)));
        assertEq(redemptionRateSetter.integralAccumulator(), 0);

        (int P, int I , int D, uint pid) = redemptionRateSetter.calculatePIDRate(oracleRelayer.redemptionPrice(), redemptionRateSetter.latestMarketPrice(), redemptionRateSetter.trendDeviationType(), redemptionRateSetter.latestDeviationType());

        assertEq(P, 0);
        assertEq(I, 0);
        assertEq(D, int(-ray(1 ether)));
        assertEq(pid, ray(1 ether));
    }
    function test_sudden_big_negative_deviation() public {
        sudden_big_deviation(1, 20);

        assertEq(redemptionRateSetter.trendDeviationType(), 1);

        assertEq(oracleRelayer.redemptionRate(), 1000000026434345167789949754);
        assertEq(oracleRelayer.redemptionPrice(), ray(1 ether));
        assertEq(redemptionRateSetter.latestMarketPrice(), 905833333333333331000000000);

        assertEq(redemptionRateSetter.deviationHistory(1), int(833333333333333000000000));
        assertEq(redemptionRateSetter.deviationHistory(2), int(1666666666666666000000000));
        assertEq(redemptionRateSetter.deviationHistory(3), int(2499999999999999000000000));
        assertEq(redemptionRateSetter.deviationHistory(4), int(3333333333333332000000000));
        assertEq(redemptionRateSetter.deviationHistory(5), int(4166666666666665000000000));
        assertEq(redemptionRateSetter.deviationHistory(6), int(4999999999999998000000000));
        assertEq(redemptionRateSetter.deviationHistory(7), int(5833333333333331000000000));
        assertEq(redemptionRateSetter.deviationHistory(8), int(-94166666666666669000000000));

        assertEq(redemptionRateSetter.oldAccumulator(), int(9999999999999996000000000));
        assertEq(int(redemptionRateSetter.rawAccumulator()), int(-83333333333333340000000000));
        assertEq(redemptionRateSetter.integralAccumulator(), -73333333333333344000000000);

        // Push more prices in order to test reaction to big deviation
        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(1.005 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionRate(), 1000000011380137982592083044);
        assertEq(oracleRelayer.redemptionPrice(), 1000000026434345167789949754);

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(1.005 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionRate(), 1000000009593222078580520730);
        assertEq(oracleRelayer.redemptionPrice(), 1000000037814483451208528286);

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(1.005 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionRate(), 1000000000201292473137013550);
        assertEq(oracleRelayer.redemptionPrice(), 1000000047407705892551786550);

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(1.005 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionRate(), 1000000000201292131336386858);
        assertEq(oracleRelayer.redemptionPrice(), 1000000047608998375231614464);

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(1.005 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionRate(), 1000000000202409475952048060);
        assertEq(oracleRelayer.redemptionPrice(), 1000000047810290516151318075);

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(1.005 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionRate(), 1000000000000000000000000000);
        assertEq(oracleRelayer.redemptionPrice(), 1000000048012700001780621983);
    }
    function test_sudden_big_positive_deviation() public {
        sudden_big_deviation(-1, 20);

        assertEq(redemptionRateSetter.trendDeviationType(), -1);
        assertEq(redemptionRateSetter.latestDeviationType(), -1);

        assertEq(oracleRelayer.redemptionRate(), RAY);
        assertEq(oracleRelayer.redemptionPrice(), ray(1 ether));
        assertEq(redemptionRateSetter.latestMarketPrice(), 1094166666666666669000000000);

        assertEq(redemptionRateSetter.deviationHistory(1), -int(833333333333333000000000));
        assertEq(redemptionRateSetter.deviationHistory(2), -int(1666666666666666000000000));
        assertEq(redemptionRateSetter.deviationHistory(3), -int(2499999999999999000000000));
        assertEq(redemptionRateSetter.deviationHistory(4), -int(3333333333333332000000000));
        assertEq(redemptionRateSetter.deviationHistory(5), -int(4166666666666665000000000));
        assertEq(redemptionRateSetter.deviationHistory(6), -int(4999999999999998000000000));
        assertEq(redemptionRateSetter.deviationHistory(7), -int(5833333333333331000000000));
        assertEq(redemptionRateSetter.deviationHistory(8), int(94166666666666669000000000));

        assertEq(redemptionRateSetter.oldAccumulator(), int(-9999999999999996000000000));
        assertEq(int(redemptionRateSetter.rawAccumulator()), int(83333333333333340000000000));
        assertEq(redemptionRateSetter.integralAccumulator(), 73333333333333344000000000);

        // Push more prices in order to test reaction to big deviation
        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(0.995 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionRate(), 999999981676929878779197921);
        assertEq(oracleRelayer.redemptionPrice(), 1000000000000000000000000000);

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(0.995 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionRate(), 999999985846020406211282846);
        assertEq(oracleRelayer.redemptionPrice(), 999999981676929878779197921);

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(0.995 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionRate(), 999999999636432819784832491);
        assertEq(oracleRelayer.redemptionPrice(), 999999967522950544334841358);

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(0.995 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(oracleRelayer.redemptionRate(), 999999999636433428513951286);
        assertEq(oracleRelayer.redemptionPrice(), 999999967159383375927263141);
    }
    function test_deviation_waves() public {
        monotonous_deviations(1 ether, -1, 5);

        assertEq(redemptionRateSetter.trendDeviationType(), 1);
        assertEq(redemptionRateSetter.latestDeviationType(), 1);

        assertEq(oracleRelayer.redemptionPrice(), 1000000029527503745421310299);
        assertEq(redemptionRateSetter.latestMarketPrice(), 825000000000000000000000000);
        assertEq(oracleRelayer.redemptionRate(), 1000000029370913805045019395);

        assertEq(redemptionRateSetter.rawAccumulator(), -450000029527503745421310299);
        assertEq(redemptionRateSetter.oldAccumulator(), -225000000000000000000000000);
        assertEq(redemptionRateSetter.integralAccumulator(), -675000029527503745421310299);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(1.006 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(redemptionRateSetter.trendDeviationType(), 1);
        assertEq(redemptionRateSetter.latestDeviationType(), -1);

        assertEq(oracleRelayer.redemptionPrice(), 1000000058898418417716097078);
        assertEq(redemptionRateSetter.latestMarketPrice(), 1006000000000000000000000000);
        assertEq(oracleRelayer.redemptionRate(), 1000000015724819266824747955);

        assertEq(redemptionRateSetter.rawAccumulator(), -319000088425922163137407377);
        assertEq(redemptionRateSetter.oldAccumulator(), -300000000000000000000000000);
        assertEq(redemptionRateSetter.integralAccumulator(), -619000088425922163137407377);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(1.035 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(redemptionRateSetter.deviationHistory(9), int(34999925376761389292170247));

        assertEq(redemptionRateSetter.trendDeviationType(), 1);
        assertEq(redemptionRateSetter.latestDeviationType(), -1);

        assertEq(oracleRelayer.redemptionPrice(), 1000000074623238610707829753);
        assertEq(redemptionRateSetter.latestMarketPrice(), 1035000000000000000000000000);
        assertEq(oracleRelayer.redemptionRate(), 1000000003870787652425589541);

        assertEq(redemptionRateSetter.rawAccumulator(), -134000163049160773845237130);
        assertEq(redemptionRateSetter.oldAccumulator(), -375000000000000000000000000);
        assertEq(redemptionRateSetter.integralAccumulator(), -509000163049160773845237130);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(1.075 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(redemptionRateSetter.deviationHistory(10), int(74999921505973448015870108));

        assertEq(oracleRelayer.redemptionPrice(), 1000000078494026551984129892);
        assertEq(redemptionRateSetter.latestMarketPrice(), 1075000000000000000000000000);

        assertEq(oracleRelayer.redemptionRate(), 1000000000242001321791172359);

        assertEq(redemptionRateSetter.rawAccumulator(), 115999787984316419591943277);
        assertEq(redemptionRateSetter.oldAccumulator(), -450000029527503745421310299);
        assertEq(redemptionRateSetter.integralAccumulator(), -334000241543187325829367022);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(1.075 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(redemptionRateSetter.deviationHistory(11), int(74999921263972107229039571));

        assertEq(oracleRelayer.redemptionPrice(), 1000000078736027892770960429);
        assertEq(redemptionRateSetter.latestMarketPrice(), 1075000000000000000000000000);
        assertEq(oracleRelayer.redemptionRate(), 1000000001180750080709243029);

        assertEq(redemptionRateSetter.rawAccumulator(), 184999768146706944537079926);
        assertEq(redemptionRateSetter.oldAccumulator(), -319000088425922163137407377);
        assertEq(redemptionRateSetter.integralAccumulator(), -134000320279215218600327451);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(1.075 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(redemptionRateSetter.deviationHistory(12), int(74999920083221933552225253));

        assertEq(oracleRelayer.redemptionPrice(), 1000000079916778066447774747);
        assertEq(redemptionRateSetter.latestMarketPrice(), 1075000000000000000000000000);
        assertEq(oracleRelayer.redemptionRate(), 999999990482702392239753688);

        assertEq(redemptionRateSetter.rawAccumulator(), 224999762853167488797134932);
        assertEq(redemptionRateSetter.oldAccumulator(), -134000163049160773845237130);
        assertEq(redemptionRateSetter.integralAccumulator(), 90999599804006714951897802);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(0.990 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(redemptionRateSetter.deviationHistory(13), int(-10000070399479698095767723));

        assertEq(oracleRelayer.redemptionPrice(), 1000000070399479698095767723);
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(0.990 ether));
        assertEq(oracleRelayer.redemptionRate(), 999999988830212436175464411);

        assertEq(redemptionRateSetter.rawAccumulator(), 139999770947714342685497101);
        assertEq(redemptionRateSetter.oldAccumulator(), 115999787984316419591943277);
        assertEq(redemptionRateSetter.integralAccumulator(), 255999558932030762277440378);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(0.995 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(redemptionRateSetter.deviationHistory(14), int(-5000059229691347923999302));

        assertEq(oracleRelayer.redemptionPrice(), 1000000059229691347923999302);
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(0.995 ether));
        assertEq(oracleRelayer.redemptionRate(), 999999997430434422546000846);

        assertEq(redemptionRateSetter.rawAccumulator(), 59999790454050887532458228);
        assertEq(redemptionRateSetter.oldAccumulator(), 184999768146706944537079926);
        assertEq(redemptionRateSetter.integralAccumulator(), 244999558600757832069538154);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(0.995 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(redemptionRateSetter.deviationHistory(15), int(-5000056660125618275424097));

        assertEq(oracleRelayer.redemptionPrice(), 1000000056660125618275424097);
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(0.995 ether));
        assertEq(oracleRelayer.redemptionRate(), 999999999431194701844308122);

        assertEq(redemptionRateSetter.rawAccumulator(), -20000186289296664295191122);
        assertEq(redemptionRateSetter.oldAccumulator(), 224999762853167488797134932);
        assertEq(redemptionRateSetter.integralAccumulator(), 204999576563870824501943810);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(0.995 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(redemptionRateSetter.deviationHistory(16), int(-5000056091320287891152573));

        assertEq(oracleRelayer.redemptionPrice(), 1000000056091320287891152573);
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(0.995 ether));
        assertEq(oracleRelayer.redemptionRate(), 999999999589655264660387835);

        assertEq(redemptionRateSetter.rawAccumulator(), -15000171981137254090575972);
        assertEq(redemptionRateSetter.oldAccumulator(), 139999770947714342685497101);
        assertEq(redemptionRateSetter.integralAccumulator(), 124999598966577088594921129);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(0.985 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(redemptionRateSetter.deviationHistory(17), int(-15000055680975529534762429));

        assertEq(oracleRelayer.redemptionPrice(), 1000000055680975529534762429);
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(0.985 ether));
        assertEq(oracleRelayer.redemptionRate(), 999999999734647610462053644);

        assertEq(redemptionRateSetter.rawAccumulator(), -25000168432421435701339099);
        assertEq(redemptionRateSetter.oldAccumulator(), 59999790454050887532458228);
        assertEq(redemptionRateSetter.integralAccumulator(), 34999622021629451831119129);

        // ---

        hevm.warp(now + 1 seconds);
        stableFeed.updateCollateralPrice(0.985 ether);
        redemptionRateSetter.updateRedemptionRate();

        assertEq(redemptionRateSetter.deviationHistory(18), int(-15000055415623125221736164));

        assertEq(oracleRelayer.redemptionPrice(), 1000000055415623125221736164);
        assertEq(redemptionRateSetter.latestMarketPrice(), ray(0.985 ether));
        assertEq(oracleRelayer.redemptionRate(), 1000000003237738200330359969);

        assertEq(redemptionRateSetter.rawAccumulator(), -35000167187918942647651166);
        assertEq(redemptionRateSetter.oldAccumulator(), -20000186289296664295191122);
        assertEq(redemptionRateSetter.integralAccumulator(), -55000353477215606942842288);
    }
    function test_mixed_deviations() public {
        sudden_big_deviation(1, 30);
        sudden_big_deviation(-1, 40);
        major_one_side_deviations(1, 4);
        major_one_side_deviations(-1, 3);
        zig_zag_deviations(-1, 20);

        assertTrue(oracleRelayer.redemptionPrice() != 0);
        assertTrue(oracleRelayer.redemptionRate() != 0);
        assertTrue(redemptionRateSetter.latestMarketPrice() != 0);
        assertTrue(redemptionRateSetter.oldAccumulator() != 0);
        assertTrue(redemptionRateSetter.rawAccumulator() != 0);
        assertTrue(redemptionRateSetter.integralAccumulator() != 0);
    }
}
