/// vox.sol -- rate setter

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

contract SpotLike {
    function par() external view returns (uint256);
    function file(bytes32,uint256) external;
}

contract JugLike {
    function file(bytes32, uint) external;
    function late() external view returns (bool);
    function lap() external view returns (bool);
}

contract PotLike {
    function rho() external view returns (uint);
    function drip() external returns (uint);
    function file(bytes32, uint256) external;
}

/**
  Vox1 tries to set both a base stability fee for all collateral types and a rate of
  change for par according to the market price deviation from a target price.

  The rate of change and the per-second base stability fee are computed on-chain.
  The main external input is the price feed for the reflex-bond.

  Rates are computed so that they pull the market price in the opposite direction
  of the deviation.

  After deployment, you can set several parameters such as:

    - Default values for WAY/SF
    - Bounds for SF
    - Minimum time between feedback updates
    - A spread between SF/WAY
    - A minimum deviation from the target price at which rate recalculation starts again
    - A sensitivity parameter to apply over time to increase/decrease the rates if the
      deviation is kept constant
**/
contract Vox1 is LibNote, Exp {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) external note auth { wards[guy] = 1; }
    function deny(address guy) external note auth { wards[guy] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Vox1/not-authorized");
        _;
    }

    int256  public path; // latest type of deviation
    uint256 public fix;  // market price                                                 [ray]
    uint256 public span; // spread between way and sf
    uint256 public tau;  // when fix was last updated
    uint256 public trim; // deviation from target price at which rates are recalculated  [ray]
    uint256 public rest; // minimum time between updates
    uint256 public go;   // deviation multiplier                                         [ray]
    uint256 public how;  // sensitivity parameter
    uint256 public bowl; // accrued time since the deviation has been positive/negative
    uint256 public live; // access flag

    uint256 public dawn; // default per-second sf                                        [ray]
    uint256 public dusk; // default per-second way                                       [ray]

    uint256 public up;   // upper per-second bound for sf
    uint256 public down; // bottom per-second bound for sf

    uint256  public rho;  // time of last drip
    uint256  public way;  // the Target Rate of Adjustment

    PipLike  public pip;
    JugLike  public jug;
    SpotLike public spot;

    constructor(
      address jug_,
      address spot_
    ) public {
        wards[msg.sender] = 1;
        fix  = 10 ** 27;
        span = 10 ** 27;
        dawn = 10 ** 27;
        dusk = 10 ** 27;
        go   = 10 ** 27;
        up   = 2 ** 255;
        down = 2 ** 255;
        jug  = JugLike(jug_);
        spot = SpotLike(spot_);
        rho  = now;
        live = 1;
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
        require(live == 1, "Vox1/not-live");
        if (what == "pip") pip = PipLike(addr);
        else if (what == "jug") jug = JugLike(addr);
        else if (what == "spot") spot = SpotLike(addr);
        else revert("Vox1/file-unrecognized-param");
    }
    function file(bytes32 what, uint256 val) external note auth {
        require(live == 1, "Vox1/not-live");
        if (what == "trim") trim = val;
        else if (what == "span") span = val;
        else if (what == "rest") rest = val;
        else if (what == "dawn") dawn = val;
        else if (what == "dusk") dusk = val;
        else if (what == "how")  how  = val;
        else if (what == "go")   go   = val;
        else if (what == "up") {
          if (down != MAX) require(val >= down, "Vox1/small-up");
          up = val;
        }
        else if (what == "down") {
          if (up != MAX) require(val <= up, "Vox1/big-down");
          down = val;
        }
        else revert("Vox1/file-unrecognized-param");
    }
    function cage() external note auth {
        live = 0;
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;
    uint32  constant SPY = 31536000;
    uint256 constant MAX = 2 ** 255;
    function ray(uint x) internal pure returns (uint z) {
        z = mul(x, 10 ** 9);
    }
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
    function rmul(uint x, uint y) internal pure returns (uint z) {
        // alsites rounds down
        z = mul(x, y) / RAY;
    }
    function rpow(uint x, uint n, uint base) internal pure returns (uint z) {
        assembly {
            switch x case 0 {switch n case 0 {z := base} default {z := 0}}
            default {
                switch mod(n, 2) case 0 { z := base } default { z := x }
                let half := div(base, 2)  // for rounding.
                for { n := div(n, 2) } n { n := div(n,2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0,0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0,0) }
                    x := div(xxRound, base)
                    if mod(n,2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0,0) }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }
    function delt(uint x, uint y) internal pure returns (uint z) {
        z = (x >= y) ? x - y : y - x;
    }
    function comp(uint x) internal view returns (uint z) {
        /**
          Use the Exp formulas to compute the per-second rate.
          After the initial computation we need to divide by 2^precision.
        **/
        (uint raw, uint heed) = pow(x, RAY, 1, SPY);
        z = div((raw * RAY), (2 ** heed));
    }

    // --- Utils ---
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }
    function era() internal view returns (uint) {
        return block.timestamp;
    }
    function site(uint x, uint y) internal view returns (int z) {
        z = (x >= y) ? int(-1) : int(1);
    }
    // Compute the per second 'base rate' without spread
    function br(uint256 x) internal pure returns (uint256 z) {
        return RAY + delt(x, RAY);
    }
    // Compute per second 'gap rate' taking into consideration a spread
    function gr(uint256 x) internal view returns (uint256 z) {
        return RAY + div(mul(delt(x, RAY), RAY), span);
    }
    // Add more seconds that passed since the deviation has been constantly positive/negative
    function grab(uint x) internal {
        bowl = add(bowl, x);
    }
    // Restart counting seconds since deviation has been constant
    function wipe() internal {
        bowl = 0;
        path = 0;
    }
    // Set the current deviation direction
    function rash(int site_) internal {
        path = (path == 0) ? site_ : -path;
    }
    // Calculate per year rate with a multiplier (go) and a per second sensitivity parameter (how)
    function full(uint x, uint y) internal view returns (uint z) {
        z = add(add(div(mul(sub(mul(x, RAY) / y, RAY), go), RAY), RAY), mul(how, bowl));
    }
    // Add/subtract calculated rates from default ones
    function mix(uint sf_, uint way_, int site_) internal view returns (uint x, uint y) {
        if (site_ == 1) {
          x = (dawn > RAY) ? add(dawn, sub(sf_, RAY)) : add(RAY, sub(sf_, RAY));
          y = (dusk > RAY) ? add(dusk, sub(way_, RAY)) : add(RAY, sub(way_, RAY));
        } else {
          x = (dawn < RAY) ? sub(dawn, sub(sf_, RAY)) : sub(RAY, sub(sf_, RAY));
          y = (dusk < RAY) ? sub(dusk, sub(way_, RAY)) : sub(RAY, sub(way_, RAY));
        }
    }
    function adj(uint val, uint par, int site_) public view returns (uint256, uint256) {
        // Calculate adjusted annual rate
        uint full_ = (site_ == 1) ? full(par, val) : full(val, par);

        // Calculate the per-second base stability fee and target rate of change
        uint way_ = comp(br(full_));
        uint sf_  = (span == RAY) ? way_ : comp(gr(full_));

        // If the deviation is positive, we set a negative rate and vice-versa
        (sf_, way_) = mix(sf_, way_, site_);

        // The stability fee might have bounds so make sure you don't pass them
        sf_ = (sf_ < down && down != MAX) ? down : sf_;
        sf_ = (sf_ > up && up != MAX)     ? up : sf_;

        return (sf_, way_);
    }

    // --- Target Price Updates ---
    function drip() public note returns (uint tmp) {
        require(now >= rho, "Vox1/invalid-now");
        uint par = spot.par();
        tmp = rmul(rpow(way, now - rho, RAY), par);
        spot.file("par", tmp);
        rho = now;
    }

    // --- Feedback Mechanism ---
    function back() external note {
        require(live == 1, "Vox1/not-live");
        // We need to have dripped in order to be able to file new rates
        require(rho == now, "Vox1/vox-not-dripped");
        // If overall sf is negative and vow doesn't have enough surplus left, skip jug dripping
        if (jug.late()) {
          require(!jug.lap(), "Vox1/jug-not-dripped");
        }
        uint gap = sub(era(), tau);
        // The gap between now and the last update time needs to be at least 'rest'
        require(gap >= rest, "Vox1/optimized");
        (bytes32 val, bool has) = pip.peek();
        // If the OSM has a value
        if (has) {
          uint sf; uint way_;
          uint par = spot.par();
          // Compute the deviation and whether it's negative/positive
          uint dev  = delt(ray(uint(val)), par);
          int site_ = site(ray(uint(val)), par);
          // If the deviation is at least 'trim'
          if (dev >= trim) {
            /**
              If the current deviation is the same as the latest deviation, add seconds
              passed to bowl using grab(). Otherwise change the latest deviation type
              and restart bowl
            **/
            (site_ == path) ? grab(gap) : rash(site_);
            // Compute the new per-second rates
            (sf, way_) = adj(ray(uint(val)), par, site_);
            // Set the new rates
            pull(sf, way_);
          } else {
            // Restart counting the seconds since the deviation has been constant
            wipe();
            // Simply set default values for the rates
            pull(dawn, dusk);
          }
          // Make sure you store the latest price as a ray
          fix = ray(uint(val));
          // Also store the timestamp of the update
          tau = era();
        }
    }
    // Set the new rate of change and base stability fee
    function pull(uint sf, uint way_) internal note {
        way = way_;
        jug.file("base", sf);
    }
}

