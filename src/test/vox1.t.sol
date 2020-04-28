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
    uint public zzz;
    constructor(uint256 price_, bool validPrice_) public {
        price = bytes32(price_);
        validPrice = validPrice_;
        zzz = now;
    }
    function updateCollateralPrice(uint256 price_) external {
        price = bytes32(price_);
        zzz = now;
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
