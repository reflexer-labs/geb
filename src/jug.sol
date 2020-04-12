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
import "./list.sol";

contract VatLike {
    function ilks(bytes32) external view returns (
        uint256 Art,   // wad
        uint256 rate   // ray
    );
    function fold(bytes32,address,int) external;
    function good(address) external view returns (uint);
}

contract Jug is LibNote {
    using Link for Link.List;

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
    struct Heir {
        uint256 take;
        uint256 cut;
        address gal;
    }
    struct Clan {
        uint256 cut;
        uint256 boon;
    }

    mapping (bytes32 => Ilk)                      public ilks;
    mapping (bytes32 => Clan)                     public clan;
    mapping (address => uint256)                  public born;   // already born heirs
    mapping (bytes32 => mapping(uint256 => Heir)) public heirs;  // data about each heir

    address    public vow;
    uint256    public base;
    uint256    public max;  // max number of heirs any ilk can have
    uint256    public last; // latest node

    bytes32[]  public  bank;
    Link.List  internal gift;

    VatLike    public vat;

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
    uint256 constant RAY     = 10 ** 27;
    uint256 constant HUNDRED = 10 ** 29;
    uint256 constant ONE     = 1;

    function add(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x);
    }
    function add(int x, int y) internal pure returns (int z) {
        z = x + y;
        if (y <= 0) require(z <= x);
        if (y  > 0) require(z > x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function sub(int x, int y) internal pure returns (int z) {
        z = x - y;
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
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
    function mul(int x, int y) internal pure returns (int z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / RAY;
    }

    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
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
        else if (what == "max") max = data;
        else revert("Jug/file-unrecognized-param");
    }
    function file(bytes32 what, address data) external note auth {
        require(data != address(0), "Jug/null-data");
        if (what == "vow") vow = data;
        else revert("Jug/file-unrecognized-param");
    }
    function file(bytes32 ilk, uint256 what, uint256 val) external note auth {
        if (both(gift.isNode(what), heirs[ilk][what].cut > 0)) {
            heirs[ilk][what].take = val;
        }
        else revert("Jug/unknown-heir");
    }
    function file(bytes32 ilk, uint256 what, uint256 val, address addr) external note auth {
        (clan[ilk].boon < what) ? form(ilk, val, addr) : fix(ilk, what, val);
    }

    // --- Stability Fee Heirs ---
    function form(bytes32 ilk, uint256 val, address addr) internal {
        require(addr != address(0), "Jug/null-heir");
        require(addr != vow, "Jug/vow-cannot-heir");
        require(val > 0, "Jug/null-val");
        require(born[addr] == 0, "Jug/already-born");
        require(add(gift.range(), ONE) <= max, "Jug/exceeds-max");
        require(add(clan[ilk].cut, val) < HUNDRED, "Jug/too-much-cut");
        born[addr]                     = ONE;
        clan[ilk].boon                 = add(clan[ilk].boon, ONE);
        clan[ilk].cut                  = add(clan[ilk].cut, val);
        heirs[ilk][clan[ilk].boon].cut = val;
        heirs[ilk][clan[ilk].boon].gal = addr;
        last                           = clan[ilk].boon;
        gift.push(clan[ilk].boon, false);
    }
    function fix(bytes32 ilk, uint256 what, uint256 val) internal {
        require(both(gift.isNode(what), heirs[ilk][what].cut > 0), "Jug/unknown-heir");
        if (val == 0) {
          born[heirs[ilk][what].gal] = 0;
          clan[ilk].cut  = sub(clan[ilk].cut, heirs[ilk][what].cut);
          if (what == last) {
            (, uint256 prev) = gift.prev(last);
            last = prev;
          }
          gift.del(what);
          delete(heirs[ilk][what]);
        } else {
          uint256 Cut = add(sub(clan[ilk].cut, heirs[ilk][what].cut), val);
          require(Cut < HUNDRED, "Jug/too-much-cut");
          clan[ilk].cut                  = Cut;
          heirs[ilk][clan[ilk].boon].cut = val;
        }
    }

    // --- Drip Utils ---
    function late() public view returns (bool ko) {
        for (uint i = 0; i < bank.length; i++) {
          if (now > ilks[bank[i]].rho) {
            ko = true;
            break;
          }
        }
    }
    function lap() public view returns (bool ok, int rad) {
        int  diff_;
        uint Art;
        int  good_ = -int(vat.good(vow));
        for (uint i = 0; i < bank.length; i++) {
          if (now > ilks[bank[i]].rho) {
            (Art, )  = vat.ilks(bank[i]);
            (, diff_) = drop(bank[i]);
            rad = add(rad, mul(Art, diff_));
          }
        }
        if (rad < 0) {
          ok = (rad < good_) ? false : true;
        } else {
          ok = true;
        }
    }

    // --- Gifts Utils ---
    function range() public view returns (uint) {
        return gift.range();
    }
    function isNode(uint256 _node) public view returns (bool) {
        return gift.isNode(_node);
    }

    // --- Stability Fee Collection ---
    function drop(bytes32 ilk) public view returns (uint, int) {
        (, uint prev) = vat.ilks(ilk);
        uint rate = rmul(rpow(add(base, ilks[ilk].duty), sub(now, ilks[ilk].rho), RAY), prev);
        int  diff_ = diff(rate, prev);
        return (rate, diff_);
    }
    function drip() external note {
        for (uint i = 0; i < bank.length; i++) {
            if (now >= ilks[bank[i]].rho) {drip(bank[i]);}
        }
    }
    function drip(bytes32 ilk) public note returns (uint) {
        require(now >= ilks[ilk].rho, "Jug/invalid-now");
        (uint rate, int rad) = drop(ilk);
        roll(ilk, rad);
        (, rate) = vat.ilks(ilk);
        ilks[ilk].rho = now;
        return rate;
    }
    function roll(bytes32 ilk, int rad) internal {
        (uint Art, )  = vat.ilks(ilk);
        uint256 prev_ = last;
        int256  much;
        int256  good_;
        while (prev_ > 0) {
          good_ = -int(vat.good(heirs[ilk][prev_].gal));
          much  = mul(int(heirs[ilk][prev_].cut), rad) / int(HUNDRED);
          much  = (both(mul(Art, much) < 0, good_ > mul(Art, much))) ? good_ / int(Art) : much;
          if ( both(much != 0, either(rad >= 0, both(much < 0, heirs[ilk][prev_].take > 0))) ) {
            vat.fold(ilk, heirs[ilk][prev_].gal, much);
          }
          (, prev_) = gift.prev(prev_);
        }
        good_ = -int(vat.good(vow));
        much  = mul(sub(HUNDRED, clan[ilk].cut), rad) / int(HUNDRED);
        much  = (both(mul(Art, much) < 0, good_ > mul(Art, much))) ? good_ / int(Art) : much;
        if (much != 0) vat.fold(ilk, vow, much);
    }
}