/**
  Vox2 doesn't update par. It's more suitable for a pot/jug setup where
  coin holders earn interest on deposits
**/
// contract Vox2 is LibNote, Exp {
//     // --- Auth ---
//     mapping (address => uint) public wards;
//     function rely(address guy) external note auth { wards[guy] = 1; }
//     function deny(address guy) external note auth { wards[guy] = 0; }
//     modifier auth {
//         require(wards[msg.sender] == 1, "Vox2/not-authorized");
//         _;
//     }
//
//     int256  public path; // latest type of deviation
//     uint256 public fix;  // market price                                                 [ray]
//     uint256 public pole; // desired price                                                [ray]
//     uint256 public tau;  // when fix was last updated
//     uint256 public trim; // deviation from pole at which rates are recalculated          [ray]
//     uint256 public rest; // minimum time between updates
//     uint256 public how;  // sensitivity parameter
//     uint256 public go;   // starting weight for rates
//     uint256 public bowl; // accrued time since the deviation has been positive/negative
//     uint256 public live; // access flag
//
//     uint256 public dawn; // default per-second sf                                        [ray]
//     uint256 public dusk; // default per-second sr                                        [ray]
//
//     PipLike public pip;
//     JugLike public jug;
//     PotLike public pot;
//
//     constructor(
//       address jug_,
//       address pot_,
//       uint256 pole_
//     ) public {
//         wards[msg.sender] = 1;
//         fix  = 10 ** 27;
//         pole = pole_;
//         span = 10 ** 27;
//         dawn = 10 ** 27;
//         dusk = 10 ** 27;
//         jug  = JugLike(jug_);
//         pot  = PotLike(pot_);
//         rho  = now;
//         live = 1;
//     }
//
//     // --- Administration ---
//     function file(bytes32 what, address addr) external note auth {
//         require(live == 1, "Vox2/not-live");
//         if (what == "pip") pip = PipLike(addr);
//         else if (what == "jug") jug = JugLike(addr);
//         else if (what == "pot") pot = PotLike(addr);
//         else revert("Vox2/file-unrecognized-param");
//     }
//     function file(bytes32 what, uint256 val) external note auth {
//         require(live == 1, "Vox2/not-live");
//         if (what == "trim") trim = val;
//         else if (what == "rest") rest = val;
//         else if (what == "dawn") dawn = val;
//         else if (what == "dusk") dusk = val;
//         else if (what == "how")  how  = val;
//         else if (what == "go")   go   = val;
//         else revert("Vox2/file-unrecognized-param");
//     }
//     function cage() external note auth {
//         live = 0;
//     }
//
//     // --- Math ---
//     uint256 constant RAY = 10 ** 27;
//     uint32  constant SPY = 31536000;
//     uint256 constant MAX = 2 ** 255;
//     function ray(uint x) internal pure returns (uint z) {
//         z = mul(x, 10 ** 9);
//     }
//     function add(uint x, uint y) internal pure returns (uint z) {
//         z = x + y;
//         require(z >= x);
//     }
//     function add(uint x, int y) internal pure returns (uint z) {
//         z = x + uint(y);
//         require(y >= 0 || z <= x);
//         require(y <= 0 || z >= x);
//     }
//     function add(int x, int y) internal pure returns (int z) {
//         z = x + y;
//         require(y >= 0 || z <= x);
//         require(y <= 0 || z >= x);
//     }
//     function sub(uint x, uint y) internal pure returns (uint z) {
//         z = x - y;
//         require(z <= x);
//     }
//     function sub(uint x, int y) internal pure returns (uint z) {
//         z = x - uint(y);
//         require(y <= 0 || z <= x);
//         require(y >= 0 || z >= x);
//     }
//     function sub(int x, int y) internal pure returns (int z) {
//         z = x - y;
//         require(y <= 0 || z <= x);
//         require(y >= 0 || z >= x);
//     }
//     function mul(uint x, uint y) internal pure returns (uint z) {
//         require(y == 0 || (z = x * y) / y == x);
//     }
//     function mul(int x, uint y) internal pure returns (int z) {
//         require(y == 0 || (z = x * int(y)) / int(y) == x);
//     }
//     function div(uint x, uint y) internal pure returns (uint z) {
//         return x / y;
//     }
//     function rmul(uint x, uint y) internal pure returns (uint z) {
//         // alsites rounds down
//         z = mul(x, y) / RAY;
//     }
//     function delt(uint x, uint y) internal pure returns (uint z) {
//         z = (x >= y) ? x - y : y - x;
//     }
//     function comp(uint x) internal view returns (uint z) {
//         /**
//           Use the Exp formulas to compute the per-second rate.
//           After the initial computation we need to divide by 2^precision.
//         **/
//         (uint raw, uint heed) = pow(x, RAY, 1, SPY);
//         z = div((raw * RAY), (2 ** heed));
//     }
//
//     // --- Utils ---
//     function both(bool x, bool y) internal pure returns (bool z) {
//         assembly{ z := and(x, y)}
//     }
//     function era() internal view returns (uint) {
//         return block.timestamp;
//     }
//     function site(uint x, uint y) internal view returns (int z) {
//         z = (x >= y) ? int(-1) : int(1);
//     }
//     // Compute the per second rate without spread
//     function br(uint256 x) internal pure returns (uint256 z) {
//         return RAY + delt(x, RAY);
//     }
//     // Compute per second rate taking into consideration a spread
//     function sr(uint256 x) internal view returns (uint256 z) {
//         return RAY + div(mul(delt(x, RAY), RAY), span);
//     }
//     // Add more seconds that passed since the deviation has been constantly positive/negative
//     function grab(uint x) internal {
//         bowl = add(bowl, x);
//     }
//     // Restart counting seconds since deviation has been constant
//     function wipe() internal {
//         bowl = 0;
//         path = 0;
//     }
//     // Set the current deviation direction
//     function rash(int site_) internal {
//         path = (path == 0) ? site_ : -path;
//     }
//     function full(uint x, uint y) internal view returns (uint z) {
//         z = add(mul(x, RAY) / y, mul(how, bowl));
//     }
//     function adj(uint val, int site_) public view returns (uint256, uint256) {
//
//
//         // Calculate the per-second base stability fee and target rate of change
//         uint way_ = comp(br(full_));
//         uint sf_  = (span == RAY) ? way_ : comp(sr(full_));
//
//         // If the deviation is positive, we set a negative rate and vice-versa
//         (sf_, way_) = (site_ == 1) ? (sf_, way_) : (sub(RAY, sub(sf_, RAY)), sub(RAY, sub(way_, RAY)));
//
//         return (sf_, way_);
//     }
//
//     // --- Feedback Mechanism ---
//     function back() external note {
//         require(live == 1, "Vox2/not-live");
//         // We need to have dripped in order to be able to file new rates
//         require(both(pot.rho() == now, jug.late() == false), "Vox2/not-dripped");
//         uint gap = sub(era(), tau);
//         // The gap between now and the last update time needs to be at least 'rest'
//         require(gap >= rest, "Vox2/optimized");
//         (bytes32 val, bool has) = pip.peek();
//         // If the OSM has a value
//         if (has) {
//           uint sf; uint way_;
//           // Compute the deviation and whether it's negative/positive
//           uint dev  = delt(ray(uint(val)), par);
//           int site_ = site(ray(uint(val)), par);
//           // If the deviation is at least 'trim'
//           if (dev >= trim) {
//             /**
//               If the current deviation is the same as the latest deviation, add seconds
//               passed to bowl using grab(). Otherwise change the latest deviation type
//               and restart bowl
//             **/
//             (site_ == path) ? grab(gap) : rash(site_);
//             // Compute the new per-second rates
//             (sf, way_) = adj(ray(uint(val)), site_);
//             // Set the new rates
//             pull(sf, way_);
//           } else {
//             // Restart counting the seconds since the deviation has been constant
//             wipe();
//             // Simply set default values for the rates
//             pull(dawn, dusk);
//           }
//           // Make sure you store the latest price as a ray
//           fix = ray(uint(val));
//           // Also store the timestamp of the update
//           tau = era();
//         }
//     }
//     // Set the new savings rate and base stability fee
//     function pull(uint sf, uint sr) internal note {
//         pot.file("sr", sr);
//         jug.file("base", sf);
//     }
// }
