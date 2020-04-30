/// AccountingEngine.sol

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

contract DebtAuctionHouseLike {
    function startAuction(address incomeReceiver, uint amountToSell, uint initialBid) external returns (uint);
    function disableContract() external;
    function contractEnabled() external returns (uint);
}

contract SurplusAuctionHouseLike {
    function startAuction(uint, uint) external returns (uint);
    function disableContract() external;
    function contractEnabled() external returns (uint);
}

contract CDPEngineLike {
    function coinBalance(address) external view returns (uint);
    function debtBalance(address) external view returns (uint);
    function settleDebt(uint256) external;
    function approveCDPModification(address) external;
    function denyCDPModification(address) external;
}

contract AccountingEngine is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized {
        require(contractEnabled == 1, "AccountingEngine/contract-not-enabled");
        authorizedAccounts[account] = 1;
    }
    function removeAuthorization(address account) external emitLog isAuthorized {
        authorizedAccounts[account] = 0;
    }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "AccountingEngine/account-not-authorized");
        _;
    }

    // --- Data ---
    CDPEngineLike           public cdpEngine;
    SurplusAuctionHouseLike public surplusAuctionHouse;
    DebtAuctionHouseLike    public debtAuctionHouse;

    mapping (uint256 => uint256) public debtQueue;
    uint256 public totalQueuedDebt;      // [rad]
    uint256 public totalOnAuctionDebt;   // [rad]

    uint256 public lastSurplusAuctionTime;
    uint256 public surplusAuctionDelay;
    uint256 public popDebtDelay;
    uint256 public initialDebtAuctionAmount;  // [wad]
    uint256 public debtAuctionBidSize;        // [rad]

    uint256 public surplusAuctionAmountSold;  // [rad]
    uint256 public surplusBuffer;             // [rad]

    uint256 public contractEnabled;

    // --- Init ---
    constructor(address cdpEngine_, address surplusAuctionHouse_, address debtAuctionHouse_) public {
        authorizedAccounts[msg.sender] = 1;
        cdpEngine = CDPEngineLike(cdpEngine_);
        surplusAuctionHouse = SurplusAuctionHouseLike(surplusAuctionHouse_);
        debtAuctionHouse = DebtAuctionHouseLike(debtAuctionHouse_);
        cdpEngine.approveCDPModification(surplusAuctionHouse_);
        lastSurplusAuctionTime = now;
        contractEnabled = 1;
    }

    // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function min(uint x, uint y) internal pure returns (uint z) {
        return x <= y ? x : y;
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, uint data) external emitLog isAuthorized {
        if (parameter == "surplusAuctionDelay") surplusAuctionDelay = data;
        else if (parameter == "popDebtDelay") popDebtDelay = data;
        else if (parameter == "surplusAuctionDelay") surplusAuctionDelay = data;
        else if (parameter == "surplusAuctionAmountSold") surplusAuctionAmountSold = data;
        else if (parameter == "debtAuctionBidSize") debtAuctionBidSize = data;
        else if (parameter == "initialDebtAuctionAmount") initialDebtAuctionAmount = data;
        else if (parameter == "surplusBuffer") surplusBuffer = data;
        else revert("AccountingEngine/modify-unrecognized-param");
    }

    function modifyParameters(bytes32 parameter, address data) external emitLog isAuthorized {
        if (parameter == "surplusAuctionHouse") {
            cdpEngine.denyCDPModification(address(surplusAuctionHouse));
            surplusAuctionHouse = SurplusAuctionHouseLike(data);
            cdpEngine.approveCDPModification(data);
        }
        else if (parameter == "debtAuctionHouse") debtAuctionHouse = DebtAuctionHouseLike(data);
        else revert("AccountingEngine/modify-unrecognized-param");
    }

    // --- Debt Queueing ---
    function pushDebtToQueue(uint debtBlock) external emitLog isAuthorized {
        debtQueue[now] = add(debtQueue[now], debtBlock);
        totalQueuedDebt = add(totalQueuedDebt, debtBlock);
    }
    function popDebtFromQueue(uint era) external emitLog {
        require(add(era, popDebtDelay) <= now, "AccountingEngine/pop-debt-delay-not-passed");
        totalQueuedDebt = sub(totalQueuedDebt, debtQueue[era]);
        debtQueue[era] = 0;
    }

    // Debt settlement
    function settleDebt(uint rad) external emitLog {
        require(rad <= cdpEngine.coinBalance(address(this)), "AccountingEngine/insufficient-surplus");
        require(rad <= sub(sub(cdpEngine.debtBalance(address(this)), totalQueuedDebt), totalOnAuctionDebt), "AccountingEngine/insufficient-debt");
        cdpEngine.settleDebt(rad);
    }
    function cancelAuctionedDebtWithSurplus(uint rad) external emitLog {
        require(rad <= totalOnAuctionDebt, "AccountingEngine/not-enough-debt-being-auctioned");
        require(rad <= cdpEngine.coinBalance(address(this)), "AccountingEngine/insufficient-surplus");
        totalOnAuctionDebt = sub(totalOnAuctionDebt, rad);
        cdpEngine.settleDebt(rad);
    }

    // Debt auction
    function auctionDebt() external emitLog returns (uint id) {
        require(debtAuctionBidSize <= sub(sub(cdpEngine.debtBalance(address(this)), totalQueuedDebt), totalOnAuctionDebt), "AccountingEngine/insufficient-debt");
        require(cdpEngine.coinBalance(address(this)) == 0, "AccountingEngine/surplus-not-zero");
        totalOnAuctionDebt = add(totalOnAuctionDebt, debtAuctionBidSize);
        id = debtAuctionHouse.startAuction(address(this), initialDebtAuctionAmount, debtAuctionBidSize);
    }
    // Surplus auction
    function auctionSurplus() external emitLog returns (uint id) {
        require(
          now >= add(lastSurplusAuctionTime, surplusAuctionDelay),
          "AccountingEngine/surplus-auction-delay-not-passed"
        );
        require(
          cdpEngine.coinBalance(address(this)) >=
          add(add(cdpEngine.debtBalance(address(this)), surplusAuctionAmountSold), surplusBuffer),
          "AccountingEngine/insufficient-surplus"
        );
        require(
          sub(sub(cdpEngine.debtBalance(address(this)), totalQueuedDebt), totalOnAuctionDebt) == 0,
          "AccountingEngine/debt-not-zero"
        );
        lastSurplusAuctionTime = now;
        id = surplusAuctionHouse.startAuction(surplusAuctionAmountSold, 0);
    }

    function disableContract() external emitLog isAuthorized {
        require(contractEnabled == 1, "AccountingEngine/contract-not-enabled");
        contractEnabled = 0;
        totalQueuedDebt = 0;
        totalOnAuctionDebt = 0;
        surplusAuctionHouse.disableContract();
        debtAuctionHouse.disableContract();
        cdpEngine.settleDebt(min(cdpEngine.coinBalance(address(this)), cdpEngine.debtBalance(address(this))));
    }
}
