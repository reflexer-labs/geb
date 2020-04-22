/// purse.sol -- stability fee treasury

// Copyright (C) 2020 Stefan C. Ionescu <stefanionescu@protonmail.com>

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
    function move(address,address,uint) external;
    function good(address) external view returns (uint);
}
contract GemLike {
    function balanceOf(address) external view returns (uint);
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
}
contract CoinJoinLike {
    function coin() external view returns (address);
    function join(address, uint) external;
    function exit(address, uint) external;
}

contract Purse is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Purse/not-authorized");
        _;
    }

    mapping(address => uint) public allowance;

    VatLike      public vat;
    GemLike      public coin;
    CoinJoinLike public coinJoin;

    address public vow;

    uint256 public full;
    uint256 public times;
    uint256 public gap;
    uint256 public cron;
    uint256 public pin;
    uint256 public rho;
    uint256 public live;

    constructor(address vat_, address vow_, address coinJoin_, uint gap_) public {
        require(address(CoinJoinLike(coinJoin_).coin()) != address(0), "Purse/null-coin");
        wards[msg.sender] = 1;
        vat      = VatLike(vat_);
        vow      = vow_;
        coinJoin = CoinJoinLike(coinJoin_);
        coin     = GemLike(coinJoin.coin());
        gap      = gap_;
        rho      = now;
        times    = 1;
        live     = 1;
    }

    // --- Math ---
    uint256 constant WAD = 10 ** 18;

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
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
        require(live == 1, "Purse/not-live");
        require(addr != address(0), "Purse/null-addr");
        if (what == "vow") vow = addr;
        else revert("Purse/file-unrecognized-param");
    }
    function file(bytes32 what, uint val) external note auth {
        require(live == 1, "Purse/not-live");
        if (what == "times") times = val;
        else if (what == "full") full = val;
        else if (what == "gap") gap = val;
        else revert("Purse/file-unrecognized-param");
    }
    function cage() external note auth {
        vat.move(address(this), vow, vat.good(address(this)));
        live = 0;
    }

    // --- Utils ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- Allowance ---
    function allow(address gal, uint val) external note auth {
        require(gal != address(0), "Purse/null-gal");
        allowance[gal] = val;
    }

    // --- Stability Fee Transfer (Governance) ---
    function give(address gal, uint val) external note auth {
        require(gal != address(0), "Purse/null-gal");
        cron = add(cron, val);
        vat.move(address(this), gal, val);
    }
    function take(address gal, uint val) external note auth {
        vat.move(gal, address(this), val);
    }

    // --- Stability Fee Transfer (Approved Gals) ---
    function pull(address gal, address tkn, uint val) external returns (bool) {
        if (
          either(
            add(coin.balanceOf(address(this)), vat.good(address(this))) < val,
            either(
              either(
                allowance[msg.sender] < val,
                either(gal == address(0), val == 0)
              ),
              tkn != address(coin)
            )
          )
        ) {
          return false;
        }
        allowance[msg.sender] = sub(allowance[msg.sender], val);
        cron = add(cron, val);
        uint exit = (coin.balanceOf(address(this)) >= val) ? 0 : sub(val, coin.balanceOf(address(this)));
        if (exit > 0) {
          coinJoin.exit(address(this), exit);
        }
        coin.transfer(gal, val);
        return true;
    }

    // --- Treasury Maintenance ---
    function keep() external {
        require(now >= add(rho, gap), "Purse/gap-not-passed");
        // Compute current pin and minimum reserves
        uint pin_  = sub(cron, pin);
        uint min   = (both(full > 0, full <= mul(times, pin_) / WAD)) ? full : mul(times, pin_) / WAD;
        // Set internal vars
        pin = cron;
        rho = now;
        // Join all coins in system
        if (coin.balanceOf(address(this)) > 0) {
          coinJoin.join(address(this), coin.balanceOf(address(this)));
        }
        // Check if we have too much money
        if (vat.good(address(this)) > min) {
          // transfer surplus to vow
          vat.move(address(this), vow, sub(vat.good(address(this)), min));
        }
    }
}
