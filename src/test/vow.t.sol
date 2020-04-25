pragma solidity ^0.5.15;

import "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";
import {Flopper as Flop} from './flop.t.sol';
import {Flapper1 as Flap1} from "./flap.t.sol";
import {Flapper2 as Flap2} from './flap.t.sol';
import {TestVat as  Vat} from './vat.t.sol';
import {Vow}             from '../vow.sol';
import {CoinJoin}        from '../join.sol';

contract Hevm {
    function warp(uint256) public;
}

contract BinLike {
    bytes32 public constant INPUT  = bytes32("INPUT");

    uint256 give;

    constructor(
      uint256 give_
    ) public {
      give = give_;
    }

    function tkntkn(bytes32 side, uint sell, address lad, address[] calldata path) external returns (uint) {
        DSToken(path[0]).transferFrom(msg.sender, address(this), sell);
        DSToken(path[1]).transfer(lad, give);
        return give;
    }
}

contract VowDexFlapperTest is DSTest {
    Hevm hevm;

    Vat     vat;
    Vow     vow;
    Flop    flop;
    Flap2   flap2;
    BinLike bin;

    DSToken gov;
    DSToken coin;
    CoinJoin coinA;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        vat = new Vat();

        gov  = new DSToken('');
        coin = new DSToken("Coin");
        bin  = new BinLike(1 ether);
        coinA = new CoinJoin(address(vat), address(coin));

        vat.rely(address(coinA));
        coin.mint(address(this), 50 ether);
        coin.setOwner(address(coinA));

        flop = new Flop(address(vat), address(gov));

        flap2 = new Flap2(address(vat));
        flap2.file("coin", address(coin));
        flap2.file("gov", address(gov));
        flap2.file("bin", address(bin));
        flap2.file("join", address(coinA));
        flap2.file("safe", address(this));

        vat.hope(address(flap2));
        gov.approve(address(flap2));

        vow = new Vow(address(vat), address(flap2), address(flop));
        flap2.rely(address(vow));
        flop.rely(address(vow));

        vow.file("bump", rad(100 ether));
        vow.file("sump", rad(100 ether));
        vow.file("dump", 200 ether);

        vat.hope(address(flop));
        vat.rely(address(vow));

        gov.mint(200 ether);
        gov.setOwner(address(flap2));
        gov.push(address(bin), 200 ether);

        vat.suck(address(this), address(this), 1000 ether * 10 ** 27);
        vat.move(address(this), address(coinA), 100 ether * 10 ** 27);
    }

    function try_popDebtFromQueue(uint era) internal returns (bool ok) {
        string memory sig = "popDebtFromQueue(uint256)";
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
    function can_flap2() public returns (bool) {
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
        vow.pushDebtToQueue(rad(wad));
        vat.init('');
        vat.suck(address(vow), who, rad(wad));
    }
    function popDebtFromQueue(uint wad) internal {
        suck(address(0), wad);  // suck coin into the zero address
        vow.popDebtFromQueue(now);
    }
    function heal(uint wad) internal {
        vow.heal(rad(wad));
    }

    function test_change_flap_flop() public {
        Flap2 newFlap2 = new Flap2(address(vat));
        Flop newFlop = new Flop(address(vat), address(gov));

        newFlap2.rely(address(vow));
        newFlop.rely(address(vow));

        assertEq(vat.can(address(vow), address(flap2)), 1);
        assertEq(vat.can(address(vow), address(newFlap2)), 0);

        vow.file('flapper', address(newFlap2));
        vow.file('flopper', address(newFlop));

        assertEq(address(vow.flapper()), address(newFlap2));
        assertEq(address(vow.flopper()), address(newFlop));

        assertEq(vat.can(address(vow), address(flap2)), 0);
        assertEq(vat.can(address(vow), address(newFlap2)), 1);
    }

    function test_popDebtFromQueue_wait() public {
        assertEq(vow.wait(), 0);
        vow.file('wait', uint(100 seconds));
        assertEq(vow.wait(), 100 seconds);

        uint tic = now;
        vow.pushDebtToQueue(100 ether);
        assertTrue(!try_popDebtFromQueue(tic) );
        hevm.warp(now + tic + 100 seconds);
        assertTrue( try_popDebtFromQueue(tic) );
    }

    function test_no_reflop() public {
        popDebtFromQueue(100 ether);
        assertTrue( can_flop() );
        vow.flop();
        assertTrue(!can_flop() );
    }

    function test_no_flop_pending_joy() public {
        popDebtFromQueue(200 ether);

        vat.mint(address(vow), 100 ether);
        assertTrue(!can_flop() );

        heal(100 ether);
        assertTrue( can_flop() );
    }

    function test_basic_cage() public {
        assertEq(flap2.live(), 1);
        assertEq(flop.live(), 1);
        vow.cage();
        assertEq(flap2.live(), 0);
        assertEq(flop.live(), 0);
    }

    function test_cage_prefunded_flapper() public {
        coin.transfer(address(flap2), 50 ether);
        vow.cage();
        assertEq(coin.balanceOf(address(flap2)), 0);
        assertEq(vat.good(address(flap2)), 0);
        assertEq(coin.balanceOf(address(vow)), 0);
        assertEq(vat.good(address(vow)), 0);
    }

    function test_flap() public {
        vat.mint(address(vow), 100 ether * 10 ** 27);
        assertTrue( can_flap2() );
    }

    function test_no_flap_pending_sin() public {
        vow.file("bump", uint256(0 ether));
        popDebtFromQueue(100 ether);

        vat.mint(address(vow), 50 ether);
        assertTrue(!can_flap2() );
    }
    function test_no_flap_nonzero_woe() public {
        vow.file("bump", uint256(0 ether));
        popDebtFromQueue(100 ether);
        vat.mint(address(vow), 50 ether);
        assertTrue(!can_flap2() );
    }
    function test_no_flap_pending_flop() public {
        popDebtFromQueue(100 ether);
        vow.flop();

        vat.mint(address(vow), 100 ether);

        assertTrue(!can_flap2() );
    }
    function test_no_flap_pending_heal() public {
        popDebtFromQueue(100 ether);
        uint id = vow.flop();

        vat.mint(address(this), 100 ether);
        flop.dent(id, 0 ether, rad(100 ether));

        assertTrue(!can_flap2() );
    }

    function test_no_surplus_after_good_flop() public {
        popDebtFromQueue(100 ether);
        uint id = vow.flop();
        vat.mint(address(this), 100 ether);

        flop.dent(id, 0 ether, rad(100 ether));  // flop succeeds..

        assertTrue(!can_flap2() );
    }

    function test_multiple_flop_dents() public {
        popDebtFromQueue(100 ether);
        uint id = vow.flop();

        vat.mint(address(this), 100 ether);
        assertTrue(try_dent(id, 2 ether,  rad(100 ether)));

        vat.mint(address(this), 100 ether);
        assertTrue(try_dent(id, 1 ether,  rad(100 ether)));
    }
}

