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
    function zzz() external view returns (uint256);
}

contract SpotLike {
    function drip() external returns (uint256);
    function rho() external view returns (uint256);
    function par() external returns (uint256);
    function file(bytes32,uint256) external;
}

contract JugLike {
    function file(bytes32, uint) external;
    function late() external view returns (bool);
    function lap() external view returns (bool);
    function leap() external;
}

contract PotLike {
    function rho() external view returns (uint);
    function drip() external returns (uint);
    function file(bytes32, uint256) external;
}

/**
  Vox1 is a PI controller that tries to set a rate of change for par according to the market
  price deviation from a target price.

  The rate of change is computed on-chain.

  The main external input is the price feed for the reflex-bond.

  Rates are computed so that they pull the market price in the opposite direction
  of the deviation.

  The deviation is always calculated against the most recent price update from the oracle. Check
  Vox2 for a controller that checks the deviation against a deviation accumulator.

  The integral component should be adjusted through governance by setting 'how'. Check Vox2 for
  an accumulator that computes the integral automatically.

  After deployment, you can set several parameters such as:
    - Default value for WAY
    - A deviation multiplier for faster response
    - A minimum deviation from the target price at which rate recalculation starts again
    - A sensitivity parameter to apply over time to increase/decrease the rates if the
      deviation is kept constant (the integral from PI)
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

    // --- Structs ---
    struct PID {
        uint go;   // deviation multiplier
        uint how;  // integral sensitivity parameter
    }

    int256  public path; // latest type of deviation

    uint256 public fix;  // market price                                                 [ray]
    uint256 public tau;  // when fix was last updated

    uint256 public trim; // deviation from target price at which rates are recalculated  [ray]
    uint256 public bowl; // accrued time since the deviation has been positive/negative

    uint256 public live; // access flag

    uint256 public deaf; // default per-second way                                       [ray]
    uint256 public wand; // rate of change for deaf                                      [ray]

    uint256 public up;   // upper bound for deaf                                         [ray]
    uint256 public down; // lower bound for deaf                                         [ray]

    uint256 public rho;  // last timestamp of then deaf was updated

    PID     public core;

    PipLike  public pip;
    SpotLike public spot;

    constructor(
      address spot_
    ) public {
        wards[msg.sender] = 1;
        fix  = RAY;
        deaf = RAY;
        wand = RAY;
        up   = MAX;
        down = MAX;
        tau  = now;
        rho  = now;
        spot = SpotLike(spot_);
        core = PID(RAY, 0);
        live = 1;
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
        require(live == 1, "Vox1/not-live");
        if (what == "pip") pip = PipLike(addr);
        else if (what == "spot") spot = SpotLike(addr);
        else revert("Vox1/file-unrecognized-param");
    }
    function file(bytes32 what, uint256 val) external note auth {
        require(live == 1, "Vox1/not-live");
        if (what == "trim") trim = val;
        else if (what == "deaf") deaf = val;
        else if (what == "wand") {
          require(val > 0, "Vox1/null-wand");
          wand = val;
        }
        else if (what == "how")  {
          core.how  = val;
        }
        else if (what == "go") {
          core.go = val;
        }
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
    function delt(uint x, uint y) internal pure returns (uint z) {
        z = (x >= y) ? x - y : y - x;
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
    function br(uint256 x) internal pure returns (uint256 z) {
        return RAY + delt(x, RAY);
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
        z = add(add(div(mul(sub(mul(x, RAY) / y, RAY), core.go), RAY), RAY), mul(core.how, bowl));
    }
    // Add/subtract calculated rate from default one
    function mix(uint way_, int site_) internal view returns (uint x) {
        if (site_ == 1) {
          x = (deaf > RAY) ? add(deaf, sub(way_, RAY)) : add(RAY, sub(way_, RAY));
        } else {
          x = (deaf < RAY) ? sub(deaf, sub(way_, RAY)) : sub(RAY, sub(way_, RAY));
        }
    }
    function adj(uint val, uint par, int site_) public view returns (uint256) {
        // Calculate adjusted annual rate
        uint full_ = (site_ == 1) ? full(par, val) : full(val, par);

        // Calculate the per-second base stability fee and target rate of change
        uint way_ = comp(br(full_));

        // If the deviation is positive, we set a negative rate and vice-versa
        way_ = mix(way_, site_);

        return way_;
    }

    // --- Feedback Mechanism ---
    function back() external note {
        require(live == 1, "Vox1/not-live");
        uint gap = sub(era(), tau);
        require(gap > 0, "Vox1/optimized");
        // Fetch par
        uint par = spot.par();
        // Get price feed updates
        (bytes32 val, bool has) = pip.peek();
        // If the OSM has a value
        if (has) {
          uint way_;
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
            // Compute the new per-second rate
            way_ = adj(ray(uint(val)), par, site_);
            // Set the new rate
            spot.file("way", way_);
          } else {
            // Restart counting the seconds since the deviation has been constant
            wipe();
            // Simply set default values for the rates
            spot.file("way", prod());
          }
          // Make sure you store the latest price as a ray
          fix = ray(uint(val));
          // Also store the timestamp of the update
          tau = era();
        }
    }
    function prod() internal returns (uint tmp) {
        tmp = (now > rho) ? rmul(rpow(wand, sub(now, rho), RAY), deaf) : deaf;

        // Deaf might have bounds so make sure you don't pass them
        if (down != MAX) {
          tmp = (tmp < down) ? down : tmp;
        }

        if (up != MAX) {
          tmp = (tmp > up) ? up : tmp;
        }

        deaf = tmp;
        rho  = now;
    }
}

/**
  Vox2 tries to set a rate of change for par according to recent market price deviations. It is meant to
  resemble a PID controller as closely as possible.

  The rate of change for par is computed on-chain.

  The elements that come into computing the rate of change are:
    - The current market price deviation from par (the proportional from PID)
    - An accumulator of the latest market price deviations from par (the integral from PID)
    - A derivative (slope) of the market/target price deviation computed using two accumulators (the derivative from PID)

  The main external input is the price feed for the reflex-bond.

  Rates are computed so that they pull the market price in the opposite direction
  of the deviation, toward the constantly updating target price.

  After deployment, you can set several parameters such as:

    - Default value for WAY
    - A rate of change for the default WAY value
    - A default deviation multiplier
    - A default sensitivity parameter to apply over time
    - A default multiplier for the slope of change in price
    - A minimum deviation from the target price accumulator at which rate recalculation starts again
**/
contract Vox2 is LibNote, Exp {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) external note auth { wards[guy] = 1; }
    function deny(address guy) external note auth { wards[guy] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Vox2/not-authorized");
        _;
    }

    // --- Structs ---
    struct PID {
        uint go;   // deviation multiplier
        uint how;  // integral sensitivity parameter
        uint gain; // slope/derivative multiplier
    }

    // -- Static & Default Variables ---
    uint256 public trim; // deviation at which rates are recalculated
    uint256 public deaf; // default per-second way
    uint256 public wand; // rate of change for deaf                                      [ray]

    uint256 public up;   // upper bound for deaf                                         [ray]
    uint256 public down; // lower bound for deaf                                         [ray]

    uint256 public rho;  // last timestamp of then deaf was updated

    uint256 public pan;  // length of the fat cron snapshot
    uint256 public bowl; // length of the fit cron snapshot
    uint256 public mug;  // length of the thin cron snapshot

    PID     public core; // default PID values

    uint256 public live; // access flag

    // --- Fluctuating Variables ---
    int256  public site; // latest type of deviation between the integral accumulator and par
    int256  public road; // latest type of deviation between fix and par
    uint256 public fix;  // latest market price

    // --- Accumulator ---
    int256[]  public cron; // deviation history
    uint256   public kick; // how many times we received new prices from OSM
    uint256   public zzz;  // latest update time of the OSM

    int256   public fat;  // accumulator used for derivative (old deviations) and manipulation resistance
    int256   public fit;  // integral accumulator
    int256   public thin; // accumulator used for derivative (newer deviations)

    // --- Other System Components ---
    PipLike  public pip;
    SpotLike public spot;

    constructor(
      address spot_,
      uint256 pan_,
      uint256 bowl_,
      uint256 mug_
    ) public {
        require(bowl_ == pan_ + mug_, "Vox2/pan-and-mug-must-sum-bowl");
        require(bowl_ > 0, "Vox2/null-bowl");
        wards[msg.sender] = 1;
        live = 1;
        fat  = 0;
        fit  = 0;
        thin = 0;
        pan  = pan_;
        bowl = bowl_;
        mug  = mug_;
        cron.push(0);
        deaf = RAY;
        wand = RAY;
        up   = MAX;
        down = MAX;
        rho  = now;
        zzz  = now;
        spot = SpotLike(spot_);
        fix  = spot.par();
        core = PID(RAY, RAY, RAY);
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
        require(live == 1, "Vox2/not-live");
        if (what == "pip") pip = PipLike(addr);
        else if (what == "spot") spot = SpotLike(addr);
        else revert("Vox2/file-unrecognized-param");
    }
    function file(bytes32 what, uint256 val) external note auth {
        require(live == 1, "Vox2/not-live");
        if (what == "trim") trim = val;
        else if (what == "deaf") deaf = val;
        else if (what == "go")   core.go = val;
        else if (what == "how")  core.how = val;
        else if (what == "gain") core.gain = val;
        else if (what == "up") {
          if (down != MAX) require(val >= down, "Vox1/small-up");
          up = val;
        }
        else if (what == "down") {
          if (up != MAX) require(val <= up, "Vox1/big-down");
          down = val;
        }
        else revert("Vox2/file-unrecognized-param");
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
    function mul(int x, int y) internal pure returns (int z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function div(uint x, uint y) internal pure returns (uint z) {
        return x / y;
    }
    function delt(uint x, uint y) internal pure returns (uint z) {
        z = (x >= y) ? x - y : y - x;
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
    function comp(uint x) internal view returns (uint z) {
        /**
          Use the Exp formulas to compute the per-second rate.
          After the initial computation we need to divide by 2^precision.
        **/
        (uint raw, uint heed) = pow(x, RAY, 1, SPY);
        z = div((raw * RAY), (2 ** heed));
    }

    // --- Utils ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }
    function era() internal view returns (uint) {
        return block.timestamp;
    }
    function pole(uint x, uint y) internal view returns (int z) {
        z = (x >= y) ? int(-1) : int(1);
    }
    // Compute the per second 'base rate'
    function br(uint256 x) internal pure returns (uint256 z) {
        return RAY + delt(x, RAY);
    }
    // Set the opposite integral deviation
    function rash(int site_) internal {
        site = (site == 0) ? site_ : -site;
    }
    // Set the opposite market price deviation
    function wild(int road_) internal {
        road = (road == 0) ? road_ : -road;
    }
    function dox(uint x, uint y) internal view returns (int z) {
        uint dev  = delt(x, y);
        int pole_ = pole(x, y);
        return mul(-pole_, dev);
    }
    // Update accumulators and deviation history
    function acc(int x) internal {
        // Update deviation history
        cron.push(x);
        // Update the integral accumulator
        fit  = add(fit, x);
        if (cron.length > bowl) {fit  = sub(fit, cron[sub(cron.length, add(bowl, uint(1)))]);}
        // Update the derivative accumulators
        thin = add(thin, x);
        if (cron.length > mug)  {thin = sub(thin, cron[sub(cron.length, add(mug, uint(1)))]);}
        fat  = sub(fit, thin);
    }
    // Calculate yearly rate according to PID settings
    function full(uint x, uint y, int site_, int road_) public view returns (int P, int I, int D, uint pid) {
        P   = mul(mul(road_, sub(x, y)), core.go) / int(RAY);

        I   = mul(int(-1), int(mul(fit, core.how) / int(RAY)));

        if (either(fat < 0 && thin > 0, fat > 0 && thin < 0)) {
          D = int(RAY);
        } else if (either(fat == 0, thin == 0)) {
          D = int(RAY);
        } else {
          D = mul(thin, RAY) / fat;
        }

        D   = mul(D, core.gain) / int(RAY);

        int  diff = mul(add(P, I), D) / int(RAY);
        uint den  = (site_ > 0) ? add(y, diff) : add(x, diff);

        pid = (site_ > 0) ? mul(den, RAY) / x : mul(x, RAY) / den;
    }
    // Add/subtract calculated rates from default ones
    function mix(uint way_, int site_) internal view returns (uint x) {
        if (site_ == 1) {
          x = (deaf > RAY) ? add(deaf, sub(way_, RAY)) : add(RAY, sub(way_, RAY));
        } else {
          x = (deaf < RAY) ? sub(deaf, sub(way_, RAY)) : sub(RAY, sub(way_, RAY));
        }
    }
    function adj(uint val, uint par, int site_, int road_) public view returns (uint256) {
        // Calculate adjusted annual rate
        (, , , uint full_) = (road_ == 1) ? full(par, val, site_, road_) : full(val, par, site_, road_);

        // Calculate the per-second target rate of change
        uint way_ = comp(br(full_));

        // If the deviation is positive, we set a negative rate and vice-versa
        way_ = mix(way_, site_);

        return way_;
    }

    // --- Feedback Mechanism ---
    function back() external note {
        require(live == 1, "Vox2/not-live");
        // Get feed latest price timestamp
        uint zzz_ = pip.zzz();
        // If there's no new time in the feed, simply return
        if (zzz_ <= zzz) return;
        // Get price feed updates
        (bytes32 val, bool has) = pip.peek();
        // If the OSM has a value
        if (has) {
          uint par = spot.par();
          // Update accumulators and deviation history
          acc(dox(ray(uint(val)), par));
          // If we don't have enough datapoints, return
          if (either(either(cron.length <= mug, cron.length <= bowl), cron.length <= pan)) return;
          // Initialize new rate
          uint way_;
          // Compute the deviation of the fit accumulator from par
          int dev = (fit == 0) ? 0 : fit / int(bowl);
          // Compute the opposite of the current accumulator sign
          int site_ = (dev < 0) ? int(1) : int(-1);
          // Compute the opposite of the current market price deviation
          int road_ = pole(ray(uint(val)), par);
          // If the deviation is at least 'trim'
          if (dev >= int(trim) || dev <= -int(trim)) {
            /**
              If the current deviation is different than the latest one,
              update the latest one
            **/
            if (site_ != site) rash(site_);
            if (road_ != road) wild(road_);
            // Compute the new per-second rate
            way_ = adj(ray(uint(val)), par, site_, road_);
            spot.file("way", way_);
          } else {
            // Restart deviation types
            site = 0;
            road = 0;
            // Set default rate
            spot.file("way", prod());
          }
          // Store the latest market price
          fix = ray(uint(val));
          // Store the timestamp of the oracle update
          zzz = zzz_;
        }
    }
    function prod() internal returns (uint tmp) {
        tmp = (now > rho) ? rmul(rpow(wand, sub(now, rho), RAY), deaf) : deaf;

        // Deaf might have bounds so make sure you don't pass them
        if (down != MAX) {
          tmp = (tmp < down) ? down : tmp;
        }

        if (up != MAX) {
          tmp = (tmp > up) ? up : tmp;
        }

        deaf = tmp;
        rho  = now;
    }
}

/***
  Vox3 is a rate setter for a pegged coin. It automatically adjusts the stability fee and the savings
  rate according to deviations from the peg.

  As opposed to the previous Vox flavours, this one does not change the target price (par) but rather
  tries to maintain a strong peg.
***/
// contract Vox3 is LibNote, Exp {
//     // --- Auth ---
//     mapping (address => uint) public wards;
//     function rely(address guy) external note auth { wards[guy] = 1; }
//     function deny(address guy) external note auth { wards[guy] = 0; }
//     modifier auth {
//         require(wards[msg.sender] == 1, "Vox3/not-authorized");
//         _;
//     }
//
//     int256  public path; // latest type of deviation
//     uint256 public fix;  // market price                                                 [ray]
//     uint256 public span; // spread between way and sf
//     uint256 public tau;  // when fix was last updated
//     uint256 public trim; // deviation from target price at which rates are recalculated  [ray]
//     uint256 public go;   // deviation multiplier                                         [ray]
//     uint256 public how;  // sensitivity parameter
//     uint256 public bowl; // accrued time since the deviation has been positive/negative
//     uint256 public live; // access flag
//
//     uint256 public dawn; // default per-second sf                                        [ray]
//     uint256 public dusk; // default per-second way                                       [ray]
//
//     uint256 public up;   // upper per-second bound for sf
//     uint256 public down; // bottom per-second bound for sf
//
//     uint256  public way;  // the Target Rate of Adjustment
//
//     PipLike  public pip;
//     JugLike  public jug;
//     SpotLike public spot;
//
//     constructor(
//       address jug_,
//       address spot_
//     ) public {
//         wards[msg.sender] = 1;
//         fix  = 10 ** 27;
//         span = 10 ** 27;
//         dawn = 10 ** 27;
//         dusk = 10 ** 27;
//         go   = 10 ** 27;
//         way  = 10 ** 27;
//         up   = 2 ** 255;
//         down = 2 ** 255;
//         tau  = now;
//         jug  = JugLike(jug_);
//         spot = SpotLike(spot_);
//         live = 1;
//     }
//
//     // --- Administration ---
//     function file(bytes32 what, address addr) external note auth {
//         require(live == 1, "Vox3/not-live");
//         if (what == "pip") pip = PipLike(addr);
//         else if (what == "jug") jug = JugLike(addr);
//         else if (what == "spot") spot = SpotLike(addr);
//         else revert("Vox3/file-unrecognized-param");
//     }
//     function file(bytes32 what, uint256 val) external note auth {
//         require(live == 1, "Vox3/not-live");
//         if (what == "trim") trim = val;
//         else if (what == "span") span = val;
//         else if (what == "dawn") dawn = val;
//         else if (what == "dusk") dusk = val;
//         else if (what == "how")  how  = val;
//         else if (what == "go")   go   = val;
//         else if (what == "up") {
//           if (down != MAX) require(val >= down, "Vox3/small-up");
//           up = val;
//         }
//         else if (what == "down") {
//           if (up != MAX) require(val <= up, "Vox3/big-down");
//           down = val;
//         }
//         else revert("Vox3/file-unrecognized-param");
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
//     function delt(uint x, uint y) internal pure returns (uint z) {
//         z = (x >= y) ? x - y : y - x;
//     }
//     function rmul(uint x, uint y) internal pure returns (uint z) {
//         // alsites rounds down
//         z = mul(x, y) / RAY;
//     }
//     function rpow(uint x, uint n, uint base) internal pure returns (uint z) {
//         assembly {
//             switch x case 0 {switch n case 0 {z := base} default {z := 0}}
//             default {
//                 switch mod(n, 2) case 0 { z := base } default { z := x }
//                 let half := div(base, 2)  // for rounding.
//                 for { n := div(n, 2) } n { n := div(n,2) } {
//                     let xx := mul(x, x)
//                     if iszero(eq(div(xx, x), x)) { revert(0,0) }
//                     let xxRound := add(xx, half)
//                     if lt(xxRound, xx) { revert(0,0) }
//                     x := div(xxRound, base)
//                     if mod(n,2) {
//                         let zx := mul(z, x)
//                         if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
//                         let zxRound := add(zx, half)
//                         if lt(zxRound, zx) { revert(0,0) }
//                         z := div(zxRound, base)
//                     }
//                 }
//             }
//         }
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
//     // Compute the per second 'base rate' without spread
//     function br(uint256 x) internal pure returns (uint256 z) {
//         return RAY + delt(x, RAY);
//     }
//     // Compute per second 'gap rate' taking into consideration a spread
//     function gr(uint256 x) internal view returns (uint256 z) {
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
//     // Calculate per year rate with a multiplier (go) and a per second sensitivity parameter (how)
//     function full(uint x, uint y) internal view returns (uint z) {
//         z = add(add(div(mul(sub(mul(x, RAY) / y, RAY), go), RAY), RAY), mul(how, bowl));
//     }
//     // Add/subtract calculated rates from default ones
//     function mix(uint sf_, uint way_, int site_) internal view returns (uint x, uint y) {
//         if (site_ == 1) {
//           x = (dawn > RAY) ? add(dawn, sub(sf_, RAY)) : add(RAY, sub(sf_, RAY));
//           y = (dusk > RAY) ? add(dusk, sub(way_, RAY)) : add(RAY, sub(way_, RAY));
//         } else {
//           x = (dawn < RAY) ? sub(dawn, sub(sf_, RAY)) : sub(RAY, sub(sf_, RAY));
//           y = (dusk < RAY) ? sub(dusk, sub(way_, RAY)) : sub(RAY, sub(way_, RAY));
//         }
//     }
//     function adj(uint val, uint par, int site_) public view returns (uint256, uint256) {
//         // Calculate adjusted annual rate
//         uint full_ = (site_ == 1) ? full(par, val) : full(val, par);
//
//         // Calculate the per-second base stability fee and target rate of change
//         uint way_ = comp(br(full_));
//         uint sf_  = (span == RAY) ? way_ : comp(gr(full_));
//
//         // If the deviation is positive, we set a negative rate and vice-versa
//         (sf_, way_) = mix(sf_, way_, site_);
//
//         // The stability fee might have bounds so make sure you don't pass them
//         sf_ = (sf_ < down && down != MAX) ? down : sf_;
//         sf_ = (sf_ > up && up != MAX)     ? up : sf_;
//
//         return (sf_, way_);
//     }
//
//     // --- Feedback Mechanism ---
//     function back() external note {
//         require(live == 1, "Vox3/not-live");
//         // If overall sf is negative and vow doesn't have enough surplus left, skip jug dripping
//         bool late = jug.late();
//         if (late) {
//           require(!jug.lap(), "Vox3/jug-not-dripped");
//         }
//         uint gap = sub(era(), tau);
//         require(gap > 0, "Vox3/optimized");
//         // Update par and then fetch it
//         flex(gap);
//         uint par = spot.par();
//         // Get price feed updates
//         (bytes32 val, bool has) = pip.peek();
//         // If the OSM has a value
//         if (has) {
//           uint sf;
//           uint way_;
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
//             (sf, way_) = adj(ray(uint(val)), par, site_);
//             // Set the new rates
//             pull(sf, way_, late);
//           } else {
//             // Restart counting the seconds since the deviation has been constant
//             wipe();
//             // Simply set default values for the rates
//             pull(dawn, dusk, late);
//           }
//           // Make sure you store the latest price as a ray
//           fix = ray(uint(val));
//           // Also store the timestamp of the update
//           tau = era();
//         }
//     }
//     // Set the new target price
//     function flex(uint gap) internal note {
//         // Update target price
//         if (way > 0) {
//           uint par = spot.par();
//           uint tmp = rmul(rpow(way, gap, RAY), par);
//           spot.file("par", tmp);
//         }
//     }
//     // Set the new base stability fee and target rate of change
//     function pull(uint sf, uint way_, bool late) internal note {
//         // Update sf
//         if (late) {
//           /***
//             If we lap for a long time and then go positive with the sf,
//             there will be an abrupt change in ilks' rates. To avoid this,
//             ilks with negative rates (base + duty) will have rho updated
//           ***/
//           jug.leap();
//         }
//         (sf > 0) ? jug.file("base", sf) : jug.file("base", RAY);
//         // Update rate of change
//         way = way_;
//     }
// }

/***
  Vox4 is similar to Vox3 although it has an extra lever to pull in order to maintain the long-term peg.

  If the savings rate or the stability fee cannot be further decreased, it will try to briefly detach the
  coin from its peg. After the market and target prices come back close to each other, it will
  try to bring the target price back to its original state
***/
// contract Vox4 is LibNote, Exp {
//     // --- Auth ---
//     mapping (address => uint) public wards;
//     function rely(address guy) external note auth { wards[guy] = 1; }
//     function deny(address guy) external note auth { wards[guy] = 0; }
//     modifier auth {
//         require(wards[msg.sender] == 1, "Vox4/not-authorized");
//         _;
//     }
//
//     // --- Structs ---
//     struct PID {
//         uint go;   // deviation multiplier
//         uint how;  // integral sensitivity parameter
//     }
//
//     int256  public path; // latest type of deviation
//
//     uint256 public fix;  // market price                                                 [ray]
//     uint256 public tau;  // when fix was last updated
//
//     uint256 public trim; // deviation from target price at which rates are recalculated  [ray]
//     uint256 public bowl; // accrued time since the deviation has been positive/negative
//
//     uint256 public live; // access flag
//
//     uint256 public deaf; // default per-second way                                       [ray]
//     uint256 public wand; // rate of change for deaf                                      [ray]
//
//     uint256 public up;   // upper bound for deaf                                         [ray]
//     uint256 public down; // lower bound for deaf                                         [ray]
//
//     uint256 public rho;  // last timestamp of then deaf was updated
//
//     PID     public core;
//
//     PipLike  public pip;
//     JugLike  public jug;
//     SpotLike public spot;
//
//     constructor(
//       address jug_,
//       address spot_
//     ) public {
//         wards[msg.sender] = 1;
//         fix  = RAY;
//         deaf = RAY;
//         wand = RAY;
//         up   = MAX;
//         down = MAX;
//         tau  = now;
//         rho  = now;
//         jug  = JugLike(jug_);
//         spot = SpotLike(spot_);
//         core = PID(RAY, 0);
//         live = 1;
//     }
//
//     // --- Administration ---
//     function file(bytes32 what, address addr) external note auth {
//         require(live == 1, "Vox4/not-live");
//         if (what == "pip") pip = PipLike(addr);
//         else if (what == "jug") jug = JugLike(addr);
//         else if (what == "spot") spot = SpotLike(addr);
//         else revert("Vox4/file-unrecognized-param");
//     }
//     function file(bytes32 what, uint256 val) external note auth {
//         require(live == 1, "Vox4/not-live");
//         if (what == "trim") trim = val;
//         else if (what == "deaf") deaf = val;
//         else if (what == "wand") {
//           require(val > 0, "Vox4/null-wand");
//           wand = val;
//         }
//         else if (what == "how")  {
//           core.how  = val;
//         }
//         else if (what == "go") {
//           core.go = val;
//         }
//         else if (what == "up") {
//           if (down != MAX) require(val >= down, "Vox4/small-up");
//           up = val;
//         }
//         else if (what == "down") {
//           if (up != MAX) require(val <= up, "Vox4/big-down");
//           down = val;
//         }
//         else revert("Vox4/file-unrecognized-param");
//     }
//     function cage() external note auth {
//         live = 0;
//     }
//
//     // --- Math ---
//     uint256 constant RAY = 10 ** 27;
//     uint32  constant SPY = 31536000;
//     uint256 constant MAX = 2 ** 255;
//
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
//     function delt(uint x, uint y) internal pure returns (uint z) {
//         z = (x >= y) ? x - y : y - x;
//     }
//     function rmul(uint x, uint y) internal pure returns (uint z) {
//         // alsites rounds down
//         z = mul(x, y) / RAY;
//     }
//     function rpow(uint x, uint n, uint base) internal pure returns (uint z) {
//         assembly {
//             switch x case 0 {switch n case 0 {z := base} default {z := 0}}
//             default {
//                 switch mod(n, 2) case 0 { z := base } default { z := x }
//                 let half := div(base, 2)  // for rounding.
//                 for { n := div(n, 2) } n { n := div(n,2) } {
//                     let xx := mul(x, x)
//                     if iszero(eq(div(xx, x), x)) { revert(0,0) }
//                     let xxRound := add(xx, half)
//                     if lt(xxRound, xx) { revert(0,0) }
//                     x := div(xxRound, base)
//                     if mod(n,2) {
//                         let zx := mul(z, x)
//                         if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
//                         let zxRound := add(zx, half)
//                         if lt(zxRound, zx) { revert(0,0) }
//                         z := div(zxRound, base)
//                     }
//                 }
//             }
//         }
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
//     function br(uint256 x) internal pure returns (uint256 z) {
//         return RAY + delt(x, RAY);
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
//     // Calculate per year rate with a multiplier (go) and a per second sensitivity parameter (how)
//     function full(uint x, uint y) internal view returns (uint z) {
//         z = add(add(div(mul(sub(mul(x, RAY) / y, RAY), core.go), RAY), RAY), mul(core.how, bowl));
//     }
//     // Add/subtract calculated rate from default one
//     function mix(uint way_, int site_) internal view returns (uint x) {
//         if (site_ == 1) {
//           x = (deaf > RAY) ? add(deaf, sub(way_, RAY)) : add(RAY, sub(way_, RAY));
//         } else {
//           x = (deaf < RAY) ? sub(deaf, sub(way_, RAY)) : sub(RAY, sub(way_, RAY));
//         }
//     }
//     function adj(uint val, uint par, int site_) public view returns (uint256) {
//         // Calculate adjusted annual rate
//         uint full_ = (site_ == 1) ? full(par, val) : full(val, par);
//
//         // Calculate the per-second base stability fee and target rate of change
//         uint way_ = comp(br(full_));
//
//         // If the deviation is positive, we set a negative rate and vice-versa
//         way_ = mix(way_, site_);
//
//         return way_;
//     }
//
//     // --- Feedback Mechanism ---
//     function back() external note {
//         require(live == 1, "Vox4/not-live");
//         uint gap = sub(era(), tau);
//         require(gap > 0, "Vox4/optimized");
//         // Fetch par
//         uint par = spot.par();
//         // Get price feed updates
//         (bytes32 val, bool has) = pip.peek();
//         // If the OSM has a value
//         if (has) {
//           uint way_;
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
//             // Compute the new per-second rate
//             way_ = adj(ray(uint(val)), par, site_);
//             // Set the new rate
//             spot.file("way", way_);
//           } else {
//             // Restart counting the seconds since the deviation has been constant
//             wipe();
//             // Simply set default values for the rates
//             spot.file("way", prod());
//           }
//           // Make sure you store the latest price as a ray
//           fix = ray(uint(val));
//           // Also store the timestamp of the update
//           tau = era();
//         }
//     }
//     function prod() internal returns (uint tmp) {
//         tmp = (now > rho) ? rmul(rpow(wand, sub(now, rho), RAY), deaf) : deaf;
//
//         // Deaf might have bounds so make sure you don't pass them
//         if (down != MAX) {
//           tmp = (tmp < down) ? down : tmp;
//         }
//
//         if (up != MAX) {
//           tmp = (tmp > up) ? up : tmp;
//         }
//
//         deaf = tmp;
//         rho  = now;
//     }
// }
