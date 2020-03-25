pragma solidity ^0.5.15;

import "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";
import {Flopper as Flop} from './flop.t.sol';
import {Flapper as Flap} from './flap.t.sol';
import {TestVat as  Vat} from './vat.t.sol';
import {Vow}             from '../vow.sol';
import {MaiJoin}         from '../join.sol';

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

contract VowTest is DSTest {
    Hevm hevm;

    Vat     vat;
    Vow     vow;
    Flop    flop;
    Flap    flap;
    BinLike bin;

    DSToken gov;
    DSToken bond;
    MaiJoin maiA;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        vat = new Vat();

        gov  = new DSToken('');
        bond = new DSToken("Mai");
        bin  = new BinLike(1 ether);
        maiA = new MaiJoin(address(vat), address(bond));

        vat.rely(address(maiA));
        bond.mint(address(this), 50 ether);
        bond.setOwner(address(maiA));

        flop = new Flop(address(vat), address(gov));

        flap = new Flap(address(vat));
        flap.file("bond", address(bond));
        flap.file("gov", address(gov));
        flap.file("bin", address(bin));
        flap.file("join", address(maiA));
        flap.file("safe", address(this));

        vat.hope(address(flap));
        gov.approve(address(flap));

        vow = new Vow(address(vat), address(flap), address(flop));
        flap.rely(address(vow));
        flop.rely(address(vow));

        vow.file("bump", rad(100 ether));
        vow.file("sump", rad(100 ether));
        vow.file("dump", 200 ether);

        vat.hope(address(flop));
        vat.rely(address(vow));

        gov.mint(200 ether);
        gov.setOwner(address(flap));
        gov.push(address(bin), 200 ether);
    }

    function try_flog(uint era) internal returns (bool ok) {
        string memory sig = "flog(uint256)";
        (ok,) = address(vow).call(abi.encodeWithSignature(sig, era));
    }
    function try_dent(uint id, uint lot, uint bid) internal returns (bool ok) {
        string memory sig = "dent(uint256,uint256,uint256)";
        (ok,) = address(flop).call(abi.encodeWithSignature(sig, id, lot, bid));
    }
    function try_call(address addr, bytes calldata data) external returns (bool) {
        bytes memory _data = data;
        assembly {
            let ok := call(gas, addr, 0, add(_data, 0x20), mload(_data), 0, 0)
            let free := mload(0x40)
            mstore(free, ok)
            mstore(0x40, add(free, 32))
            revert(free, 32)
        }
    }
    function can_flap() public returns (bool) {
        string memory sig = "flap()";
        bytes memory data = abi.encodeWithSignature(sig);

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", vow, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function can_flop() public returns (bool) {
        string memory sig = "flop()";
        bytes memory data = abi.encodeWithSignature(sig);

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", vow, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }

    uint constant RAY = 10 ** 27;
    function rad(uint wad) internal pure returns (uint) {
        return wad * RAY;
    }

    function suck(address who, uint wad) internal {
        vow.fess(rad(wad));
        vat.init('');
        vat.suck(address(vow), who, rad(wad));
    }
    function flog(uint wad) internal {
        suck(address(0), wad);  // suck mai into the zero address
        vow.flog(now);
    }
    function heal(uint wad) internal {
        vow.heal(rad(wad));
    }

    function test_change_flap_flop() public {
        Flap newFlap = new Flap(address(vat));
        Flop newFlop = new Flop(address(vat), address(gov));

        newFlap.rely(address(vow));
        newFlop.rely(address(vow));

        assertEq(vat.can(address(vow), address(flap)), 1);
        assertEq(vat.can(address(vow), address(newFlap)), 0);

        vow.file('flapper', address(newFlap));
        vow.file('flopper', address(newFlop));

        assertEq(address(vow.flapper()), address(newFlap));
        assertEq(address(vow.flopper()), address(newFlop));

        assertEq(vat.can(address(vow), address(flap)), 0);
        assertEq(vat.can(address(vow), address(newFlap)), 1);
    }

    function test_flog_wait() public {
        assertEq(vow.wait(), 0);
        vow.file('wait', uint(100 seconds));
        assertEq(vow.wait(), 100 seconds);

        uint tic = now;
        vow.fess(100 ether);
        assertTrue(!try_flog(tic) );
        hevm.warp(now + tic + 100 seconds);
        assertTrue( try_flog(tic) );
    }

    function test_no_reflop() public {
        flog(100 ether);
        assertTrue( can_flop() );
        vow.flop();
        assertTrue(!can_flop() );
    }

    function test_no_flop_pending_joy() public {
        flog(200 ether);

        vat.mint(address(vow), 100 ether);
        assertTrue(!can_flop() );

        heal(100 ether);
        assertTrue( can_flop() );
    }

    function test_basic_cage() public {
        assertEq(flap.live(), 1);
        assertEq(flop.live(), 1);
        vow.cage();
        assertEq(flap.live(), 0);
        assertEq(flop.live(), 0);
    }

    function test_cage_prefunded_flapper() public {
        bond.transfer(address(flap), 50 ether);
        vow.cage();
        // assertEq(bond.balanceOf(address(flap)), 0);
        // assertEq(vat.mai(address(flap)), 0);
        // assertEq(bond.balanceOf(address(vow)), 0);
        // assertEq(vat.mai(address(vow)), 0);
    }

    function test_flap() public {
        vat.mint(address(vow), 100 ether * 10 ** 27);
        assertTrue( can_flap() );
    }

    function test_no_flap_pending_sin() public {
        vow.file("bump", uint256(0 ether));
        flog(100 ether);

        vat.mint(address(vow), 50 ether);
        assertTrue(!can_flap() );
    }
    function test_no_flap_nonzero_woe() public {
        vow.file("bump", uint256(0 ether));
        flog(100 ether);
        vat.mint(address(vow), 50 ether);
        assertTrue(!can_flap() );
    }
    function test_no_flap_pending_flop() public {
        flog(100 ether);
        vow.flop();

        vat.mint(address(vow), 100 ether);

        assertTrue(!can_flap() );
    }
    function test_no_flap_pending_heal() public {
        flog(100 ether);
        uint id = vow.flop();

        vat.mint(address(this), 100 ether);
        flop.dent(id, 0 ether, rad(100 ether));

        assertTrue(!can_flap() );
    }

    function test_no_surplus_after_good_flop() public {
        flog(100 ether);
        uint id = vow.flop();
        vat.mint(address(this), 100 ether);

        flop.dent(id, 0 ether, rad(100 ether));  // flop succeeds..

        assertTrue(!can_flap() );
    }

    function test_multiple_flop_dents() public {
        flog(100 ether);
        uint id = vow.flop();

        vat.mint(address(this), 100 ether);
        assertTrue(try_dent(id, 2 ether,  rad(100 ether)));

        vat.mint(address(this), 100 ether);
        assertTrue(try_dent(id, 1 ether,  rad(100 ether)));
    }
}
