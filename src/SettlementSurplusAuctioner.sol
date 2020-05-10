/// SettlementSurplusAuctioner.sol

// Copyright (C) 2020 Stefan C. Ionescu <stefanionescu@protonmail.com>

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

import "./Logging.sol";

contract AccountingEngineLike {
    function surplusAuctionDelay() external view returns (uint);
    function surplusAuctionAmountToSell() external view returns (uint);
    function surplusAuctionHouse() external view returns (address);
    function cdpEngine() external view returns (address);
    function contractEnabled() external view returns (uint);
}
contract CDPEngineLike {
    function coinBalance(address) external view returns (uint);
    function approveCDPModification(address) external;
    function denyCDPModification(address) external;
}
contract SurplusAuctionHouseLike {
    function startAuction(uint, uint) external returns (uint);
}

contract SettlementSurplusAuctioner is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) external emitLog isAuthorized {
        require(contractEnabled == 1, "SettlementSurplusAuctioner/contract-not-enabled");
        authorizedAccounts[account] = 1;
    }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(address account) external emitLog isAuthorized {
        authorizedAccounts[account] = 0;
    }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "SettlementSurplusAuctioner/account-not-authorized");
        _;
    }

    AccountingEngineLike    public accountingEngine;
    SurplusAuctionHouseLike public surplusAuctionHouse;
    CDPEngineLike           public cdpEngine;

    uint256 public contractEnabled;
    uint256 public lastSurplusAuctionTime;

    constructor(address accountingEngine_) public {
        authorizedAccounts[msg.sender] = 1;
        accountingEngine = AccountingEngineLike(accountingEngine_);
        surplusAuctionHouse = SurplusAuctionHouseLike(address(accountingEngine.surplusAuctionHouse()));
        cdpEngine = CDPEngineLike(address(accountingEngine.cdpEngine()));
        cdpEngine.approveCDPModification(address(surplusAuctionHouse));
        contractEnabled = 1;
    }

    // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, address data) external emitLog isAuthorized {
        require(contractEnabled == 1, "SettlementSurplusAuctioner/contract-not-enabled");
        if (parameter == "accountingEngine") {
          cdpEngine.denyCDPModification(address(surplusAuctionHouse));
          accountingEngine = AccountingEngineLike(data);
          surplusAuctionHouse = SurplusAuctionHouseLike(address(accountingEngine.surplusAuctionHouse()));
          cdpEngine.approveCDPModification(address(surplusAuctionHouse));
        }
        else revert("SettlementSurplusAuctioner/modify-unrecognized-param");
    }
    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
    }

    // --- Core Logic ---
    function auctionSurplus() external emitLog returns (uint id) {
        require(accountingEngine.contractEnabled() == 0, "SettlementSurplusAuctioner/accounting-engine-still-enabled");
        require(
          now >= add(lastSurplusAuctionTime, accountingEngine.surplusAuctionDelay()),
          "AccountingEngine/surplus-auction-delay-not-passed"
        );
        lastSurplusAuctionTime = now;
        uint defaultAmountToSell = accountingEngine.surplusAuctionAmountToSell();
        uint finalAmountToSell =
          (cdpEngine.coinBalance(address(this)) < defaultAmountToSell) ?
          cdpEngine.coinBalance(address(this)) : defaultAmountToSell;
        if (finalAmountToSell > 0) {
            id = surplusAuctionHouse.startAuction(finalAmountToSell, 0);
        }
    }
}