contract Gem {
    mapping (address => uint256) public balanceOf;
    function mint(address usr, uint rad) public {
        balanceOf[usr] += rad;
    }
}

contract VowAuctionFlapperTest is DSTest {
    Hevm hevm;

    Vat  vat;
    Vow  vow;
    Flop flop;
    Flap1 flap1;
    Gem  gov;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        vat = new Vat();

        gov  = new Gem();
        flop = new Flop(address(vat), address(gov));
        flap1 = new Flap1(address(vat), address(gov));

        vow = new Vow(address(vat), address(flap1), address(flop));
        flap1.rely(address(vow));
        flop.rely(address(vow));

        vow.file("bump", rad(100 ether));
        vow.file("sump", rad(100 ether));
        vow.file("dump", 200 ether);

        vat.hope(address(flop));
    }

    function try_popDebtFromQueue(uint era) internal returns (bool ok) {
        string memory sig = "popDebtFromQueue(uint256)";
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
    function can_flap1() public returns (bool) {
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

    uint constant ONE = 10 ** 27;
    function rad(uint wad) internal pure returns (uint) {
        return wad * ONE;
    }

    function suck(address who, uint wad) internal {
        vow.pushDebtToQueue(rad(wad));
        vat.init('');
        vat.suck(address(vow), who, rad(wad));
    }
    function popDebtFromQueue(uint wad) internal {
        suck(address(0), wad);  // suck dai into the zero address
        vow.popDebtFromQueue(now);
    }
    function heal(uint wad) internal {
        vow.heal(rad(wad));
    }

    function test_change_flap_flop() public {
        Flap1 newFlap1 = new Flap1(address(vat), address(gov));
        Flop newFlop = new Flop(address(vat), address(gov));

        newFlap1.rely(address(vow));
        newFlop.rely(address(vow));

        assertEq(vat.can(address(vow), address(flap1)), 1);
        assertEq(vat.can(address(vow), address(newFlap1)), 0);

        vow.file('flapper', address(newFlap1));
        vow.file('flopper', address(newFlop));

        assertEq(address(vow.flapper()), address(newFlap1));
        assertEq(address(vow.flopper()), address(newFlop));

        assertEq(vat.can(address(vow), address(flap1)), 0);
        assertEq(vat.can(address(vow), address(newFlap1)), 1);
    }

    function test_popDebtFromQueue_wait() public {
        assertEq(vow.wait(), 0);
        vow.file('wait', uint(100 seconds));
        assertEq(vow.wait(), 100 seconds);

        uint tic = now;
        vow.pushDebtToQueue(100 ether);
        assertTrue(!try_popDebtFromQueue(tic) );
        hevm.warp(now + tic + 100 seconds);
        assertTrue( try_popDebtFromQueue(tic) );
    }

    function test_no_reflop() public {
        popDebtFromQueue(100 ether);
        assertTrue( can_flop() );
        vow.flop();
        assertTrue(!can_flop() );
    }

    function test_no_flop_pending_joy() public {
        popDebtFromQueue(200 ether);

        vat.mint(address(vow), 100 ether);
        assertTrue(!can_flop() );

        heal(100 ether);
        assertTrue( can_flop() );
    }

    function test_flap() public {
        vat.mint(address(vow), 100 ether);
        assertTrue( can_flap1() );
    }

    function test_no_flap_pending_sin() public {
        vow.file("bump", uint256(0 ether));
        popDebtFromQueue(100 ether);

        vat.mint(address(vow), 50 ether);
        assertTrue(!can_flap1() );
    }
    function test_no_flap_nonzero_woe() public {
        vow.file("bump", uint256(0 ether));
        popDebtFromQueue(100 ether);
        vat.mint(address(vow), 50 ether);
        assertTrue(!can_flap1() );
    }
    function test_no_flap_pending_flop() public {
        popDebtFromQueue(100 ether);
        vow.flop();

        vat.mint(address(vow), 100 ether);

        assertTrue(!can_flap1() );
    }
    function test_no_flap_pending_heal() public {
        popDebtFromQueue(100 ether);
        uint id = vow.flop();

        vat.mint(address(this), 100 ether);
        flop.dent(id, 0 ether, rad(100 ether));

        assertTrue(!can_flap1() );
    }

    function test_no_surplus_after_good_flop() public {
        popDebtFromQueue(100 ether);
        uint id = vow.flop();
        vat.mint(address(this), 100 ether);

        flop.dent(id, 0 ether, rad(100 ether));  // flop succeeds..

        assertTrue(!can_flap1() );
    }

    function test_multiple_flop_dents() public {
        popDebtFromQueue(100 ether);
        uint id = vow.flop();

        vat.mint(address(this), 100 ether);
        assertTrue(try_dent(id, 2 ether,  rad(100 ether)));

        vat.mint(address(this), 100 ether);
        assertTrue(try_dent(id, 1 ether,  rad(100 ether)));
    }
}
