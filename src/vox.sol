/// vox.sol -- target rate feedback mechanism

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

pragma solidity ^0.5.15;

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

contract JugLike {
    function file(bytes32, uint) external;
    function drip() external;
}

// --- Base TRFM setup contract that other models inherit from ---
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
    uint256 public span; // spread between msr and sf
    uint256 public age;  // when mpr was last updated
    uint256 public trim; // deviation from tpr at which rates are recalculated
    uint256 public rest; // minimum time between updates
    uint256 public live; // access flag

    mapping(int256 => int256) public how; // adjustment multiplier when pulling towards tpr

    PipLike  public pip;
    MaiLike  public tkn;
    JugLike  public jug;
    SpotLike public spot;

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
        require(live == 1, "Vox/not-live");
        if (what == "pip") pip = PipLike(addr);
        else if (what == "jug") jug = JugLike(addr);
        else if (what == "spot") spot = SpotLike(addr);
        else revert("Vox/file-unrecognized-param");
    }
    function file(bytes32 what, int256 side, int256 val) external note auth {
        require(live == 1, "Vox/not-live");
        require(side == -1 || side == 1, "Vox/invalid-side");
        require(val <= SPY && val >= -SPY, "Vox/val-exceeds-limits");
        if (what == "how") how[side] = val;
        else revert("Vox/file-unrecognized-param");
    }
    function cage() external note auth {
        live = 0;
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;
    int256  constant SPY = 31536000;
    uint256 constant SUP = 10 ** 9;
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
    function div(uint x, uint y) internal pure returns (uint z) {
        return x / y;
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
    function inj(uint256 x, uint256 y) internal view returns (uint256 z) {
        return y + div(mul(delt(x, y), RAY), span);
    }

    // --- Rate Setter ---
    function pull(uint msr, uint sf) internal note {
        tkn.drip();
        tkn.file("msr", msr);

        jug.drip();
        jug.file("base", sf);
    }
}

// --- TRFM that allows both savings rate and stability fee to go negative ---
contract Vox1 is Vox {
    constructor(
      address tkn_,
      address spot_,
      uint256 tpr_
    ) public {
        wards[msg.sender] = 1;
        tpr = tpr_;
        span = 10 ** 27;
        tkn = MaiLike(tkn_);
        spot = SpotLike(spot_);
        live = 1;
    }

    // --- Administration ---
    function file(bytes32 what, uint256 val) external note auth {
        require(live == 1, "Vox/not-live");
        if (what == "trim") trim = val;
        else if (what == "span") span = val;
        else if (what == "rest") rest = val;
        else revert("Vox/file-unrecognized-param");
    }

    // --- Utils ---
    function adj(uint val) public view returns (uint256, uint256) {
        int way_ = way(val, tpr);

        (uint raw, uint precision) = pow(prj(val, tpr), RAY, 1, uint32(add(uint(SPY), how[way_])));
        uint sf = (raw * RAY) / (2 ** precision);
        sf = (way_ == 1) ? sf : tpr - sub(sf, tpr);

        (raw, precision) = pow(inj(val, tpr), RAY, 1, uint32(add(uint(SPY), how[way_])));
        uint msr = (raw * RAY) / (2 ** precision);
        msr = (way_ == 1) ? msr : tpr - sub(msr, tpr);

        if (way_ == 1) {
          (sf, msr) = (msr, sf);
        }

        return (sf, msr);
    }

    // --- Feedback Mechanism ---
    function back() external note {
        require(live == 1, "Vox/not-live");
        require(sub(era(), age) > rest, "Vox/optimized");
        (bytes32 val, bool has) = pip.peek();
        uint msr; uint sf;
        if (has) {
          uint dev = delt(mul(uint(val), SUP), tpr);
          if (dev >= trim) {
            (msr, sf) = adj(mul(uint(val), SUP));
            pull(msr, sf);
          }
          else {
            uint par = spot.par();
            if (par != tpr) {
              (msr, sf) = adj(par);
              pull(msr, sf);
            }
          }
          mpr = mul(uint(val), SUP);
          age = era();
        }
    }
}

// --- TRFM that bounds the stability fee ---
contract Vox2 is Vox {
    uint256 public up = 2 ** 255;   // upper per-second bound for sf
    uint256 public down = 2 ** 255; // bottom per-second bound for sf

    uint256 constant public MAX = 2 ** 255;

    // --- Administration ---
    function file(bytes32 what, uint256 val) external note auth {
        require(live == 1, "Vox/not-live");
        if (what == "trim") trim = val;
        else if (what == "span") span = val;
        else if (what == "up") up = val;
        else if (what == "down") down = val;
        else if (what == "rest") rest = val;
        else revert("Vox/file-unrecognized-param");
    }

    // --- Utils ---
    function adj(uint val) public view returns (uint256, uint256) {
        int way_ = way(val, tpr);

        (uint raw, uint precision) = pow(prj(val, tpr), RAY, 1, uint32(add(uint(SPY), how[way_])));
        uint sf = (raw * RAY) / (2 ** precision);
        sf = (way_ == 1) ? sf : tpr - sub(sf, tpr);

        (raw, precision) = pow(inj(val, tpr), RAY, 1, uint32(add(uint(SPY), how[way_])));
        uint msr = (raw * RAY) / (2 ** precision);
        msr = (way_ == 1) ? msr : tpr - sub(msr, tpr);

        if (way_ == 1) {
          (sf, msr) = (msr, sf);
        }

        sf = (sf < down && down != MAX) ? down : sf;
        sf = (sf > up && down != MAX)   ? up : sf;

        return (sf, msr);
    }

    // --- Feedback Mechanism ---
    function back() external note {
        require(live == 1, "Vox/not-live");
        require(sub(era(), age) > rest, "Vox/optimized");
        (bytes32 val, bool has) = pip.peek();
        uint msr; uint sf;
        if (has) {
          uint dev = delt(mul(uint(val), SUP), tpr);
          if (dev >= trim) {
            (msr, sf) = adj(mul(uint(val), SUP));
            pull(msr, sf);
          }
          else {
            uint par = spot.par();
            if (par != tpr) {
              (msr, sf) = adj(par);
              pull(msr, sf);
            }
          }
          mpr = mul(uint(val), SUP);
          age = era();
        }
    }
}

// --- TRFM that doesn't force par to go back to tpr ---
contract Vox3 is Vox {
    // --- Administration ---
    function file(bytes32 what, uint256 val) external note auth {
        require(live == 1, "Vox/not-live");
        if (what == "trim") trim = val;
        else if (what == "span") span = val;
        else if (what == "rest") rest = val;
        else revert("Vox/file-unrecognized-param");
    }

    // --- Utils ---
    function adj(uint val) public view returns (uint256, uint256) {
        int way_ = way(val, tpr);

        (uint raw, uint precision) = pow(prj(val, tpr), RAY, 1, uint32(add(uint(SPY), how[way_])));
        uint sf = (raw * RAY) / (2 ** precision);
        sf = (way_ == 1) ? sf : tpr - sub(sf, tpr);

        (raw, precision) = pow(inj(val, tpr), RAY, 1, uint32(add(uint(SPY), how[way_])));
        uint msr = (raw * RAY) / (2 ** precision);
        msr = (way_ == 1) ? msr : tpr - sub(msr, tpr);

        if (way_ == 1) {
          (sf, msr) = (msr, sf);
        }

        return (sf, msr);
    }

    // --- Feedback Mechanism ---
    function back() external note {
        require(live == 1, "Vox/not-live");
        require(sub(era(), age) > rest, "Vox/optimized");
        (bytes32 val, bool has) = pip.peek();
        uint msr; uint sf;
        if (has) {
          uint dev = delt(mul(uint(val), SUP), tpr);
          if (dev >= trim) {
            (msr, sf) = adj(mul(uint(val), SUP));
            pull(msr, sf);
          }
          mpr = mul(uint(val), SUP);
          age = era();
        }
    }
}
