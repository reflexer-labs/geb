pragma solidity ^0.5.15;

import "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";
import {Flapper1, Flapper2} from "../flap.sol";
import "../vat.sol";
import {CoinJoin} from '../join.sol';
import {Coin} from "../coin.sol";

contract Hevm {
    function warp(uint256) public;
}

contract Guy {
    Flapper1 flap;
    constructor(Flapper1 flap_) public {
        flap = flap_;
        Vat(address(flap.vat())).hope(address(flap));
        DSToken(address(flap.gem())).approve(address(flap));
    }
    function tend(uint id, uint lot, uint bid) public {
        flap.tend(id, lot, bid);
    }
    function deal(uint id) public {
        flap.deal(id);
    }
    function try_tend(uint id, uint lot, uint bid)
        public returns (bool ok)
    {
        string memory sig = "tend(uint256,uint256,uint256)";
        (ok,) = address(flap).call(abi.encodeWithSignature(sig, id, lot, bid));
    }
    function try_deal(uint id)
        public returns (bool ok)
    {
        string memory sig = "deal(uint256)";
        (ok,) = address(flap).call(abi.encodeWithSignature(sig, id));
    }
    function try_tick(uint id)
        public returns (bool ok)
    {
        string memory sig = "tick(uint256)";
        (ok,) = address(flap).call(abi.encodeWithSignature(sig, id));
    }
}

contract FlapOneTest is DSTest {
    Hevm hevm;

    Flapper1 flap;
    Vat      vat;
    DSToken  gem;

    address ali;
    address bob;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        vat = new Vat();
        gem = new DSToken('');

        flap = new Flapper1(address(vat), address(gem));

        ali = address(new Guy(flap));
        bob = address(new Guy(flap));

        vat.hope(address(flap));
        gem.approve(address(flap));

        vat.suck(address(this), address(this), 1000 ether);

        gem.mint(1000 ether);
        gem.setOwner(address(flap));

        gem.push(ali, 200 ether);
        gem.push(bob, 200 ether);
    }
    function test_kick() public {
        assertEq(vat.good(address(this)), 1000 ether);
        assertEq(vat.good(address(flap)),    0 ether);
        flap.kick({ lot: 100 ether
                  , bid: 0
                  });
        assertEq(vat.good(address(this)),  900 ether);
        assertEq(vat.good(address(flap)),  100 ether);
    }
    function test_tend() public {
        uint id = flap.kick({ lot: 100 ether
                            , bid: 0
                            });
        // lot taken from creator
        assertEq(vat.good(address(this)), 900 ether);

        Guy(ali).tend(id, 100 ether, 1 ether);
        // bid taken from bidder
        assertEq(gem.balanceOf(ali), 199 ether);
        // payment remains in auction
        assertEq(gem.balanceOf(address(flap)),  1 ether);

        Guy(bob).tend(id, 100 ether, 2 ether);
        // bid taken from bidder
        assertEq(gem.balanceOf(bob), 198 ether);
        // prev bidder refunded
        assertEq(gem.balanceOf(ali), 200 ether);
        // excess remains in auction
        assertEq(gem.balanceOf(address(flap)),   2 ether);

        hevm.warp(now + 5 weeks);
        Guy(bob).deal(id);
        // high bidder gets the lot
        assertEq(vat.good(address(flap)),  0 ether);
        assertEq(vat.good(bob), 100 ether);
        // income is burned
        assertEq(gem.balanceOf(address(flap)),   0 ether);
    }
    function test_beg() public {
        uint id = flap.kick({ lot: 100 ether
                            , bid: 0
                            });
        assertTrue( Guy(ali).try_tend(id, 100 ether, 1.00 ether));
        assertTrue(!Guy(bob).try_tend(id, 100 ether, 1.01 ether));
        // high bidder is subject to beg
        assertTrue(!Guy(ali).try_tend(id, 100 ether, 1.01 ether));
        assertTrue( Guy(bob).try_tend(id, 100 ether, 1.07 ether));
    }
    function test_tick() public {
        // start an auction
        uint id = flap.kick({ lot: 100 ether
                            , bid: 0
                            });
        // check no tick
        assertTrue(!Guy(ali).try_tick(id));
        // run past the end
        hevm.warp(now + 2 weeks);
        // check not biddable
        assertTrue(!Guy(ali).try_tend(id, 100 ether, 1 ether));
        assertTrue( Guy(ali).try_tick(id));
        // check biddable
        assertTrue( Guy(ali).try_tend(id, 100 ether, 1 ether));
    }
}

contract BinLike {
    uint256 give;

    constructor(
      uint256 give_
    ) public {
      give = give_;
    }

    function swap(address lad, address bond, address gov, uint sell) external returns (uint) {
        DSToken(bond).transferFrom(msg.sender, address(this), sell);
        DSToken(gov).transfer(lad, give);
        return give;
    }
}

contract FlapTwoTest is DSTest {
    Hevm hevm;

    Flapper2 flap;
    BinLike  bin;
    Vat      vat;
    DSToken  gov;
    DSToken  bond;
    CoinJoin coinA;

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

        coinA = new CoinJoin(address(vat), address(bond));
        vat.rely(address(coinA));
        bond.mint(address(this), 50 ether);
        bond.setOwner(address(coinA));

        flap = new Flapper2(address(vat));
        flap.file("bond", address(bond));
        flap.file("gov", address(gov));
        flap.file("bin", address(bin));
        flap.file("join", address(coinA));
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
    function test_kick_coin_prefunded() public {
        vat.move(address(this), address(flap), rad(50 ether));
        assertEq(vat.good(address(this)), rad(950 ether));
        assertEq(vat.good(address(flap)), rad(50 ether));
        flap.kick(rad(100 ether));
        assertEq(vat.good(address(this)), rad(900 ether));
        assertEq(vat.good(address(flap)), 0);
    }
    function test_coin_and_bond_prefunded() public {
        bond.transfer(address(flap), 50 ether);
        vat.move(address(this), address(flap), rad(50 ether));
        flap.kick(rad(150 ether));
        assertEq(gov.balanceOf(address(flap)), 0);
        assertEq(vat.good(address(flap)),    0 ether);
        assertEq(bond.balanceOf(address(flap)), 0 ether);
    }
}
