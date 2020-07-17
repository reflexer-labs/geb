/// SettlementSurplusAuctioneer.sol

// Copyright (C) 2020 Reflexer Labs, INC

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

pragma solidity ^0.6.7;

import "./Logging.sol";

abstract contract AccountingEngineLike {
    function surplusAuctionDelay() virtual public view returns (uint);
    function surplusAuctionAmountToSell() virtual public view returns (uint);
    function surplusAuctionHouse() virtual public view returns (address);
    function cdpEngine() virtual public view returns (address);
    function contractEnabled() virtual public view returns (uint);
}
abstract contract CDPEngineLike {
    function coinBalance(address) virtual public view returns (uint);
    function approveCDPModification(address) virtual external;
    function denyCDPModification(address) virtual external;
}
abstract contract SurplusAuctionHouseLike {
    function startAuction(uint, uint) virtual public returns (uint);
}

contract SettlementSurplusAuctioneer is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) external emitLog isAuthorized {
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
        require(authorizedAccounts[msg.sender] == 1, "SettlementSurplusAuctioneer/account-not-authorized");
        _;
    }

    AccountingEngineLike    public accountingEngine;
    SurplusAuctionHouseLike public surplusAuctionHouse;
    CDPEngineLike           public cdpEngine;

    uint256 public lastSurplusAuctionTime;

    constructor(address accountingEngine_, address surplusAuctionHouse_) public {
        authorizedAccounts[msg.sender] = 1;
        accountingEngine = AccountingEngineLike(accountingEngine_);
        surplusAuctionHouse = SurplusAuctionHouseLike(surplusAuctionHouse_);
        cdpEngine = CDPEngineLike(address(accountingEngine.cdpEngine()));
        cdpEngine.approveCDPModification(address(surplusAuctionHouse));
    }

    // --- Math ---
    function addition(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }

    // --- Administration ---
    /**
     * @notice Modify contract addresses
     * @param parameter The name of the contract whose address will be changed
     * @param addr New address for the contract
     */
    function modifyParameters(bytes32 parameter, address addr) external emitLog isAuthorized {
        if (parameter == "accountingEngine") {
          cdpEngine.denyCDPModification(address(surplusAuctionHouse));
          accountingEngine = AccountingEngineLike(addr);
          cdpEngine.approveCDPModification(address(surplusAuctionHouse));
        } else if (parameter == "surplusAuctionHouse") {
          surplusAuctionHouse = SurplusAuctionHouseLike(addr);
        }
        else revert("SettlementSurplusAuctioneer/modify-unrecognized-param");
    }

    // --- Core Logic ---
    /**
     * @notice Auction stability fees. The process is very similar to how the AccountingEngine would do it.
               The contract even reads surplus auction parameters from the AccountingEngine and uses them to
               start a new auction.
     */
    function auctionSurplus() external emitLog returns (uint id) {
        require(accountingEngine.contractEnabled() == 0, "SettlementSurplusAuctioneer/accounting-engine-still-enabled");
        require(
          now >= addition(lastSurplusAuctionTime, accountingEngine.surplusAuctionDelay()),
          "SettlementSurplusAuctioneer/surplus-auction-delay-not-passed"
        );
        lastSurplusAuctionTime = now;
        uint amountToSell = (cdpEngine.coinBalance(address(this)) < accountingEngine.surplusAuctionAmountToSell()) ?
          cdpEngine.coinBalance(address(this)) : accountingEngine.surplusAuctionAmountToSell();
        if (amountToSell > 0) {
          id = surplusAuctionHouse.startAuction(amountToSell, 0);
        }
    }
}
