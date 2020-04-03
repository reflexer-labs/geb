/// bin.sol -- Connector between core contracts and DEX aggregator

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

import "../lib.sol";
import "./ione.sol";
import "./ierc20.sol";

contract Bin is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Bin/not-authorized");
        _;
    }

    Ione      public ione;

    uint256   public omit;
    uint256   public part;
    uint256   public live;

    constructor() public {
        wards[msg.sender] = 1;
        live = 1;
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
        require(live == 1, "Bin/not-live");
        require(addr != address(0), "Bin/null-addr");
        if (what == "ione") ione = Ione(addr);
        else revert("Bin/file-unrecognized-param");
    }
    function file(bytes32 what, uint256 val) external note auth {
        require(live == 1, "Bin/not-live");
        if (what == "part") part = val;
        else if (what == "omit") omit = val;
        else revert("Bin/file-unrecognized-param");
    }
    function cage() external note auth {
        live = 0;
    }

    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }

    // --- Conversion ---
    function tkntkn(
        address lad,
        address src,
        address dst,
        uint256 wad
    ) external note {
        require(lad != address(0), "Bin/null-lad");
        require(src != dst, "Bin/same-tkn");
        require(both(src != address(0), dst != address(0)), "Bin/cannot-convert-eth");
        require(wad > 0, "Bin/null-wad");
        // Get converted amount
        (uint256 got, uint256[] memory range) = IoneLike(address(ione)).getExpectedReturn(
          IERC20(src),
          IERC20(dst),
          wad,
          part,
          omit
        );
        require(got > 0, "Bin/got-zero");
        // Allow aggregator to transfer tokens
        IERC20(src).approve(address(ione), 0);
        IERC20(src).approve(address(ione), wad);
        // Get starting dst balance
        uint256 open = IERC20(dst).balanceOf(address(this));
        // Swap tokens
        ione.swap.value(0)(
          IERC20(src),
          IERC20(dst),
          wad,
          got,
          range,
          omit
        );
        // Get close balance
        uint256 close = IERC20(dst).balanceOf(address(this));
        require(add(open, got) <= close, "Bin/cannot-swap");
        // Send tokens to lad
        IERC20(dst).transfer(lad, got);
    }
    function ethtkn(
        address lad,
        address dst
    ) external note payable {
        require(lad != address(0), "Bin/null-lad");
        require(dst != address(0), "Bin/null-dst");
        require(msg.value > 0, "Bin/null-msg-value");
        // Get converted amount
        (uint256 got, uint256[] memory range) = IoneLike(address(ione)).getExpectedReturn(
          IERC20(address(0)),
          IERC20(dst),
          msg.value,
          part,
          omit
        );
        require(got > 0, "Bin/got-zero");
        // Get starting dst balance
        uint256 open = IERC20(dst).balanceOf(address(this));
        // Swap tokens
        ione.swap.value(msg.value)(
          IERC20(address(0)),
          IERC20(dst),
          msg.value,
          got,
          range,
          omit
        );
        // Get close balance
        uint256 close = IERC20(dst).balanceOf(address(this));
        require(add(open, got) <= close, "Bin/cannot-swap");
        // Send tokens to lad
        IERC20(dst).transfer(lad, got);
    }
    function tkneth(
        address lad,
        address src,
        uint256 wad
    ) external note {
        require(lad != address(0), "Bin/null-lad");
        require(src != address(0), "Bin/null-src");
        require(wad > 0, "Bin/null-wad");
        // Get converted amount
        (uint256 got, uint256[] memory range) = IoneLike(address(ione)).getExpectedReturn(
          IERC20(src),
          IERC20(address(0)),
          wad,
          part,
          omit
        );
        require(got > 0, "Bin/got-zero");
        // Allow aggregator to transfer tokens
        IERC20(src).approve(address(ione), 0);
        IERC20(src).approve(address(ione), wad);
        // Get starting ETH balance
        uint256 open = address(this).balance;
        // Swap tokens
        ione.swap.value(0)(
          IERC20(src),
          IERC20(address(0)),
          wad,
          got,
          range,
          omit
        );
        // Get close balance
        uint256 close = address(this).balance;
        require(add(open, got) <= close, "Bin/cannot-swap");
        // Send ETH to lad
        address(address(uint160(lad))).transfer(got);
    }

    function() external payable {
        revert();
    }
}
