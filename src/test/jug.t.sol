pragma solidity ^0.5.15;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";

import {Jug} from "../jug.sol";
import {Vat} from "../vat.sol";

contract Hevm {
    function warp(uint256) public;
}

contract VatLike {
    function ilks(bytes32) public view returns (
        uint256 Art,
        uint256 rate,
        uint256 spot,
        uint256 line,
        uint256 dust
    );
}

contract JugTest is DSTest {
    Hevm hevm;
    Jug jug;
    Vat  vat;

    function ray(uint wad_) internal pure returns (uint) {
        return wad_ * 10 ** 9;
    }
    function rad(uint wad_) internal pure returns (uint) {
        return wad_ * 10 ** 27;
    }
    function wad(uint rad_) internal pure returns (uint) {
        return rad_ / 10 ** 27;
    }
    function wad(int rad_) internal pure returns (uint) {
        return uint(rad_ / 10 ** 27);
    }
    function rho(bytes32 ilk) internal view returns (uint) {
        (uint duty, uint rho_) = jug.ilks(ilk); duty;
        return rho_;
    }
    function Art(bytes32 ilk) internal view returns (uint ArtV) {
        (ArtV,,,,) = VatLike(address(vat)).ilks(ilk);
    }
    function rate(bytes32 ilk) internal view returns (uint rateV) {
        (, rateV,,,) = VatLike(address(vat)).ilks(ilk);
    }
    function line(bytes32 ilk) internal view returns (uint lineV) {
        (,,, lineV,) = VatLike(address(vat)).ilks(ilk);
    }

    address ali  = address(bytes20("ali"));
    address bob  = address(bytes20("bob"));
    address char = address(bytes20("char"));

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        vat  = new Vat();
        jug = new Jug(address(vat));
        vat.rely(address(jug));
        vat.init("i");

        draw("i", 100 ether);
    }
    function draw(bytes32 ilk, uint coin) internal {
        vat.file("Line", vat.Line() + rad(coin));
        vat.file(ilk, "line", line(ilk) + rad(coin));
        vat.file(ilk, "spot", 10 ** 27 * 10000 ether);
        address self = address(this);
        vat.slip(ilk, self,  10 ** 27 * 1 ether);
        vat.frob(ilk, self, self, self, int(1 ether), int(coin));
    }

    function test_bend() public {
        jug.init("i");
        jug.init("j");

        jug.file("i", "duty", 999999706969857929985428567);
        jug.file("j", "duty", 1000000564701133626865910626);

        assertEq(jug.bend(0), 1000000135835495778425669596);
        assertEq(jug.bend(ray(1 ether)), 2000000135835495778425669596);
    }
    function test_drip_setup() public {
        hevm.warp(0);
        assertEq(uint(now), 0);
        hevm.warp(1);
        assertEq(uint(now), 1);
        hevm.warp(2);
        assertEq(uint(now), 2);
        assertEq(Art("i"), 100 ether);
    }
    function test_drip_updates_rho() public {
        jug.init("i");
        assertEq(rho("i"), now);

        jug.file("i", "duty", 10 ** 27);
        jug.drip("i");
        assertEq(rho("i"), now);
        hevm.warp(now + 1);
        assertEq(rho("i"), now - 1);
        jug.drip("i");
        assertEq(rho("i"), now);
        hevm.warp(now + 1 days);
        jug.drip("i");
        assertEq(rho("i"), now);
    }
    function test_drip_file() public {
        jug.init("i");
        jug.file("i", "duty", 10 ** 27);
        jug.drip("i");
        jug.file("i", "duty", 1000000564701133626865910626);  // 5% / day
    }
    function test_drip_0d() public {
        jug.init("i");
        jug.file("i", "duty", 1000000564701133626865910626);  // 5% / day
        assertEq(vat.good(ali), rad(0 ether));
        jug.drip("i");
        assertEq(vat.good(ali), rad(0 ether));
    }
    function test_drip_1d() public {
        jug.init("i");
        jug.file("vow", ali);

        jug.file("i", "duty", 1000000564701133626865910626);  // 5% / day
        hevm.warp(now + 1 days);
        assertEq(wad(vat.good(ali)), 0 ether);
        jug.drip("i");
        assertEq(wad(vat.good(ali)), 5 ether);
    }
    function test_drip_2d() public {
        jug.init("i");
        jug.file("vow", ali);
        jug.file("i", "duty", 1000000564701133626865910626);  // 5% / day

        hevm.warp(now + 2 days);
        assertEq(wad(vat.good(ali)), 0 ether);
        jug.drip("i");
        assertEq(wad(vat.good(ali)), 10.25 ether);
    }
    function test_drip_3d() public {
        jug.init("i");
        jug.file("vow", ali);

        jug.file("i", "duty", 1000000564701133626865910626);  // 5% / day
        hevm.warp(now + 3 days);
        assertEq(wad(vat.good(ali)), 0 ether);
        jug.drip("i");
        assertEq(wad(vat.good(ali)), 15.7625 ether);
    }
    function test_drip_negative_3d() public {
        jug.init("i");
        jug.file("vow", ali);

        jug.file("i", "duty", 999999706969857929985428567);  // -2.5% / day
        hevm.warp(now + 3 days);
        assertEq(wad(vat.good(address(this))), 100 ether);
        vat.move(address(this), ali, rad(100 ether));
        assertEq(wad(vat.good(ali)), 100 ether);
        jug.drip("i");
        assertEq(wad(vat.good(ali)), 92.6859375 ether);
    }

    function test_drip_multi() public {
        jug.init("i");
        jug.file("vow", ali);

        jug.file("i", "duty", 1000000564701133626865910626);  // 5% / day
        hevm.warp(now + 1 days);
        jug.drip("i");
        assertEq(wad(vat.good(ali)), 5 ether);
        jug.file("i", "duty", 1000001103127689513476993127);  // 10% / day
        hevm.warp(now + 1 days);
        jug.drip("i");
        assertEq(wad(vat.good(ali)),  15.5 ether);
        assertEq(wad(vat.debt()),     115.5 ether);
        assertEq(rate("i") / 10 ** 9, 1.155 ether);
    }
    function test_drip_base() public {
        vat.init("j");
        draw("j", 100 ether);

        jug.init("i");
        jug.init("j");
        jug.file("vow", ali);

        jug.file("i", "duty", 1050000000000000000000000000); // 5% / second
        jug.file("j", "duty", 1000000000000000000000000000); // 0% / second
        jug.file("base",  uint(50000000000000000000000000)); // 5% / second
        hevm.warp(now + 1);
        jug.drip("i");
        assertEq(wad(vat.good(ali)), 10 ether);
    }
    function test_drip_all_positive() public {
        vat.init("j");
        draw("j", 100 ether);

        jug.init("i");
        jug.init("j");
        jug.file("vow", ali);

        jug.file("i", "duty", 1050000000000000000000000000);  // 5% / second
        jug.file("j", "duty", 1030000000000000000000000000);  // 3% / second
        jug.file("base",  uint(50000000000000000000000000));  // 5% / second

        hevm.warp(now + 1);
        jug.drip();

        assertEq(wad(vat.good(ali)), 18 ether);

        (, uint rho) = jug.ilks("i");
        assertEq(rho, now);
        (, rho) = jug.ilks("j");
        assertEq(rho, now);

        assertTrue(!jug.late());
    }
    function test_drip_all_some_negative() public {
        vat.init("j");
        draw("j", 100 ether);

        jug.init("i");
        jug.init("j");
        jug.file("vow", ali);

        jug.file("i", "duty", 1050000000000000000000000000);
        jug.file("j", "duty", 900000000000000000000000000);

        hevm.warp(now + 10);
        jug.drip("i");
        assertEq(wad(vat.good(ali)), 62889462677744140625);

        jug.drip("j");
        assertEq(wad(vat.good(ali)), 0);

        (, uint rho) = jug.ilks("i");
        assertEq(rho, now);
        (, rho) = jug.ilks("j");
        assertEq(rho, now);

        assertTrue(!jug.late());
    }
    function testFail_add_same_heir_twice() public {
        jug.file("max", 10);
        jug.file("i", 1, ray(1 ether), address(this));
        jug.file("i", 2, ray(1 ether), address(this));
    }
    function testFail_cut_at_hundred() public {
        jug.file("max", 10);
        jug.file("i", 0, ray(100 ether), address(this));
    }
    function testFail_add_over_max() public {
        jug.file("max", 1);
        jug.file("i", 1, ray(1 ether), address(this));
        jug.file("i", 2, ray(1 ether), ali);
    }
    function testFail_modify_cut_total_over_hundred() public {
        jug.file("max", 1);
        jug.file("i", 1, ray(1 ether), address(this));
        jug.file("i", 1, ray(100.1 ether), address(this));
    }
    function testFail_remove_past_node() public {
        // Add
        jug.file("max", 2);
        jug.file("i", 1, ray(1 ether), address(this));
        // Remove
        jug.file("i", 1, 0, address(this));
        jug.file("i", 1, 0, address(this));
    }
    function testFail_fix_removed_node() public {
        // Add
        jug.file("max", 1);
        jug.file("i", 1, ray(1 ether), address(this));
        // Remove
        jug.file("i", 1, 0, address(this));
        // Fix
        jug.file("i", 1, ray(1 ether), address(this));
    }
    function testFail_heir_vow() public {
        jug.file("max", 1);
        jug.file("vow", ali);
        jug.file("i", 1, ray(1 ether), ali);
    }
    function testFail_heir_null() public {
        jug.file("max", 1);
        jug.file("i", 1, ray(1 ether), address(0));
    }
    function test_add_heirs() public {
        jug.file("max", 2);
        jug.file("i", 1, ray(1 ether), address(this));
        (uint Cut, uint boon) = jug.clan("i");
        assertEq(Cut, ray(1 ether));
        assertEq(boon, 1);
        assertEq(jug.born(address(this)), 1);
        (uint take, uint cut, address gal) = jug.heirs("i", 1);
        assertEq(take, 0);
        assertEq(cut, ray(1 ether));
        assertEq(gal, address(this));
        assertEq(jug.last(), 1);
    }
    function test_modify_heir_cut() public {
        jug.file("max", 1);
        jug.file("i", 1, ray(1 ether), address(this));
        jug.file("i", 1, ray(99.9 ether), address(this));
        (uint Cut, ) = jug.clan("i");
        assertEq(Cut, ray(99.9 ether));
        (,uint cut,) = jug.heirs("i", 1);
        assertEq(cut, ray(99.9 ether));
    }
    function test_remove_some_heirs() public {
        // Add
        jug.file("max", 2);
        jug.file("i", 1, ray(1 ether), address(this));
        jug.file("i", 2, ray(98 ether), ali);
        (uint Cut, uint boon) = jug.clan("i");
        assertEq(Cut, ray(99 ether));
        assertEq(boon, 2);
        assertEq(jug.born(ali), 1);
        (uint take, uint cut, address gal) = jug.heirs("i", 2);
        assertEq(take, 0);
        assertEq(cut, ray(98 ether));
        assertEq(gal, ali);
        assertEq(jug.last(), 2);
        // Remove
        jug.file("i", 1, 0, address(this));
        (Cut, boon) = jug.clan("i");
        assertEq(Cut, ray(98 ether));
        assertEq(boon, 2);
        assertEq(jug.born(address(this)), 0);
        (take, cut, gal) = jug.heirs("i", 1);
        assertEq(take, 0);
        assertEq(cut, 0);
        assertEq(gal, address(0));
        assertEq(jug.last(), 2);
    }
    function test_remove_all_heirs() public {
        // Add
        jug.file("max", 2);
        jug.file("i", 1, ray(1 ether), address(this));
        jug.file("i", 2, ray(98 ether), ali);
        // Remove
        jug.file("i", 2, 0, ali);
        jug.file("i", 1, 0, address(this));
        (uint Cut, uint boon) = jug.clan("i");
        assertEq(Cut, 0);
        assertEq(boon, 2);
        assertEq(jug.born(ali), 0);
        assertEq(jug.born(address(0)), 0);
        (uint take, uint cut, address gal) = jug.heirs("i", 1);
        assertEq(take, 0);
        assertEq(cut, 0);
        assertEq(gal, address(0));
        assertEq(jug.last(), 0);
    }
    function test_add_remove_add_heirs() public {
        // Add
        jug.file("max", 2);
        jug.file("i", 1, ray(1 ether), address(this));
        // Remove
        jug.file("i", 1, 0, address(this));
        // Add again
        jug.file("i", 2, ray(1 ether), address(this));
        // Remove again
        jug.file("i", 2, 0, address(this));
        (uint Cut, uint boon) = jug.clan("i");
        assertEq(Cut, 0);
        assertEq(boon, 2);
        assertEq(jug.born(ali), 0);
        assertEq(jug.born(address(0)), 0);
        (uint take, uint cut, address gal) = jug.heirs("i", 1);
        assertEq(take, 0);
        assertEq(cut, 0);
        assertEq(gal, address(0));
        assertEq(jug.last(), 0);
    }
    function test_toggle_heir_take() public {
        // Add
        jug.file("max", 2);
        jug.file("i", 1, ray(1 ether), address(this));
        // Toggle
        jug.file("i", 1, 1);
        (uint take,,) = jug.heirs("i", 1);
        assertEq(take, 1);

        jug.file("i", 1, 5);
        (take,,) = jug.heirs("i", 1);
        assertEq(take, 5);

        jug.file("i", 1, 0);
        (take,,) = jug.heirs("i", 1);
        assertEq(take, 0);
    }
    function test_add_heirs_drip_positive() public {
        // Setup
        jug.init("i");
        jug.file("i", "duty", 1050000000000000000000000000);

        jug.file("vow", ali);
        jug.file("max", 2);
        jug.file("i", 1, ray(40 ether), bob);
        jug.file("i", 2, ray(45 ether), char);

        assertEq(jug.last(), 2);
        hevm.warp(now + 10);
        (, int rate) = jug.drop("i");
        jug.drip("i");
        assertEq(jug.last(), 2);

        assertEq(wad(vat.good(ali)), 9433419401661621093);
        assertEq(wad(vat.good(bob)), 25155785071097656250);
        assertEq(wad(vat.good(char)), 28300258204984863281);

        assertEq(wad(vat.good(ali)) * ray(100 ether) / uint(rate), 1499999999999999999880);
        assertEq(wad(vat.good(bob)) * ray(100 ether) / uint(rate), 4000000000000000000000);
        assertEq(wad(vat.good(char)) * ray(100 ether) / uint(rate), 4499999999999999999960);
    }
    function test_add_heirs_toggle_drip_negative() public {
        // Setup
        jug.init("i");
        jug.file("i", "duty", 1050000000000000000000000000);

        jug.file("vow", ali);
        jug.file("max", 2);
        jug.file("i", 1, ray(5 ether), bob);
        jug.file("i", 2, ray(10 ether), char);
        jug.file("i", 1, 1);
        jug.file("i", 2, 1);

        hevm.warp(now + 5);
        jug.drip("i");

        assertEq(wad(vat.good(ali)), 23483932812500000000);
        assertEq(wad(vat.good(bob)), 1381407812500000000);
        assertEq(wad(vat.good(char)), 2762815625000000000);

        jug.file("i", "duty", 900000000000000000000000000);
        jug.file("i", 1, ray(10 ether), bob);
        jug.file("i", 2, ray(20 ether), char);

        hevm.warp(now + 5);
        jug.drip("i");

        assertEq(wad(vat.good(ali)), 0);
        assertEq(wad(vat.good(bob)), 0);
        assertEq(wad(vat.good(char)), 0);
    }
    function test_add_heirs_no_toggle_drip_negative() public {
        // Setup
        jug.init("i");
        jug.file("i", "duty", 1050000000000000000000000000);

        jug.file("vow", ali);
        jug.file("max", 2);
        jug.file("i", 1, ray(5 ether), bob);
        jug.file("i", 2, ray(10 ether), char);

        hevm.warp(now + 5);
        jug.drip("i");

        assertEq(wad(vat.good(ali)), 23483932812500000000);
        assertEq(wad(vat.good(bob)), 1381407812500000000);
        assertEq(wad(vat.good(char)), 2762815625000000000);

        jug.file("i", "duty", 900000000000000000000000000);
        jug.file("i", 1, ray(10 ether), bob);
        jug.file("i", 2, ray(20 ether), char);

        hevm.warp(now + 5);
        jug.drip("i");

        assertEq(wad(vat.good(ali)), 0);
        assertEq(wad(vat.good(bob)), 1381407812500000000);
        assertEq(wad(vat.good(char)), 2762815625000000000);
    }
    function test_late() public {
        vat.init("j");
        draw("j", 100 ether);

        jug.init("i");
        jug.init("j");
        jug.file("vow", ali);

        jug.file("i", "duty", 1050000000000000000000000000);  // 5% / second
        jug.file("j", "duty", 1000000000000000000000000000);  // 0% / second
        jug.file("base",  uint(50000000000000000000000000));  // 5% / second

        hevm.warp(now + 1);
        assertTrue(jug.late());

        jug.drip("i");
        assertTrue(jug.late());
    }
    function test_file_duty() public {
        jug.init("i");
        hevm.warp(now + 1);
        jug.drip("i");
        jug.file("i", "duty", 1);
    }
    function testFail_file_duty() public {
        jug.init("i");
        hevm.warp(now + 1);
        jug.file("i", "duty", 1);
    }
}
