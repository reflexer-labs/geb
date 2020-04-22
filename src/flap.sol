/// flap.sol -- Gov token burning

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
    function INPUT() public view returns (bytes32);
    function tkntkn(bytes32,uint256,address,address[] calldata) external returns (uint256);
}

/*
   This thing lets you sell some coin in return for gov tokens.
 - `lot` coin for sale
 - `bid` got tokens paid
 - `ttl` single bid lifetime
 - `beg` minimum bid increase
 - `end` max auction duration
*/

contract Flapper1 is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Flapper1/not-authorized");
        _;
    }

    // --- Data ---
    struct Bid {
        uint256 bid;
        uint256 lot;
        address guy;  // high bidder
        uint48  tic;  // expiry time
        uint48  end;
    }

    mapping (uint => Bid) public bids;

    VatLike  public   vat;
    GemLike  public   gem;

    uint256  constant ONE = 1.00E18;
    uint256  public   beg = 1.05E18;  // 5% minimum bid increase
    uint48   public   ttl = 3 hours;  // 3 hours bid duration
    uint48   public   tau = 2 days;   // 2 days total auction length
    uint256  public kicks = 0;
    uint256  public live;

    // --- Events ---
    event Kick(
      uint256 id,
      uint256 lot,
      uint256 bid
    );

    // --- Init ---
    constructor(address vat_, address gem_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        gem = GemLike(gem_);
        live = 1;
    }

    // --- Math ---
    function add(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Admin ---
    function file(bytes32 what, uint data) external note auth {
        if (what == "beg") beg = data;
        else if (what == "ttl") ttl = uint48(data);
        else if (what == "tau") tau = uint48(data);
        else revert("Flapper1/file-unrecognized-param");
    }

    // --- Auction ---
    function kick(uint lot, uint bid) external auth returns (uint id) {
        require(live == 1, "Flapper1/not-live");
        require(kicks < uint(-1), "Flapper1/overflow");
        id = ++kicks;

        bids[id].bid = bid;
        bids[id].lot = lot;
        bids[id].guy = msg.sender; // configurable??
        bids[id].end = add(uint48(now), tau);

        vat.move(msg.sender, address(this), lot);

        emit Kick(id, lot, bid);
    }
    function tick(uint id) external note {
        require(bids[id].end < now, "Flapper1/not-finished");
        require(bids[id].tic == 0, "Flapper1/bid-already-placed");
        bids[id].end = add(uint48(now), tau);
    }
    function tend(uint id, uint lot, uint bid) external note {
        require(live == 1, "Flapper1/not-live");
        require(bids[id].guy != address(0), "Flapper1/guy-not-set");
        require(bids[id].tic > now || bids[id].tic == 0, "Flapper1/already-finished-tic");
        require(bids[id].end > now, "Flapper1/already-finished-end");

        require(lot == bids[id].lot, "Flapper1/lot-not-matching");
        require(bid >  bids[id].bid, "Flapper1/bid-not-higher");
        require(mul(bid, ONE) >= mul(beg, bids[id].bid), "Flapper1/insufficient-increase");

        if (msg.sender != bids[id].guy) {
            gem.move(msg.sender, bids[id].guy, bids[id].bid);
            bids[id].guy = msg.sender;
        }
        gem.move(msg.sender, address(this), bid - bids[id].bid);

        bids[id].bid = bid;
        bids[id].tic = add(uint48(now), ttl);
    }
    function deal(uint id) external note {
        require(live == 1, "Flapper1/not-live");
        require(bids[id].tic != 0 && (bids[id].tic < now || bids[id].end < now), "Flapper1/not-finished");
        vat.move(address(this), bids[id].guy, bids[id].lot);
        gem.burn(address(this), bids[id].bid);
        delete bids[id];
    }

    function cage(uint rad) external note auth {
       live = 0;
       vat.move(address(this), msg.sender, rad);
    }
    function yank(uint id) external note {
        require(live == 0, "Flapper1/still-live");
        require(bids[id].guy != address(0), "Flapper1/guy-not-set");
        gem.move(address(this), bids[id].guy, bids[id].bid);
        delete bids[id];
    }
}

/*
  This thing automatically buys gov tokens from DEXs with surplus coming from Vow
*/

contract Flapper2 is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Flapper2/not-authorized");
        _;
    }

    VatLike     public vat;
    MaiJoinLike public join;
    GemLike     public coin;
    GemLike     public gov;
    BinLike     public bin;
    address     public safe;

    address[]   public path;

    uint8       public mutex;
    uint256     public kicks = 0;
    uint256     public live;

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
        path.push(address(0));
        path.push(address(0));
        live = 1;
    }

    // --- Math ---
    uint256 constant RAD = 10 ** 45;
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

    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- Admin ---
    function file(bytes32 what, address addr) external note auth {
        require(live == 1, "Flapper2/not-live");
        if (what == "coin") {
          coin    = GemLike(addr);
          path[0] = addr;
        }
        else if (what == "gov") {
          gov     = GemLike(addr);
          path[1] = addr;
        }
        else if (what == "join") {
          if (address(coin) != address(0)) {
            coin.approve(address(join), 0);
          }
          vat.nope(address(join));
          vat.hope(addr);
          join = MaiJoinLike(addr);
        }
        else if (what == "bin") bin = BinLike(addr);
        else if (what == "safe") safe = addr;
        else revert("Flapper2/file-unrecognized-param");
    }
    function cage() external note auth {
        live = 0;
        loot();
        vat.move(address(this), msg.sender, vat.good(address(this)));
    }

    // --- Utils ---
    function loot() internal {
        uint own = coin.balanceOf(address(this));
        if (own > 0) {
          coin.approve(address(join), own);
          join.join(safe, own);
        }
    }

    // --- Buyout ---
    function kick(uint lot, uint bid) external auth returns (uint id) {
        require(live == 1, "Flapper2/not-live");
        require(mutex == 0, "Flapper2/non-null-mutex");
        mutex = 1;

        require(kicks < uint(-1), "Flapper2/overflow");
        require(safe != address(0), "Flapper2/no-safe");
        require(both(path[0] != address(0), path[1] != address(0)), "Flapper2/null-path");
        require(mul(div(lot, RAY), RAY) == lot, "Flapper2/wasted-lot");

        id = ++kicks;

        uint own = coin.balanceOf(address(this));
        require(fund(lot, address(bin)) == true, "Flapper2/cannot-fund");
        uint bid = bin.tkntkn(bin.INPUT(), div(lot, RAY), address(this), path);

        require(bid > 0, "Flapper2/invalid-bid");
        require(coin.balanceOf(address(this)) == own, "Flapper2/cannot-buy");
        require(gov.balanceOf(address(this)) >= bid, "Flapper2/bid-not-received");

        loot();

        if (vat.good(address(this)) > 0) {
          vat.move(address(this), safe, vat.good(address(this)));
        }
        gov.burn(address(this), gov.balanceOf(address(this)));

        emit Kick(id, lot, address(bin));

        mutex = 0;
    }
    function fund(uint lot, address guy) internal auth returns (bool) {
        uint own = coin.balanceOf(address(this));
        vat.move(msg.sender, address(this), lot);
        join.exit(address(this), div(lot, RAY));
        if (add(own, div(lot, RAY)) != coin.balanceOf(address(this))) {
          return false;
        }
        return coin.approve(guy, lot);
    }
}
