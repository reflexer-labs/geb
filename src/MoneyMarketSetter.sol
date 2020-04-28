pragma solidity ^0.5.15;

import "./Logging.sol";
import "./ExponentialMath.sol";

contract PipLike {
    function peek() external returns (bytes32, bool);
    function zzz() external view returns (uint64);
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
    function drip() external;
    function base() external view returns (uint256);
}

contract PotLike {
    function rho() external view returns (uint);
    function drip() external returns (uint);
    function file(bytes32, uint256) external;
    function sr() external view returns (uint256);
}

/***
  MoneyMarketSetterOne is a PI controller for a pegged coin.
  It automatically adjusts the stability fee and the savings rate according to deviations from the peg.

  It does not change the redemption price but rather tries to maintain a strong peg without the need
  for continuous governance intervention.

  This Pop takes into consideration the deviation between the latest market price and the target price.
***/
// contract Pop1 is LibNote, Exp {
//     // --- Auth ---
//     mapping (address => uint) public wards;
//     function rely(address guy) external note auth { wards[guy] = 1; }
//     function deny(address guy) external note auth { wards[guy] = 0; }
//     modifier auth {
//         require(wards[msg.sender] == 1, "Pop1/not-authorized");
//         _;
//     }
//
//     // --- Structs ---
//     struct PI {
//         uint go;   // deviation multiplier
//         uint how;  // integral sensitivity parameter
//     }
//     struct Firm {
//         uint up;
//         uint down;
//     }
//     struct Rate {
//         uint sf;
//         uint sr;
//     }
//
//     int256  public path; // latest type of deviation
//
//     uint256 public fix;  // market price                                                 [ray]
//     uint256 public tau;  // when fix was last updated
//     uint256 public bowl; // accrued time since the deviation has been positive/negative
//
//     uint256 public trim; // deviation from target price at which rates are recalculated  [ray]
//     uint256 public cup;  // time to spend for rates to come back to normal
//     uint256 public pace; // default time to spend in order to bring rates back to normal
//
//     uint256 public span; // spread between sf and sr
//     uint256 public bulk; // a proportion of bowl
//
//     uint256 public live; // access flag
//
//     PI      public core; // PI multipliers
//     Rate    public norm; // default rates
//     Rate    public lack; // per-second rates for bringing jug.base and pot.sr back to default
//     Firm    public fsf;  // bounds for stability fee
//     Firm    public fsr;  // bounds for savings rate
//
//     PipLike  public pip;
//     SpotLike public spot;
//     PotLike  public pot;
//     JugLike  public jug;
//
//     constructor(
//       address spot_,
//       address pot_,
//       address jug_
//     ) public {
//         wards[msg.sender] = 1;
//         fix  = RAY;
//         span = RAY;
//         bulk = RAY;
//         tau  = now;
//         spot = SpotLike(spot_);
//         pot  = PotLike(pot_);
//         jug  = JugLike(jug_);
//         core = PI(RAY, 0);
//         fsf  = Firm(MAX, MAX);
//         fsr  = Firm(MAX, MAX);
//         norm = Rate(RAY, RAY);
//         lack = Rate(RAY, RAY);
//         live = 1;
//     }
//
//     // --- Administration ---
//     function file(bytes32  what, address addr) external note auth {
//         require(live == 1, "Pop1/not-live");
//         if (what == "pip") pip = PipLike(addr);
//         else if (what == "spot") spot = SpotLike(addr);
//         else if (what == "jug") jug = JugLike(addr);
//         else if (what == "pot") pot = PotLike(addr);
//         else revert("Pop1/file-unrecognized-param");
//     }
//     function file(bytes32 what, uint256 val) external note auth {
//         require(live == 1, "Pop1/not-live");
//         if (what == "trim") trim = val;
//         else if (what == "span") span = val;
//         else if (what == "bulk") bulk = val;
//         else if (what == "pace") pace = val;
//         else if (what == "sf") {
//           require(val >= norm.sr, "Pop1/small-sf");
//           norm.sf = val;
//         }
//         else if (what == "sr") {
//           require(val <= norm.sf, "Pop1/big-sr");
//           norm.sr = val;
//         }
//         else if (what == "how")  {
//           core.how  = val;
//         }
//         else if (what == "go") {
//           core.go = val;
//         }
//         else if (what == "fsf-up") {
//           if (fsf.down != MAX) require(val >= fsf.down, "Pop1/small-up");
//           fsf.up = val;
//         }
//         else if (what == "fsf-down") {
//           if (fsf.up != MAX) require(val <= fsf.up, "Pop1/big-down");
//           fsf.down = val;
//         }
//         else if (what == "fsr-up") {
//           if (fsr.down != MAX) require(val >= fsr.down, "Pop1/small-up");
//           fsr.up = val;
//         }
//         else if (what == "fsr-down") {
//           if (fsr.up != MAX) require(val <= fsr.up, "Pop1/big-down");
//           fsr.down = val;
//         }
//         else revert("Pop1/file-unrecognized-param");
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
//     function sub(uint x, uint y) internal pure returns (uint z) {
//         z = x - y;
//         require(z <= x);
//     }
//     function sub(uint x, int y) internal pure returns (uint z) {
//         z = x - uint(y);
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
//         require(y > 0);
//         z = x / y;
//         require(z <= x);
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
//     function comp(uint x, uint32 wide) internal view returns (uint z) {
//         /**
//           Use the Exp formulas to compute the per-second rate.
//           After the initial computation we need to divide by 2^precision.
//         **/
//         (uint raw, uint heed) = pow(x, RAY, 1, wide);
//         z = div((raw * RAY), (2 ** heed));
//     }
//
//     // --- Utils ---
//     function both(bool x, bool y) internal pure returns (bool z) {
//         assembly{ z := and(x, y)}
//     }
//     function either(bool x, bool y) internal pure returns (bool z) {
//         assembly{ z := or(x, y)}
//     }
//     function era() internal view returns (uint) {
//         return block.timestamp;
//     }
//     function site(uint x, uint y) internal view returns (int z) {
//         z = (x >= y) ? int(-1) : int(1);
//     }
//     // Compute the per-second base rate
//     function br(uint256 x) internal pure returns (uint256 z) {
//         return RAY + delt(x, RAY);
//     }
//     // Compute the per-second 'gap rate' taking into consideration a spread
//     function gr(uint256 x) internal view returns (uint256 z) {
//         return RAY + div(mul(delt(x, RAY), RAY), span);
//     }
//     // Add more seconds that passed since the deviation has been constantly positive/negative
//     function grab(uint x) internal {
//         bowl = add(bowl, x);
//     }
//     // Set the current deviation direction
//     function rash(int site_) internal {
//         path = (path == 0) ? site_ : -path;
//     }
//     // Calculate the per-second rate that needs to be applied to x in order to get to y in wide seconds
//     function folk(uint x, uint y, uint32 wide) internal view returns (uint z) {
//         if (x == y) return RAY;
//         (uint max, uint min) = (x > y) ? (x, y) : (y, x);
//         z = comp(br(mul(max, RAY) / min), wide);
//         z = (x > y) ? sub(RAY, sub(z, RAY)) : add(RAY, sub(z, RAY));
//     }
//     // Calculate per year rate with a multiplier (go) and a per second sensitivity parameter (how)
//     function full(uint x, uint y) internal view returns (uint z) {
//         z = add(add(div(mul(sub(mul(x, RAY) / y, RAY), core.go), RAY), RAY), mul(core.how, bowl));
//     }
//     // Add/subtract calculated rates from default/current ones
//     function mix(uint sf_, uint sr_, int site_) internal view returns (uint x, uint y) {
//         x = add(jug.base(), mul(site_, sub(sf_, RAY)));
//         y = add(pot.sr(), mul(site_, sub(sr_, RAY)));
//     }
//     function adj(uint val, uint par, int site_) public view returns (uint256, uint256) {
//         // Calculate adjusted annual rate
//         uint full_ = (site_ == 1) ? full(par, val) : full(val, par);
//
//         // Calculate the per-second stability fee and per-second savings rate
//         uint sf_ = comp(br(full_), SPY);
//         uint sr_ = (span == RAY) ? sf_ : comp(gr(full_), SPY);
//
//         // If the deviation is positive, we set a negative rate and vice-versa
//         (sf_, sr_) = mix(sf_, sr_, site_);
//
//         // The stability fee might have bounds so make sure you don't pass them
//         sf_ = (sf_ < fsf.down && fsf.down != MAX) ? fsf.down : sf_;
//         sf_ = (sf_ > fsf.up && fsf.up != MAX)     ? fsf.up   : sf_;
//
//         // The savings rate might have bounds so make sure you don't pass them
//         sr_ = (sr_ < fsr.down && fsr.down != MAX) ? fsr.down : sr_;
//         sr_ = (sr_ > fsr.up && fsr.up != MAX)     ? fsr.up   : sr_;
//
//         // Adjust savings rate so it's smaller or equal to stability fee
//         sr_ = (sr_ > sf_) ? sf_ : sr_;
//
//         return (sf_, sr_);
//     }
//
//     // --- Feedback Mechanism ---
//     function back() external note {
//         require(live == 1, "Pop1/not-live");
//         uint gap = sub(era(), tau);
//         require(gap > 0, "Pop1/optimized");
//         // Fetch par
//         uint par = spot.par();
//         // Get price feed updates
//         (bytes32 val, bool has) = pip.peek();
//         // Initialize rates
//         uint sf_; uint sr_;
//         // If the OSM has a value
//         if (has) {
//           // Compute the deviation and whether it's negative/positive
//           uint dev  = delt(ray(uint(val)), par);
//           int site_ = site(ray(uint(val)), par);
//           // If the deviation is at least 'trim'
//           if (dev >= trim) {
//             // Restart cup
//             cup  = 0;
//             /**
//               If the current deviation is the same as the latest deviation, add seconds
//               passed to bowl using grab(). Otherwise change the latest deviation type
//               and restart bowl
//             **/
//             (site_ == path) ? grab(gap) : rash(site_);
//             // Compute the new per-second rate
//             (sf_, sr_) = adj(ray(uint(val)), par, site_);
//             // Set the new rates
//             pry(sf_, sr_);
//           } else {
//             // Restart latest deviation type
//             path = 0;
//             // Set cup
//             cup = (bowl >= pace) ? pace : bowl;
//             cup = (pace == 0) ? bowl : cup;
//             // Restart bowl
//             bowl = 0;
//             // TEMPORARY: set default rates right away
//             pry(norm.sf, norm.sr);
//             // // Adjust rates so they go toward their default values
//             // turn();
//           }
//           // Make sure you store the latest price as a ray
//           fix = ray(uint(val));
//           // Also store the timestamp of the update
//           tau = era();
//         }
//     }
//     // function turn() internal {
//     //     if (either(bowl > 0, pace == 0)) return;
//     //     uint gap = sub(now, pace);
//     //     cup = (gap > cup) ? 0 : sub(cup, gap);
//     //     if (cup == 0) {
//     //       lack = Rate(RAY, RAY);
//     //       pry(norm.sf, norm.sr);
//     //       return;
//     //     }
//     //     // Update rates with per-second lack settings
//     //     uint sf_ = jug.base();
//     //     uint sr_ = pot.sr();
//     //     if (both(gap > 0, sf_ != norm.sf)) {
//     //       sf_ = rmul(rpow(lack.sf, gap, RAY), sf_);
//     //       sf_ = either(both(lack.sf > RAY, sf_ > norm.sf), both(lack.sf < RAY, sf_ < norm.sf)) ? norm.sf : sf_;
//     //     }
//     //     if (both(gap > 0, sr_ != norm.sr)) {
//     //       sr_ = rmul(rpow(lack.sr, gap, RAY), sr_);
//     //       sr_ = either(both(lack.sr > RAY, sr_ > norm.sr), both(lack.sr < RAY, sr_ < norm.sr)) ? norm.sr : sr_;
//     //     }
//     //     // Make sure sr is not bigger than sf
//     //     sr_ = (sr_ > sf_) ? sf_ : sr_;
//     //     // Update lack
//     //     lack.sf = folk(sf_, norm.sf, uint32(cup));
//     //     lack.sr = folk(sr_, norm.sr, uint32(cup));
//     //     // Set new rates
//     //     pry(sf_, sr_);
//     //     // Set the last time we updated the current set rates toward their default values
//     //     pace = now;
//     // }
//     function pry(uint sf_, uint sr_) internal {
//         jug.drip();
//         jug.file("base", sf_);
//
//         pot.drip();
//         pot.file("sr", sr_);
//     }
// }
