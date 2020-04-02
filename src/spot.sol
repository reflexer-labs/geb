/// spot.sol -- Spotter

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
    function file(bytes32, bytes32, uint) external;
}

contract PipLike {
    function peek() external returns (bytes32, bool);
}

contract Spotter is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) external note auth { wards[guy] = 1;  }
    function deny(address guy) external note auth { wards[guy] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Spotter/not-authorized");
        _;
    }

    // --- Data ---
    struct Ilk {
        PipLike pip;
        uint256 mat;
        uint256 tam;
    }

    mapping (bytes32 => Ilk) public ilks;

    VatLike public vat;
    uint256 public way;  // rate of change for par
    uint256 public rho;  // last update time of par
    uint256 public live;

    uint256 private _par;

    // --- Events ---
    event Poke(
      bytes32 ilk,
      bytes32 val,
      uint256 spot,
      uint256 risk
    );

    // --- Init ---
    constructor(address vat_) public {
        wards[msg.sender] = 1;
        vat  = VatLike(vat_);
        _par = RAY;
        way  = RAY;
        rho  = now;
        live = 1;
    }

    // --- Math ---
    uint constant RAY = 10 ** 27;

    function sub(uint x, uint y) internal pure returns (uint z) {
        z = x - y;
        require(z <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        // alsites rounds down
        z = mul(x, y) / RAY;
    }
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, RAY) / y;
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

    // --- Administration ---
    function file(bytes32 ilk, bytes32 what, address pip_) external note auth {
        require(live == 1, "Spotter/not-live");
        if (what == "pip") ilks[ilk].pip = PipLike(pip_);
        else revert("Spotter/file-unrecognized-param");
    }
    function file(bytes32 what, uint data) external note auth {
        require(live == 1, "Spotter/not-live");
        require(data > 0, "Spotter/null-data");
        if (what == "par") _par = data;
        else if (what == "way") way = data;
        else revert("Spotter/file-unrecognized-param");
    }
    function file(bytes32 ilk, bytes32 what, uint data) external note auth {
        require(live == 1, "Spotter/not-live");
        if (what == "mat") {
          require(data <= ilks[ilk].tam, "Spotter/mat-lower-than-tam");
          ilks[ilk].mat = data;
        }
        else if (what == "tam") {
          require(data >= ilks[ilk].mat, "Spotter/tam-bigger-than-mat");
          ilks[ilk].tam = data;
        }
        else revert("Spotter/file-unrecognized-param");
    }

    // --- Rate Update ---
    function drip() public note returns (uint) {
        // Update target price
        _par = rmul(rpow(way, sub(now, rho), RAY), _par);
        rho = now;
        // Return updated par
        return _par;
    }
    function par() public returns (uint) {
        if (now > rho) return drip();
        return _par;
    }

    // --- Update value ---
    function poke(bytes32 ilk) external {
        (bytes32 val, bool has) = ilks[ilk].pip.peek();
        uint256 spot = has ? rdiv(rdiv(mul(uint(val), 10 ** 9), par()), ilks[ilk].mat) : 0;
        uint256 risk = (has && ilks[ilk].tam > 0) ? rdiv(rdiv(mul(uint(val), 10 ** 9), par()), ilks[ilk].tam) : 0;
        vat.file(ilk, "spot", spot);
        vat.file(ilk, "risk", risk);
        emit Poke(ilk, val, spot, risk);
    }

    function cage() external note auth {
        live = 0;
    }

    function mat(bytes32 ilk) public view returns (uint256) {
        return ilks[ilk].mat;
    }

    function tam(bytes32 ilk) public view returns (uint256) {
        return ilks[ilk].tam;
    }

    function pip(bytes32 ilk) public view returns (address) {
        return address(ilks[ilk].pip);
    }
}
