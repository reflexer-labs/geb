// Copyright (C) 2017, 2018, 2019 dbrock, rain, mrchico, lucasvo, livnev
// Copyright (C) 2020             Stefan C. Ionescu <stefanionescu@protonmail.com>

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
}

contract Mai is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) external note auth { wards[guy] = 1; }
    function deny(address guy) external note auth { wards[guy] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Mai/not-authorized");
        _;
    }

    // --- ERC20 Data ---
    string  public constant name     = "Mai Reflex Bond";
    string  public constant symbol   = "MAI";
    string  public constant version  = "1";
    uint8   public constant decimals = 18;
    uint256 public totalSupply;

    VatLike  public vat;  // cdp engine
    SpotLike public spot; // stores the target rate
    address  public vow;  // debt engine
    uint256  public rho;  // time of last drip
    uint256  public msr;  // mai savings rate

    uint256 public live;  // access flag

    mapping (address => uint)                      public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
    mapping (address => uint)                      public nonces;

    event Approval(address indexed src, address indexed guy, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad);

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
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        // always rounds down
        z = mul(x, y) / RAY;
    }
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        // always rounds down
        z = mul(x, RAY) / y;
    }
    function rdivup(uint x, uint y) internal pure returns (uint z) {
        // always rounds up
        z = add(mul(x, RAY), sub(y, 1)) / y;
    }

    // --- EIP712 niceties ---
    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)"));
    bytes32 public constant PERMIT_TYPEHASH  = 0xea2aa0a1be11a07ed86d755c93467f4f82362b452371d1ba94d1715123511acb;

    constructor(
      uint chainId_,
      address vat_
    ) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        msr = RAY;
        rho = now;
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifmaigContract)"),
            keccak256(bytes(name)),
            keccak256(bytes(version)),
            chainId_,
            address(this)
        ));
        live = 1;
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external note auth {
        require(live == 1, "Mai/not-live");
        require(now == rho, "Mai/rho-not-updated");
        if (what == "msr") msr = data;
        else revert("Mai/file-unrecognized-param");
    }
    function file(bytes32 what, address addr) external note auth {
        if (what == "vow") vow = addr;
        else if (what == "spot") spot = SpotLike(addr);
        else revert("Mai/file-unrecognized-param");
    }
    function cage() external note auth {
        live = 0;
    }

    // --- Savings Rate Accumulation ---
    function drip() public note returns (uint tmp) {
        require(now >= rho, "Mai/invalid-now");
        uint par = spot.par();
        tmp = rmul(rpow(msr, now - rho, RAY), par);
        spot.file("par", tmp);
        rho = now;
        uint par_ = (msr <= RAY) ? sub(par, tmp) : sub(tmp, par);
        int vol = (msr <= RAY) ? -int(mul(totalSupply, par_)) : int(mul(totalSupply, par_));
        vat.suck(address(vow), address(this), vol);
    }

    // --- Token ---
    function transfer(address dst, uint wad) external returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }
    function transferFrom(address src, address dst, uint wad)
        public returns (bool)
    {
        require(balanceOf[src] >= wad, "Mai/insufficient-balance");
        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= wad, "Mai/insufficient-allowance");
            allowance[src][msg.sender] = sub(allowance[src][msg.sender], wad);
        }
        balanceOf[src] = sub(balanceOf[src], wad);
        balanceOf[dst] = add(balanceOf[dst], wad);
        emit Transfer(src, dst, wad);
        return true;
    }
    function approve(address usr, uint wad) external returns (bool) {
        allowance[msg.sender][usr] = wad;
        emit Approval(msg.sender, usr, wad);
        return true;
    }

    // --- Alias ---
    function push(address usr, uint wad) external returns (bool) {
        return transferFrom(msg.sender, usr, wad);
    }
    function pull(address usr, uint wad) external returns (bool) {
        return transferFrom(usr, msg.sender, wad);
    }
    function move(address src, address dst, uint wad) external returns (bool) {
        return transferFrom(src, dst, wad);
    }

    // --- Approve by signature ---
    function permit(address holder, address spender, uint256 nonce, uint256 expiry, bool allowed, uint8 v, bytes32 r, bytes32 s) external
    {
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(PERMIT_TYPEHASH,
                                 holder,
                                 spender,
                                 nonce,
                                 expiry,
                                 allowed))));
        require(holder != address(0), "Mai/invalid holder");
        require(holder == ecrecover(digest, v, r, s), "Mai/invalid-permit");
        require(expiry == 0 || now <= expiry, "Mai/permit-expired");
        require(nonce == nonces[holder]++, "Mai/invalid-nonce");

        uint can = allowed ? uint(-1) : 0;
        allowance[holder][spender] = can;
        emit Approval(holder, spender, can);
    }

    // --- Enter and Exit ---
    function mint(address usr, uint wad) external auth {
        balanceOf[usr] = add(balanceOf[usr], wad);
        totalSupply    = add(totalSupply, wad);
        emit Transfer(address(0), usr, wad);
    }
    function burn(address usr, uint wad) external {
        require(balanceOf[usr] >= wad, "Mai/insufficient-balance");
        if (usr != msg.sender && allowance[usr][msg.sender] != uint(-1)) {
            require(allowance[usr][msg.sender] >= wad, "Mai/insufficient-allowance");
            allowance[usr][msg.sender] = sub(allowance[usr][msg.sender], wad);
        }
        balanceOf[usr] = sub(balanceOf[usr], wad);
        totalSupply    = sub(totalSupply, wad);
        emit Transfer(usr, address(0), wad);
    }
}
