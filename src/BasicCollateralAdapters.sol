/// BasicCollateralAdapters.sol

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
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

import "./Logging.sol";

contract CollateralLike {
    function decimals() public view returns (uint);
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
}

contract DSTokenLike {
    function mint(address,uint) external;
    function burn(address,uint) external;
}

contract CDPEngineLike {
    function modifyCollateralBalance(bytes32,address,int) external;
    function transferInternalCoins(address,address,uint) external;
}

/*
    Here we provide *adapters* to connect the CDPEngine to arbitrary external
    token implementations, creating a bounded context for the CDPEngine. The
    adapters here are provided as working examples:
      - `CollateralJoin`: For well behaved ERC20 tokens, with simple transfer semantics.
      - `ETHJoin`: For native Ether.
      - `CoinJoin`: For connecting internal coin balances to an external
                   `DSToken` implementation.
    In practice, adapter implementations will be varied and specific to
    individual collateral types, accounting for different transfer
    semantics and token standards.
    Adapters need to implement two basic methods:
      - `join`: enter collateral into the system
      - `exit`: remove collateral from the system
*/

contract CollateralJoin is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "CollateralJoin/account-not-authorized");
        _;
    }

    CDPEngineLike  public cdpEngine;
    bytes32        public collateralType;
    CollateralLike public collateral;
    uint           public decimals;
    uint           public contractEnabled;

    constructor(address cdpEngine_, bytes32 collateralType_, address collateral_) public {
        authorizedAccounts[msg.sender] = 1;
        contractEnabled = 1;
        cdpEngine       = CDPEngineLike(cdpEngine_);
        collateralType  = collateralType_;
        collateral      = CollateralLike(collateral_);
        decimals        = collateral.decimals();
    }
    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
    }
    function join(address account, uint wad) external emitLog {
        require(contractEnabled == 1, "CollateralJoin/contract-not-enabled");
        require(int(wad) >= 0, "CollateralJoin/overflow");
        cdpEngine.modifyCollateralBalance(collateralType, account, int(wad));
        require(collateral.transferFrom(msg.sender, address(this), wad), "CollateralJoin/failed-transfer");
    }
    function exit(address account, uint wad) external emitLog {
        require(wad <= 2 ** 255, "CollateralJoin/overflow");
        cdpEngine.modifyCollateralBalance(collateralType, msg.sender, -int(wad));
        require(collateral.transfer(account, wad), "CollateralJoin/failed-transfer");
    }
}

contract ETHJoin is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "ETHJoin/account-not-authorized");
        _;
    }

    CDPEngineLike public cdpEngine;
    bytes32       public collateralType;
    uint          public contractEnabled;

    constructor(address cdpEngine_, bytes32 collateralType_) public {
        authorizedAccounts[msg.sender] = 1;
        contractEnabled                = 1;
        cdpEngine                      = CDPEngineLike(cdpEngine_);
        collateralType                 = collateralType_;
    }
    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
    }
    function join(address account) external payable emitLog {
        require(contractEnabled == 1, "ETHJoin/contract-not-enabled");
        require(int(msg.value) >= 0, "ETHJoin/overflow");
        cdpEngine.modifyCollateralBalance(collateralType, account, int(msg.value));
    }
    function exit(address payable account, uint wad) external emitLog {
        require(int(wad) >= 0, "ETHJoin/overflow");
        cdpEngine.modifyCollateralBalance(collateralType, msg.sender, -int(wad));
        account.transfer(wad);
    }
}

contract CoinJoin is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "CoinJoin/account-not-authorized");
        _;
    }

    CDPEngineLike public cdpEngine;
    DSTokenLike   public systemCoin;
    uint          public contractEnabled;

    constructor(address cdpEngine_, address systemCoin_) public {
        authorizedAccounts[msg.sender] = 1;
        contractEnabled                = 1;
        cdpEngine                      = CDPEngineLike(cdpEngine_);
        systemCoin                     = DSTokenLike(systemCoin_);
    }
    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
    }
    uint constant RAY = 10 ** 27;
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function join(address account, uint wad) external emitLog {
        cdpEngine.transferInternalCoins(address(this), account, mul(RAY, wad));
        systemCoin.burn(msg.sender, wad);
    }
    function exit(address account, uint wad) external emitLog {
        require(contractEnabled == 1, "CoinJoin/contract-not-enabled");
        cdpEngine.transferInternalCoins(msg.sender, address(this), mul(RAY, wad));
        systemCoin.mint(account, wad);
    }
}
