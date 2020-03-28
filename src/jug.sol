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

import "./lib.sol";

contract VatLike {
    function ilks(bytes32) external view returns (
        uint256 Art,   // wad
        uint256 rate   // ray
    );
    function fold(bytes32,address,int) external;
    function good(address) external view returns (uint);
}

contract Jug is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Jug/not-authorized");
        _;
    }

    // --- Data ---
    struct Ilk {
        uint256 duty;
        uint256  rho;
    }

    mapping (bytes32 => Ilk) public ilks;
    VatLike                  public vat;
    address                  public vow;
    uint256                  public base;

    bytes32[] public bank;

    // --- Init ---
    constructor(address vat_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
    }

    // --- Math ---
    function rpow(uint x, uint n, uint b) internal pure returns (uint z) {
      assembly {
        switch x case 0 {switch n case 0 {z := b} default {z := 0}}
        default {
          switch mod(n, 2) case 0 { z := b } default { z := x }
          let half := div(b, 2)  // for rounding.
          for { n := div(n, 2) } n { n := div(n,2) } {
            let xx := mul(x, x)
            if iszero(eq(div(xx, x), x)) { revert(0,0) }
            let xxRound := add(xx, half)
            if lt(xxRound, xx) { revert(0,0) }
            x := div(xxRound, b)
            if mod(n,2) {
              let zx := mul(z, x)
              if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
              let zxRound := add(zx, half)
              if lt(zxRound, zx) { revert(0,0) }
              z := div(zxRound, b)
            }
          }
        }
      }
    }
    uint256 constant RAY = 10 ** 27;
    function add(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x);
    }
    function add(int x, int y) internal pure returns (int z) {
        z = x + y;
        if (y <= 0) require(z <= x);
        if (y  > 0) require(z > x);
    }
    function diff(uint x, uint y) internal pure returns (int z) {
        z = int(x) - int(y);
        require(int(x) >= 0 && int(y) >= 0);
    }
    function mul(uint x, int y) internal pure returns (int z) {
        z = int(x) * y;
        require(int(x) >= 0);
        require(y == 0 || z / y == int(x));
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / RAY;
    }

    // --- Administration ---
    function init(bytes32 ilk) external note auth {
        Ilk storage i = ilks[ilk];
        require(i.duty == 0, "Jug/ilk-already-init");
        i.duty = RAY;
        i.rho  = now;
        bank.push(ilk);
    }
    function file(bytes32 ilk, bytes32 what, uint data) external note auth {
        require(now == ilks[ilk].rho, "Jug/rho-not-updated");
        if (what == "duty") ilks[ilk].duty = data;
        else revert("Jug/file-unrecognized-param");
    }
    function file(bytes32 what, uint data) external note auth {
        if (what == "base") base = data;
        else revert("Jug/file-unrecognized-param");
    }
    function file(bytes32 what, address data) external note auth {
        if (what == "vow") vow = data;
        else revert("Jug/file-unrecognized-param");
    }

    // --- Utils ---
    function late() external view returns (bool ko) {
        for (uint i = 0; i < bank.length; i++) {
          if (now > ilks[bank[i]].rho) {
            ko = true;
            break;
          }
        }
    }
    function lap() external view returns (bool ok) {
        int  rad;
        int  diff;
        uint Art;
        int  good = -int(vat.good(vow));
        for (uint i = 0; i < bank.length; i++) {
          if (now > ilks[bank[i]].rho) {
            (Art, )  = vat.ilks(bank[i]);
            (, diff) = drop(bank[i]);
            rad = add(rad, mul(Art, diff));
          }
        }
        if (rad < 0) {
          ok = (rad < good) ? false : true;
        } else {
          ok = true;
        }
    }

    // --- Stability Fee Collection ---
    function drop(bytes32 ilk) internal view returns (uint, int) {
        (, uint prev) = vat.ilks(ilk);
        uint rate  = rmul(rpow(add(base, ilks[ilk].duty), now - ilks[ilk].rho, RAY), prev);
        int  diff_ = diff(rate, prev);
        return (rate, diff_);
    }
    function drip() external note {
        for (uint i = 0; i < bank.length; i++) {
            if (now > ilks[bank[i]].rho) {drip(bank[i]);}
        }
    }
    function drip(bytes32 ilk) public note returns (uint) {
        require(now >= ilks[ilk].rho, "Jug/invalid-now");
        (uint rate, int rad) = drop(ilk);
        vat.fold(ilk, vow, rad);
        ilks[ilk].rho = now;
        return rate;
    }
}
