/// mai.t.sol -- tests for mai.sol

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
import {Vow} from '../vow.sol';
import {GemJoin} from '../join.sol';
import {Spotter} from '../spot.sol';

contract Feed {
    bytes32 public val;
    bool public has;
    constructor(uint256 initVal, bool initHas) public {
        val = bytes32(initVal);
        has = initHas;
    }
    function peek() external returns (bytes32, bool) {
        return (val, has);
    }
}

contract TokenUser {
    Mai  token;

    constructor(Mai token_) public {
        token = token_;
    }

    function doTransferFrom(address from, address to, uint amount)
        public
        returns (bool)
    {
        return token.transferFrom(from, to, amount);
    }

    function doTransfer(address to, uint amount)
        public
        returns (bool)
    {
        return token.transfer(to, amount);
    }

    function doApprove(address recipient, uint amount)
        public
        returns (bool)
    {
        return token.approve(recipient, amount);
    }

    function doAllowance(address owner, address spender)
        public
        view
        returns (uint)
    {
        return token.allowance(owner, spender);
    }

    function doBalanceOf(address who) public view returns (uint) {
        return token.balanceOf(who);
    }

    function doApprove(address guy)
        public
        returns (bool)
    {
        return token.approve(guy, uint(-1));
    }
    function doMint(uint wad) public {
        token.mint(address(this), wad);
    }
    function doBurn(uint wad) public {
        token.burn(address(this), wad);
    }
    function doMint(address guy, uint wad) public {
        token.mint(guy, wad);
    }
    function doBurn(address guy, uint wad) public {
        token.burn(guy, wad);
    }

}

contract Hevm {
    function warp(uint256) public;
}

