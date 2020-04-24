// // This program is free software: you can redistribute it and/or modify
// // it under the terms of the GNU General Public License as published by
// // the Free Software Foundation, either version 3 of the License, or
// // (at your option) any later version.
//
// // This program is distributed in the hope that it will be useful,
// // but WITHOUT ANY WARRANTY; without even the implied warranty of
// // MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// // GNU General Public License for more details.
//
// // You should have received a copy of the GNU General Public License
// // along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// pragma solidity ^0.5.15;
//
// import "./Logging.sol";
// import "./LinkedList.sol";
//
// contract CDPEngineLike {
//     function collateralTypes(bytes32) external view returns (
//         uint256 debtAmount,        // wad
//         uint256 accumulatedRates   // ray
//     );
//     function updateAccumulatedRate(bytes32,address,int) external;
//     function coinBalance(address) external view returns (uint);
// }
//
// contract TaxCollector is Logging {
//     using LinkedList for LinkedList.List;
//
//     // --- Auth ---
//     mapping (address => uint) public authorizedAccounts;
//     function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
//     function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
//     modifier isAuthorized {
//         require(authorizedAccounts[msg.sender] == 1, "TaxCollector/account-not-authorized");
//         _;
//     }
//
//     // --- Data ---
//     struct CollateralType {
//         uint256 lendingRate;
//         uint256 latestTaxCollection;
//     }
//     struct TaxReceiver {
//         uint256 canWithdrawTaxes;
//         uint256 taxPercentage;
//         address account;
//     }
//     struct TaxOverview {
//         uint256 totalTaxPercentage;
//         uint256 taxReceiverId;
//     }
//
//     mapping (bytes32 => CollateralType)                  public collateralTypes;
//     mapping (bytes32 => TaxOverview)                     public taxOverview;
//     mapping (address => uint256)                         public usedTaxAccount;
//     mapping (bytes32 => mapping(uint256 => TaxReceiver)) public taxReceivers;
//
//     address    public accountingEngine;
//     uint256    public globalStabilityFee;
//     uint256    public taxReceiverLimit;
//     uint256    public latestTaxReceiver;
//
//     bytes32[]        public   collateralList;
//     LinkedList.List  internal receiverList;
//
//     CDPEngineLike    public cdpEngine;
//
//     // --- Init ---
//     constructor(address cdpEngine_) public {
//         authorizedAccounts[msg.sender] = 1;
//         cdpEngine = CDPEngineLike(cdpEngine_);
//     }
//
//     // --- Math ---
//     function rpow(uint x, uint n, uint b) internal pure returns (uint z) {
//       assembly {
//         switch x case 0 {switch n case 0 {z := b} default {z := 0}}
//         default {
//           switch mod(n, 2) case 0 { z := b } default { z := x }
//           let half := div(b, 2)  // for rounding.
//           for { n := div(n, 2) } n { n := div(n,2) } {
//             let xx := mul(x, x)
//             if iszero(eq(div(xx, x), x)) { revert(0,0) }
//             let xxRound := add(xx, half)
//             if lt(xxRound, xx) { revert(0,0) }
//             x := div(xxRound, b)
//             if mod(n,2) {
//               let zx := mul(z, x)
//               if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
//               let zxRound := add(zx, half)
//               if lt(zxRound, zx) { revert(0,0) }
//               z := div(zxRound, b)
//             }
//           }
//         }
//       }
//     }
//     uint256 constant RAY     = 10 ** 27;
//     uint256 constant HUNDRED = 10 ** 29;
//     uint256 constant ONE     = 1;
//
//     function add(uint x, uint y) internal pure returns (uint z) {
//         z = x + y;
//         require(z >= x);
//     }
//     function add(int x, int y) internal pure returns (int z) {
//         z = x + y;
//         if (y <= 0) require(z <= x);
//         if (y  > 0) require(z > x);
//     }
//     function sub(uint x, uint y) internal pure returns (uint z) {
//         require((z = x - y) <= x);
//     }
//     function sub(int x, int y) internal pure returns (int z) {
//         z = x - y;
//         require(y <= 0 || z <= x);
//         require(y >= 0 || z >= x);
//     }
//     function diff(uint x, uint y) internal pure returns (int z) {
//         z = int(x) - int(y);
//         require(int(x) >= 0 && int(y) >= 0);
//     }
//     function mul(uint x, int y) internal pure returns (int z) {
//         z = int(x) * y;
//         require(int(x) >= 0);
//         require(y == 0 || z / y == int(x));
//     }
//     function mul(int x, int y) internal pure returns (int z) {
//         require(y == 0 || (z = x * y) / y == x);
//     }
//     function rmul(uint x, uint y) internal pure returns (uint z) {
//         z = x * y;
//         require(y == 0 || z / y == x);
//         z = z / RAY;
//     }
//
//     function both(bool x, bool y) internal pure returns (bool z) {
//         assembly{ z := and(x, y)}
//     }
//     function either(bool x, bool y) internal pure returns (bool z) {
//         assembly{ z := or(x, y)}
//     }
//
//     // --- Administration ---
//     function initializeCollateralType(bytes32 collateralType) external emitLog isAuthorized {
//         CollateralType storage collateralType_ = collateralTypes[collateralType];
//         require(collateralType_.lendingRate == 0, "TaxCollector/collateral-type-already-init");
//         collateralType_.lendingRate = RAY;
//         collateralType_.latestTaxCollection = now;
//         collateralList.push(collateralType);
//     }
//     function modifyParameters(bytes32 collateralType, bytes32 parameter, uint data) external emitLog isAuthorized {
//         require(now == collateralTypes[collateralType].latestTaxCollection, "TaxCollector/latest-tax-collection-not-updated");
//         if (parameter == "lendingRate") collateralTypes[collateralType].lendingRate = data;
//         else revert("TaxCollector/modify-unrecognized-param");
//     }
//     function modifyParameters(bytes32 parameter, uint data) external emitLog isAuthorized {
//         if (parameter == "globalStabilityFee") globalStabilityFee = data;
//         else if (parameter == "taxReceiverLimit") taxReceiverLimit = data;
//         else revert("TaxCollector/modify-unrecognized-param");
//     }
//     function modifyParameters(bytes32 parameter, address data) external emitLog isAuthorized {
//         require(data != address(0), "TaxCollector/null-data");
//         if (what == "accountingEngine") accountingEngine = data;
//         else revert("TaxCollector/modify-unrecognized-param");
//     }
//     function modifyParameters(bytes32 collateralType, uint256 parameter, uint256 val) external emitLog isAuthorized {
//         if (both(receiverList.isNode(parameter), taxReceivers[collateralType][parameter].taxPercentage > 0)) {
//             taxReceivers[collateralType][parameter].canWithdrawTaxes = val;
//         }
//         else revert("TaxCollector/unknown-tax-receiver");
//     }
//     function modifyParameters(
//       bytes32 collateralType,
//       uint256 position,
//       uint256 val,
//       address addr
//     ) external emitLog isAuthorized {
//         (latestTaxReceiver < position) ? createReceiver(collateralType, val, addr) : fix(collateralType, position, val);
//     }
//
//     // --- Stability Fee Receivers ---
//     function createReceiver(bytes32 collateralType, uint256 val, address addr) internal {
//         require(addr != address(0), "TaxCollector/null-receiver");
//         require(addr != accountingEngine, "TaxCollector/cannot-add-accounting-engine");
//         require(val > 0, "TaxCollector/null-val");
//         require(usedTaxAccount[addr] == 0, "TaxCollector/already-a-receiver");
//         require(add(receiverList.range(), ONE) <= taxReceiverLimit, "TaxCollector/exceeds-receiver-limit");
//         require(add(taxOverview[collateralType].taxPercentage, val) < HUNDRED, "TaxCollector/percentage-too-big");
//
//         usedTaxAccount[addr] = ONE;
//
//         taxOverview[collateralType].taxReceiverId = add(taxOverview[collateralType].taxReceiverId, ONE);
//         taxOverview[collateralType].totalTaxPercentage = add(taxOverview[collateralType].totalTaxPercentage, val);
//
//         taxReceivers[collateralType][taxOverview[collateralType].taxReceiverId].taxPercentage = val;
//         taxReceivers[collateralType][taxOverview[collateralType].taxReceiverId].gal = addr;
//
//         latestTaxReceiver = taxOverview[collateralType].taxReceiverId;
//         receiverList.push(taxOverview[collateralType].taxReceiverId, false);
//     }
//     function fix(bytes32 ilk, uint256 what, uint256 val) internal {
//         require(both(receiverList.isNode(what), heirs[ilk][what].cut > 0), "TaxCollector/unknown-heir");
//         if (val == 0) {
//           born[heirs[ilk][what].gal] = 0;
//           clan[ilk].cut  = sub(clan[ilk].cut, heirs[ilk][what].cut);
//           if (what == latestTaxReceiver) {
//             (, uint256 prev) = receiverList.prev(latestTaxReceiver);
//             latestTaxReceiver = prev;
//           }
//           receiverList.del(what);
//           delete(heirs[ilk][what]);
//         } else {
//           uint256 Cut = add(sub(clan[ilk].cut, heirs[ilk][what].cut), val);
//           require(Cut < HUNDRED, "TaxCollector/too-much-cut");
//           clan[ilk].cut                  = Cut;
//           heirs[ilk][clan[ilk].taxReceiverId].cut = val;
//         }
//     }
//
//     // --- Drip Utils ---
//     function late() public view returns (bool ko) {
//         for (uint i = 0; i < collateralList.length; i++) {
//           if (now > ilks[collateralList[i]].rho) {
//             ko = true;
//             break;
//           }
//         }
//     }
//     function lap() public view returns (bool ok, int rad) {
//         int  diff_;
//         uint Art;
//         int  good_ = -int(vat.good(accountingEngine));
//         for (uint i = 0; i < collateralList.length; i++) {
//           if (now > ilks[collateralList[i]].rho) {
//             (Art, )  = vat.ilks(collateralList[i]);
//             (, diff_) = drop(collateralList[i]);
//             rad = add(rad, mul(Art, diff_));
//           }
//         }
//         if (rad < 0) {
//           ok = (rad < good_) ? false : true;
//         } else {
//           ok = true;
//         }
//     }
//     function bend(uint globalStabilityFee_) public view returns (uint256 z) {
//         if (collateralList.length == 0) return globalStabilityFee_;
//         for (uint i = 0; i < collateralList.length; i++) {
//           z = add(z, add(globalStabilityFee_, ilks[collateralList[i]].duty));
//         }
//         z = z / collateralList.length;
//     }
//
//     // --- Gifts Utils ---
//     function range() public view returns (uint) {
//         return receiverList.range();
//     }
//     function isNode(uint256 _node) public view returns (bool) {
//         return receiverList.isNode(_node);
//     }
//
//     // --- Stability Fee Collection ---
//     function drop(bytes32 ilk) public view returns (uint, int) {
//         (, uint prev) = vat.ilks(ilk);
//         uint rate  = rmul(rpow(add(globalStabilityFee, ilks[ilk].duty), sub(now, ilks[ilk].rho), RAY), prev);
//         int  diff_ = diff(rate, prev);
//         return (rate, diff_);
//     }
//     function drip() external note {
//         for (uint i = 0; i < collateralList.length; i++) {
//             drip(collateralList[i]);
//         }
//     }
//     function drip(bytes32 ilk) public note returns (uint) {
//         if (now <= ilks[ilk].rho) {
//           (, uint prev) = vat.ilks(ilk);
//           return prev;
//         }
//         (uint rate, int rad) = drop(ilk);
//         roll(ilk, rad);
//         (, rate) = vat.ilks(ilk);
//         ilks[ilk].rho = now;
//         return rate;
//     }
//     function roll(bytes32 ilk, int rad) internal {
//         (uint Art, )  = vat.ilks(ilk);
//         uint256 prev_ = latestTaxReceiver;
//         int256  much;
//         int256  good_;
//         while (prev_ > 0) {
//           good_ = -int(vat.good(heirs[ilk][prev_].gal));
//           much  = mul(int(heirs[ilk][prev_].cut), rad) / int(HUNDRED);
//           much  = (both(mul(Art, much) < 0, good_ > mul(Art, much))) ? good_ / int(Art) : much;
//           if ( both(much != 0, either(rad >= 0, both(much < 0, heirs[ilk][prev_].canWithdrawTaxes > 0))) ) {
//             vat.fold(ilk, heirs[ilk][prev_].gal, much);
//           }
//           (, prev_) = receiverList.prev(prev_);
//         }
//         good_ = -int(vat.good(accountingEngine));
//         much  = mul(sub(HUNDRED, clan[ilk].cut), rad) / int(HUNDRED);
//         much  = (both(mul(Art, much) < 0, good_ > mul(Art, much))) ? good_ / int(Art) : much;
//         if (much != 0) vat.fold(ilk, accountingEngine, much);
//     }
// }
