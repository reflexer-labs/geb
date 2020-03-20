/// vox.sol -- target price feed trigger

// Copyright (C) 2016, 2017  Nikolai Mushegian <nikolai@dapphub.com>
// Copyright (C) 2016, 2017  Daniel Brockman <daniel@dapphub.com>
// Copyright (C) 2017        Rain Break <rainbreak@riseup.net>
// Copyright (C) 2020        Stefan C. Ionescu <stefanionescu@protonmail.com>

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

pragma solidity ^0.5.12;

import "./lib.sol";
import "./exp.sol";

contract PipLike {
    function peek() external returns (bytes32, bool);
}

contract MaiLike {
    function file(bytes32, uint256) external;
    function drip() public returns (uint);
}

contract SpotLike {
    function par() external returns (uint256);
}

contract Vox is LibNote, Exp {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) external note auth { wards[guy] = 1; }
    function deny(address guy) external note auth { wards[guy] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Vox/not-authorized");
        _;
    }

    uint256 public mpr;  // market price
    uint256 public tpr;  // target price
    uint256 public age;  // when mpr was last updated
    uint256 public trim; // deviation from tpr at which rate is recalculated
    uint256 public live; // access flag

    mapping(uint256 => mapping(uint256 => uint256)) public how; // adjustment multiplier when pulling toward tpr

    PipLike  public pip;
    MaiLike  public mai;
    SpotLike public spot;

    constructor(
      address mai_,
      address spot_,
      uint256 tpr_
    ) public {
        wards[msg.sender] = 1;
        mai = MaiLike(mai_);
        spot = SpotLike(spot_);
        tpr = tpr_;
        live = 1;
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
        require(live == 1, "Vox/not-live");
        if (what == "pip") pip = PipLike(addr);
        else if (what == "spot") spot = SpotLike(addr);
        else revert("Vox/file-unrecognized-param");
    }
    function file(bytes32 what, uint256 val) external note auth {
        require(live == 1, "Vox/not-live");
        if (what == "trim") trim = val;
        else revert("Vox/file-unrecognized-param");
    }
    function file(bytes32 what, uint256 trg, uint256 val) external note auth {
        require(live == 1, "Vox/not-live");
        if (what == "how") how[trg] = val;
        else revert("Vox/file-unrecognized-param");
    }
    function cage() external note auth {
        live = 0;
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;
    uint32  constant SPY = 31536000;
    function add(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x);
    }
    function add(uint x, int y) internal pure returns (uint z) {
        z = x + uint(y);
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function add(int x, int y) internal pure returns (int z) {
        z = x + y;
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        z = x - y;
        require(z <= x);
    }
    function sub(uint x, int y) internal pure returns (uint z) {
        z = x - uint(y);
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }
    function sub(int x, int y) internal pure returns (int z) {
        z = x - y;
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function mul(int x, uint y) internal pure returns (int z) {
        require(y == 0 || (z = x * int(y)) / int(y) == x);
    }
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, RAY), y / 2) / y;
    }

    // --- Utils ---
    function era() internal view returns (uint) {
        return block.timestamp;
    }
    function delt(uint x, uint y) internal pure returns (uint z) {
        z = (x >= y) ? x - y : y - x;
    }
    function way(uint x, uint y) internal view returns (int z) {
        z = (x >= y) ? int(-1) : int(1);
    }
    function prj(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return y + delt(x, y);
    }
    function adj(uint val) public view returns (uint256) {
        (uint raw, uint precision) = pow(prj(val, tpr), RAY, 1, SPY);
        uint adj = (raw * RAY) / (2 ** precision);
        adj = (way(val, tpr) == 1) ? adj : tpr - sub(adj, tpr);
        return adj;
    }

    // --- Feedback Mechanism ---
    function back() public note {
        require(live == 1, "Vox/not-live");
        require(sub(era(), age) > 0, "Vox/optimized");
        (bytes32 val, bool has) = pip.peek();
        require(uint(val) != mpr, "Vox/same-mpr");
        if (has) {
          uint dev = delt(mul(uint(val), 10 ** 9), tpr);
          if (dev >= trim) {
            pull(adj(mul(uint(val), 10 ** 9)));
          }
          else {
            uint par = spot.par();
            if (par != tpr) {
              pull(adj(par));
            }
          }
          mpr = mul(uint(val), 10 ** 9);
          age = era();
        }
    }
    function pull(uint msr) internal note {
        mai.drip();
        mai.file("msr", msr);
    }
}
