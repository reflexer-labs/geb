pragma solidity ^0.5.15;

import "./lib.sol";

contract VatLike {
    function move(address,address,uint) external;
    function good(address) external view returns (uint);
}

contract Purse is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Purse/not-authorized");
        _;
    }

    mapping(address => uint) public allowance;
    mapping(address => uint) public pace;

    VatLike public vat;

    address public vow;

    uint8   public mutex;

    uint256 public live;

    constructor(address vat_, address vow_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        vow = vow_;
        live = 1;
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;

    function add(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x);
    }
    function add(int x, int y) internal pure returns (int z) {
        z = x + y;
        if (y <= 0) require(z <= x);
        if (y  > 0) require(z > x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function sub(int x, int y) internal pure returns (int z) {
        z = x - y;
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
        require(live == 1, "Purse/not-live");
        require(addr != address(0), "Purse/null-addr");
        if (what == "vow") vow = addr;
        else revert("Purse/file-unrecognized-param");
    }
    function cage() external note auth {
        vat.move(address(this), vow, vat.good(address(this)));
        live = 0;
    }

    // --- Allowance ---
    function allow(address gal, uint val) external note auth {
        require(gal != address(0), "Purse/null-gal");
        allowance[gal] = val;
    }
    function limit(address gal, uint val) external note auth {
        require(gal != address(0), "Purse/null-gal");
        pace[gal] = val;
    }

    // --- Stability Fee Transfer (Governance) ---
    function give(address gal, uint val) external note auth {
        require(gal != address(0), "Purse/null-gal");
        vat.move(address(this), gal, val);
    }
    function take(address gal, uint val) external note auth {
        vat.move(gal, address(this), val);
    }

    // --- Stability Fee Transfer (Approved Gals) ---
    function pull(address gal, uint val) external returns (bool) {
        require(mutex == 0, "Purse/non-null-mutex");
        mutex = 1;
        if (pace[msg.sender] > 0) {
          require(val <= pace[msg.sender], "Purse/exceeds-pace");
        }
        allowance[msg.sender] = sub(allowance[msg.sender], val);
        vat.move(address(this), gal, val);
        mutex = 0;
        return true;
    }
}
