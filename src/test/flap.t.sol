pragma solidity ^0.5.15;

import "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";
import {Flapper} from "../flap.sol";
import "../vat.sol";
import {CoinJoin} from '../join.sol';
import {Coin} from "../coin.sol";

contract Hevm {
    function warp(uint256) public;
}

contract BinLike {
    uint256 give;

    constructor(
      uint256 give_
    ) public {
      give = give_;
    }

    function swap(address bond, address gov, uint sell) external returns (uint) {
        DSToken(bond).transferFrom(msg.sender, address(this), sell);
        DSToken(gov).transfer(msg.sender, give);
        return give;
    }
}

contract FlapTest is DSTest {
    Hevm hevm;

    Flapper flap;
    BinLike bin;
    Vat     vat;
    DSToken gov;
    DSToken bond;
    CoinJoin maiA;

    address ali;
    address bob;

    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        vat  = new Vat();
        gov  = new DSToken('');
        bond = new DSToken("Coin");
        bin  = new BinLike(1 ether);

        maiA = new CoinJoin(address(vat), address(bond));
        vat.rely(address(maiA));
        bond.mint(address(this), 50 ether);
        bond.setOwner(address(maiA));

        flap = new Flapper(address(vat));
        flap.file("bond", address(bond));
        flap.file("gov", address(gov));
        flap.file("bin", address(bin));
        flap.file("join", address(maiA));
        flap.file("safe", address(this));

        vat.hope(address(flap));
        gov.approve(address(flap));

        vat.suck(address(this), address(this), 1000 ether * 10 ** 27);

        gov.mint(1000 ether);
        gov.setOwner(address(flap));
        gov.push(address(bin), 200 ether);
    }
    function test_kick() public {
        assertEq(vat.good(address(this)), rad(1000 ether));
        assertEq(gov.balanceOf(address(flap)), 0);
        assertEq(vat.good(address(flap)),    0 ether);
        assertEq(bond.balanceOf(address(flap)), 0 ether);
        flap.kick(rad(100 ether));
        assertEq(gov.balanceOf(address(flap)), 0);
        assertEq(vat.good(address(flap)),    0 ether);
        assertEq(bond.balanceOf(address(flap)), 0 ether);
        assertEq(vat.good(address(this)),  rad(900 ether));
    }
    function testFail_wasted_lot() public {
        flap.kick(rad(100 ether) + 1);
    }
    function test_kick_gov_prefunded() public {
        gov.transfer(address(flap), 2 ether);
        assertEq(gov.balanceOf(address(flap)), 2 ether);
        flap.kick(rad(100 ether));
        assertEq(gov.balanceOf(address(flap)), 0);
    }
    function test_kick_bond_prefunded() public {
        bond.transfer(address(flap), 50 ether);
        assertEq(vat.good(address(this)), rad(1000 ether));
        assertEq(bond.balanceOf(address(this)), 0 ether);
        assertEq(bond.balanceOf(address(flap)), 50 ether);
        flap.kick(rad(100 ether));
        assertEq(gov.balanceOf(address(flap)), 0);
        assertEq(vat.good(address(flap)),    0 ether);
        assertEq(bond.balanceOf(address(flap)), 0 ether);
    }
    function test_kick_mai_prefunded() public {
        vat.move(address(this), address(flap), rad(50 ether));
        assertEq(vat.good(address(this)), rad(950 ether));
        assertEq(vat.good(address(flap)), rad(50 ether));
        flap.kick(rad(100 ether));
        assertEq(vat.good(address(this)), rad(900 ether));
        assertEq(vat.good(address(flap)), 0);
    }
    function test_mai_and_bond_prefunded() public {
        bond.transfer(address(flap), 50 ether);
        vat.move(address(this), address(flap), rad(50 ether));
        flap.kick(rad(150 ether));
        assertEq(gov.balanceOf(address(flap)), 0);
        assertEq(vat.good(address(flap)),    0 ether);
        assertEq(bond.balanceOf(address(flap)), 0 ether);
    }
}