contract MaiTest is DSTest {
    uint constant initialBalanceThis = 1000;
    uint constant initialBalanceCal = 100;

    Vat     vat;
    Spotter spot;

    GemJoin gemA;
    DSToken gold;
    Feed    goldFeed;

    Mai     token;
    Hevm    hevm;

    address user1;
    address user2;
    address user3;
    address self;

    uint amount = 2;
    uint fee = 1;
    uint nonce = 0;
    uint deadline = 0;
    address cal = 0x29C76e6aD8f28BB1004902578Fb108c507Be341b;
    address del = 0xdd2d5D3f7f1b35b7A0601D6A00DbB7D44Af58479;
    uint8 v = 27;
    bytes32 r = 0xc7a9f6e53ade2dc3715e69345763b9e6e5734bfe6b40b8ec8e122eb379f07e5b;
    bytes32 s = 0x14cb2f908ca580a74089860a946f56f361d55bdb13b6ce48a998508b0fa5e776;
    bytes32 _r = 0x64e82c811ee5e912c0f97ac1165c73d593654a6fc434a470452d8bca6ec98424;
    bytes32 _s = 0x5a209fe6efcf6e06ec96620fd968d6331f5e02e5db757ea2a58229c9b3c033ed;
    uint8 _v = 28;

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }

    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        vat = new Vat();
        spot = new Spotter(address(vat));
        vat.rely(address(spot));

        gold = new DSToken("GEM");
        gold.mint(1000 ether);
        vat.init("gold");
        goldFeed = new Feed(1 ether, true);
        spot.file("gold", "pip", address(goldFeed));
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

        spot.rely(address(token));
        vat.rely(address(token));

        user1 = address(new TokenUser(token));
        user2 = address(new TokenUser(token));
        user3 = address(new TokenUser(token));

        token.file("vow", address(user3));
        token.file("spot", address(spot));

        token.mint(address(this), initialBalanceThis);
        token.mint(cal, initialBalanceCal);

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

    function createToken() internal returns (Mai) {
        return new Mai(99, address(vat));
    }

    function testSetup() public {
        assertEq(spot.par(), 10 ** 27);
        assertEq(token.balanceOf(self), initialBalanceThis);
        assertEq(token.balanceOf(cal), initialBalanceCal);
        token.mint(self, 0);
        assertEq(token.rho(), now);
        assertEq(token.msr(), 10 ** 27);
        (,,uint price,,,) = vat.ilks("gold");
        assertEq(price, ray(1 ether));
    }

    function testSetupPrecondition() public {
        assertEq(token.balanceOf(self), initialBalanceThis);
    }

    function testTransferCost() public logs_gas {
        token.transfer(address(0), 10);
    }

    function testAllowanceStartsAtZero() public logs_gas {
        assertEq(token.allowance(user1, user2), 0);
    }

    function testValidTransfers() public logs_gas {
        uint sentAmount = 250;
        emit log_named_address("token11111", address(token));
        token.transfer(user2, sentAmount);
        assertEq(token.balanceOf(user2), sentAmount);
        assertEq(token.balanceOf(self), initialBalanceThis - sentAmount);
    }

    function testFailWrongAccountTransfers() public logs_gas {
        uint sentAmount = 250;
        token.transferFrom(user2, self, sentAmount);
    }

    function testFailInsufficientFundsTransfers() public logs_gas {
        uint sentAmount = 250;
        token.transfer(user1, initialBalanceThis - sentAmount);
        token.transfer(user2, sentAmount + 1);
    }

    function testApproveSetsAllowance() public logs_gas {
        emit log_named_address("Test", self);
        emit log_named_address("Token", address(token));
        emit log_named_address("Me", self);
        emit log_named_address("User 2", user2);
        token.approve(user2, 25);
        assertEq(token.allowance(self, user2), 25);
    }

    function testChargesAmountApproved() public logs_gas {
        uint amountApproved = 20;
        token.approve(user2, amountApproved);
        assertTrue(TokenUser(user2).doTransferFrom(self, user2, amountApproved));
        assertEq(token.balanceOf(self), initialBalanceThis - amountApproved);
    }

    function testFailTransferWithoutApproval() public logs_gas {
        token.transfer(user1, 50);
        token.transferFrom(user1, self, 1);
    }

    function testFailChargeMoreThanApproved() public logs_gas {
        token.transfer(user1, 50);
        TokenUser(user1).doApprove(self, 20);
        token.transferFrom(user1, self, 21);
    }
    function testTransferFromSelf() public {
        token.transferFrom(self, user1, 50);
        assertEq(token.balanceOf(user1), 50);
    }
    function testFailTransferFromSelfNonArbitrarySize() public {
        // you shouldn't be able to evade balance checks by transferring
        // to yourself
        token.transferFrom(self, self, token.balanceOf(self) + 1);
    }
    function testMintself() public {
        uint mintAmount = 10;
        token.mint(address(this), mintAmount);
        assertEq(token.balanceOf(self), initialBalanceThis + mintAmount);
    }
    function testMintGuy() public {
        uint mintAmount = 10;
        token.mint(user1, mintAmount);
        assertEq(token.balanceOf(user1), mintAmount);
    }
    function testFailMintGuyNoAuth() public {
        TokenUser(user1).doMint(user2, 10);
    }
    function testMintGuyAuth() public {
        token.rely(user1);
        TokenUser(user1).doMint(user2, 10);
    }

    function testBurn() public {
        uint burnAmount = 10;
        token.burn(address(this), burnAmount);
        assertEq(token.totalSupply(), initialBalanceThis + initialBalanceCal - burnAmount);
        assertEq(spot.par(), 10 ** 27);
        assertEq(token.rho(), now);
    }
    function testBurnself() public {
        uint burnAmount = 10;
        token.burn(address(this), burnAmount);
        assertEq(token.balanceOf(self), initialBalanceThis - burnAmount);
    }
    function testBurnGuyWithTrust() public {
        uint burnAmount = 10;
        token.transfer(user1, burnAmount);
        assertEq(token.balanceOf(user1), burnAmount);

        TokenUser(user1).doApprove(self);
        token.burn(user1, burnAmount);
        assertEq(token.balanceOf(user1), 0);
    }
    function testBurnAuth() public {
        token.transfer(user1, 10);
        token.rely(user1);
        TokenUser(user1).doBurn(10);
    }
    function testBurnGuyAuth() public {
        token.transfer(user2, 10);
        token.rely(user1);
        TokenUser(user2).doApprove(user1);
        TokenUser(user1).doBurn(user2, 10);
    }

    function testFailUntrustedTransferFrom() public {
        assertEq(token.allowance(self, user2), 0);
        TokenUser(user1).doTransferFrom(self, user2, 200);
    }
    function testTrusting() public {
        assertEq(token.allowance(self, user2), 0);
        token.approve(user2, uint(-1));
        assertEq(token.allowance(self, user2), uint(-1));
        token.approve(user2, 0);
        assertEq(token.allowance(self, user2), 0);
    }
    function testTrustedTransferFrom() public {
        token.approve(user1, uint(-1));
        TokenUser(user1).doTransferFrom(self, user2, 200);
        assertEq(token.balanceOf(user2), 200);
    }
    function testApproveWillModifyAllowance() public {
        assertEq(token.allowance(self, user1), 0);
        assertEq(token.balanceOf(user1), 0);
        token.approve(user1, 1000);
        assertEq(token.allowance(self, user1), 1000);
        TokenUser(user1).doTransferFrom(self, user1, 500);
        assertEq(token.balanceOf(user1), 500);
        assertEq(token.allowance(self, user1), 500);
    }
    function testApproveWillNotModifyAllowance() public {
        assertEq(token.allowance(self, user1), 0);
        assertEq(token.balanceOf(user1), 0);
        token.approve(user1, uint(-1));
        assertEq(token.allowance(self, user1), uint(-1));
        TokenUser(user1).doTransferFrom(self, user1, 1000);
        assertEq(token.balanceOf(user1), 1000);
        assertEq(token.allowance(self, user1), uint(-1));
    }
    function testMaiAddress() public {
        //The mai address generated by hevm
        //used for signature generation testing
        assertEq(address(token), address(0xD9ced1c2A058f4d60e392f6DA2898594138B5ac0));
    }

    function testTypehash() public {
        assertEq(token.PERMIT_TYPEHASH(), 0xea2aa0a1be11a07ed86d755c93467f4f82362b452371d1ba94d1715123511acb);
    }

    function testDomain_Separator() public {
        assertEq(token.DOMAIN_SEPARATOR(), 0x198ebdd248a623f1024e205d5da141719fb9869cd528047b2893b4f9b70473ef);
    }

    //TODO: remake with v,r,s for mai now that we changed the DOMAIN SEPARATOR because of the dai->mai rename

    // function testPermit() public {
    //     assertEq(token.nonces(cal), 0);
    //     assertEq(token.allowance(cal, del), 0);
    //     token.permit(cal, del, 0, 0, true, v, r, s);
    //     assertEq(token.allowance(cal, del),uint(-1));
    //     assertEq(token.nonces(cal),1);
    // }

    function testFailPermitAddress0() public {
        v = 0;
        token.permit(address(0), del, 0, 0, true, v, r, s);
    }

    //TODO: remake with _v,_r,_s for mai now that we changed the DOMAIN SEPARATOR because of the dai->mai rename

    // function testPermitWithExpiry() public {
    //     assertEq(now, 604411200);
    //     token.permit(cal, del, 0, 604411200 + 1 hours, true, _v, _r, _s);
    //     assertEq(token.allowance(cal, del),uint(-1));
    //     assertEq(token.nonces(cal),1);
    // }

    function testFailPermitWithExpiry() public {
        hevm.warp(now + 2 hours);
        assertEq(now, 604411200 + 2 hours);
        token.permit(cal, del, 0, 1, true, _v, _r, _s);
    }

    function testFailReplay() public {
        token.permit(cal, del, 0, 0, true, v, r, s);
        token.permit(cal, del, 0, 0, true, v, r, s);
    }

    function testUpdateRate() public {
        token.drip();
        token.file("msr", 1000000564701133626865910626);
        assertEq(token.msr(), 1000000564701133626865910626);
        assertEq(spot.par(), 10 ** 27);
    }

    function testPositiveRateAndDrip() public {
        token.drip();
        token.file("msr", 1000000564701133626865910626);
        hevm.warp(now + 2 hours);
        token.drip();
        assertEq(spot.par(), 1004074123783648301605420882);
    }

    function testNegativeRateAndDrip() public {
        token.drip();
        token.file("msr", 999999706969857929985428567);
        hevm.warp(now + 1 hours);
        token.drip();
        assertEq(spot.par(), 998945647554530252758389043);
    }

    function testPositiveThenNegativeRateAndDrip() public {
        token.drip();
        token.file("msr", 1000000564701133626865910626);
        hevm.warp(now + 2 hours);
        token.drip();

        token.file("msr", 999999706969857929985428567);
        hevm.warp(now + 1 hours);
        token.drip();
        assertEq(spot.par(), 1003015475775804118317582801);
    }

    function testChangeParCollateralPrice() public {
        token.drip();
        token.file("msr", 1000000564701133626865910626);
        hevm.warp(now + 2 hours);
        token.drip();

        spot.poke("gold");
        (,,uint price,,,) = vat.ilks("gold");
        assertEq(price, 995942407351067072547712742);

        token.file("msr", 999999706969857929985428567);
        hevm.warp(now + 3.5 hours);
        token.drip();

        spot.poke("gold");
        (,,price,,,) = vat.ilks("gold");
        assertEq(price, 999626403121623126487339967);
    }
}
