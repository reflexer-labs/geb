/// flap.sol -- Gov token buyout

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
// Copyright (C) 2020 Stefan C. Ionescu <stefanionescu@protonmail.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.5.15;

import "./lib.sol";

contract VatLike {
    function move(address,address,uint) external;
    function good(address) external view returns (uint);
    function hope(address) external;
    function nope(address usr) external;
}
contract MaiJoinLike {
    function join(address, uint) external;
    function exit(address, uint) external;
}
contract GemLike {
    function approve(address, uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
    function move(address,address,uint) external;
    function burn(address,uint) external;
}
contract BinLike {
    function swap(address,address,uint256) external returns (uint256);
}

contract Flapper is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Flapper/not-authorized");
        _;
    }

    VatLike     public vat;
    MaiJoinLike public join;
    GemLike     public bond;
    GemLike     public gov;
    BinLike     public bin;
    address     public safe;

    uint256  public kicks = 0;
    uint256  public live;

    // --- Events ---
    event Kick(
      uint256 id,
      uint256 lot,
      address lad
    );

    // --- Init ---
    constructor(address vat_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        live = 1;
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function div(uint x, uint y) internal pure returns (uint z) {
        z = x / y;
    }

    // --- Admin ---
    function file(bytes32 what, address addr) external note auth {
        require(live == 1, "Flapper/not-live");
        if (what == "bond") bond = GemLike(addr);
        else if (what == "gov") gov = GemLike(addr);
        else if (what == "join") {
          if (address(bond) != address(0)) {
            bond.approve(address(join), 0);
          }
          vat.nope(address(join));
          vat.hope(addr);
          join = MaiJoinLike(addr);
        }
        else if (what == "bin") bin = BinLike(addr);
        else if (what == "safe") safe = addr;
        else revert("Flapper/file-unrecognized-param");
    }
    function cage() external note auth {
        live = 0;
        loot();
        vat.move(address(this), msg.sender, vat.good(address(this)));
    }

    // --- Utils ---
    function loot() internal {
        uint own = bond.balanceOf(address(this));
        if (own > 0) {
          bond.approve(address(join), own);
          join.join(safe, own);
        }
    }

    // --- Buyout ---
    function kick(uint lot) external auth returns (uint id) {
        require(live == 1, "Flapper/not-live");
        require(kicks < uint(-1), "Flapper/overflow");
        require(safe != address(0), "Flapper/no-safe");
        require(lot % RAY == 0, "Flapper/wasted-lot");

        id = ++kicks;

        uint own = bond.balanceOf(address(this));
        require(fund(div(lot, RAY), address(bin)) == true, "Flapper/cannot-fund");
        uint bid = bin.swap(address(bond), address(gov), div(lot, RAY));

        require(bid > 0, "Flapper/invalid-bid");
        require(bond.balanceOf(address(this)) == own, "Flapper/cannot-buy");
        require(gov.balanceOf(address(this)) >= bid, "Flapper/bid-not-received");

        loot();

        if (vat.good(address(this)) > 0) {
          vat.move(address(this), safe, vat.good(address(this)));
        }
        gov.burn(address(this), gov.balanceOf(address(this)));

        emit Kick(id, lot, address(bin));
    }
    function fund(uint lot, address guy) internal auth returns (bool) {
        uint own = bond.balanceOf(address(this));
        vat.move(msg.sender, address(this), mul(lot, RAY));
        join.exit(address(this), lot);
        if (add(own, lot) != bond.balanceOf(address(this))) {
          return false;
        }
        return bond.approve(guy, lot);
    }
}
