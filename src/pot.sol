/// pot.sol -- Mai Savings Rate

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
// Copyright (C) 2020 Stefan C. Ionescu <rainbreak@riseup.net>
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

contract SpotLike {
    function par() external view returns (uint256);
    function file(bytes32,uint256) external;
}
contract VatLike {
    function suck(address,address,int256) external;
    function debt() external view returns (uint);
}

contract Pot is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) external note auth { wards[guy] = 1; }
    function deny(address guy) external note auth { wards[guy] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Pot/not-authorized");
        _;
    }

    VatLike  public vat;  // CDP engine
    SpotLike public spot; // par holder
    address  public vow;  // debt engine
    uint256  public rho;  // time of last drip
    uint256  public way;  // the Mai Savings Rate

    uint256  public live;  // Access Flag

    // --- Init ---
    constructor(address vat_, address spot_) public {
        wards[msg.sender] = 1;
        vat  = VatLike(vat_);
        spot = SpotLike(spot_);
        way  = RAY;
        rho  = now;
        live = 1;
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;
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

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, y) / RAY;
    }

    function diff(uint x, uint y) internal pure returns (int z) {
        z = int(x) - int(y);
        require(int(x) >= 0 && int(y) >= 0);
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external note auth {
        require(live == 1, "Pot/not-live");
        require(now == rho, "Pot/rho-not-updated");
        if (what == "way") way = data;
        else revert("Pot/file-unrecognized-param");
    }

    function file(bytes32 what, address addr) external note auth {
        if (what == "vow") vow = addr;
        else if (what == "spot") spot = SpotLike(addr);
        else revert("Pot/file-unrecognized-param");
    }

    function cage() external note auth {
        live = 0;
        way = RAY;
    }

    // --- Savings Rate Accumulation ---
    function drip() public note returns (uint tmp) {
        require(now >= rho, "Pot/invalid-now");
        uint par = spot.par();
        tmp = rmul(rpow(way, now - rho, RAY), par);
        spot.file("par", tmp);
        rho = now;
    }
}
