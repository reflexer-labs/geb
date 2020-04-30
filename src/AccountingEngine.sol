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
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) external emitLog isAuthorized {
        require(contractEnabled == 1, "AccountingEngine/contract-not-enabled");
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
        require(authorizedAccounts[msg.sender] == 1, "AccountingEngine/account-not-authorized");
        _;
    }

    // --- Data ---
    // CDP database
    CDPEngineLike           public cdpEngine;
    // Contract that handles auctions for surplus stability fees (sell coins for protocol tokens that are then burned)
    SurplusAuctionHouseLike public surplusAuctionHouse;
    /**
      Contract that handles auctions for debt that couldn't be covered by collateral
      auctions (it prints protocol tokens in exchange for coins that will settle the debt)
    **/
    DebtAuctionHouseLike    public debtAuctionHouse;

    /**
      Debt blocks that need to be covered by auctions. There is a delay to pop debt from
      this queue and either settle it with surplus that came from collateral auctions or with debt auctions
      that print protocol tokens
    **/
    mapping (uint256 => uint256) public debtQueue;
    // Total debt in the queue (that the system tries to cover with collateral auctions)
    uint256 public totalQueuedDebt;      // [rad]
    // Total debt being auctioned in DebtAuctionHouse (printing protocol tokens for coins that will settle the debt)
    uint256 public totalOnAuctionDebt;   // [rad]

    // When the last surplus auction was triggered; enforces a delay in case we use DEX surplus auctions
    uint256 public lastSurplusAuctionTime;
    // Delay between surplus auctions
    uint256 public surplusAuctionDelay;
    // Delay after which debt can be popped from debtQueue
    uint256 public popDebtDelay;
    // Amount of debt that will be sold in one debt auction
    uint256 public initialDebtAuctionAmount;  // [wad]
    // Initial bid (coins/protocol token) that needs to be submitted in order to participate in debt auctions
    uint256 public debtAuctionBidSize;        // [rad]

    // Amount of surplus stability fees sold in one surplus auction
    uint256 public surplusAuctionAmountSold;  // [rad]
    // Amount of stability fees that need to accrue in this contract before any surplus auction can start
    uint256 public surplusBuffer;             // [rad]

    // Whether this contract is enabled or not
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
    /**
     * @notice Modify general uint params for auctions
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
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
    /**
     * @notice Modify addresses of collateral auction houses
     * @param parameter The name of the auction type we want to change the address for
     * @param data New address for the auction
     */
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
    /**
     * @notice Push debt (that the system tries to cover with collateral auctions) to a queue
     * @dev Debt is locked in a queue to give the system enough time to auction collateral
     *      and gather surplus
     * @param debtBlock Amount of debt to push
     */
    function pushDebtToQueue(uint debtBlock) external emitLog isAuthorized {
        debtQueue[now] = add(debtQueue[now], debtBlock);
        totalQueuedDebt = add(totalQueuedDebt, debtBlock);
    }
    /**
     * @notice A block of debt can be popped from the queue after popDebtDelay seconds passed since it was
     *         added there
     * @param debtBlockTimestamp Timestamp of the block of debt that should be popped out
     */
    function popDebtFromQueue(uint debtBlockTimestamp) external emitLog {
        require(add(debtBlockTimestamp, popDebtDelay) <= now, "AccountingEngine/pop-debt-delay-not-passed");
        totalQueuedDebt = sub(totalQueuedDebt, debtQueue[debtBlockTimestamp]);
        debtQueue[debtBlockTimestamp] = 0;
    }

    // Debt settlement
    /**
     * @notice Destroy an equal amount of coins and debt
     * @dev We can only destroy debt that is not locked in the queue and also not in a debt auction
     * @param rad Amount of coins/debt to destroy (number with 45 decimals)
    **/
    function settleDebt(uint rad) external emitLog {
        require(rad <= cdpEngine.coinBalance(address(this)), "AccountingEngine/insufficient-surplus");
        require(rad <= sub(sub(cdpEngine.debtBalance(address(this)), totalQueuedDebt), totalOnAuctionDebt), "AccountingEngine/insufficient-debt");
        cdpEngine.settleDebt(rad);
    }
    /**
     * @notice Use surplus coins to destroy debt that is/was in a debt auction
     * @param rad Amount of coins/debt to destroy (number with 45 decimals)
    **/
    function cancelAuctionedDebtWithSurplus(uint rad) external emitLog {
        require(rad <= totalOnAuctionDebt, "AccountingEngine/not-enough-debt-being-auctioned");
        require(rad <= cdpEngine.coinBalance(address(this)), "AccountingEngine/insufficient-surplus");
        totalOnAuctionDebt = sub(totalOnAuctionDebt, rad);
        cdpEngine.settleDebt(rad);
    }

    // Debt auction
    /**
     * @notice Start a debt auction (print protocol tokens in exchange for coins so that the
     *         system can accumulate surplus)
     * @dev We can only auction debt that is not already being auctioned and is not locked in the debt queue
    **/
    function auctionDebt() external emitLog returns (uint id) {
        require(debtAuctionBidSize <= sub(sub(cdpEngine.debtBalance(address(this)), totalQueuedDebt), totalOnAuctionDebt), "AccountingEngine/insufficient-debt");
        require(cdpEngine.coinBalance(address(this)) == 0, "AccountingEngine/surplus-not-zero");
        totalOnAuctionDebt = add(totalOnAuctionDebt, debtAuctionBidSize);
        id = debtAuctionHouse.startAuction(address(this), initialDebtAuctionAmount, debtAuctionBidSize);
    }
    // Surplus auction
    /**
     * @notice Start a surplus auction
     * @dev We can only auction surplus if we wait at least 'surplusAuctionDelay' seconds since the last
     *      auction trigger, if we keep enough surplus in the buffer and if there is no bad debt to settle
    **/
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

    /**
     * @notice Disable this contract (normally called by Global Settlement)
     * @dev When we disable, the contract tries to settle as much debt as possible (if there's any) with
            any surplus that's left in the system
    **/
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
