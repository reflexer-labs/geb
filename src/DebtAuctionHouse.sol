/// DebtAuctionHouse.sol

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

contract CDPEngineLike {
    function transferInternalCoins(address,address,uint) external;
    function createUnbackedDebt(address,address,uint) external;
}
contract TokenLike {
    function mint(address,uint) external;
}
contract AccountingEngineLike {
    function settleDebtAuction(uint id) external;
    function totalOnAuctionDebt() public returns (uint);
    function cancelAuctionedDebtWithSurplus(uint) external;
}

/*
   This thing creates protocol tokens on demand in return for system coins
*/

contract DebtAuctionHouse is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 1;
    }
    function removeAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 0;
    }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "DebtAuctionHouse/account-not-authorized");
        _;
    }

    // --- Data ---
    struct Bid {
        uint256 bidAmount;
        uint256 amountToSell;
        address highBidder;
        uint48  bidExpiry;
        uint48  auctionDeadline;
    }

    mapping (uint => Bid) public bids;

    CDPEngineLike public cdpEngine;
    TokenLike public protocolToken;
    AccountingEngineLike public accountingEngine;

    uint256  constant ONE = 1.00E18;
    uint256  public   bidDecrease = 1.05E18;
    uint256  public   amountSoldIncrease = 1.50E18;
    uint48   public   bidDuration = 3 hours;
    uint48   public   totalAuctionLength = 2 days;
    uint256  public   auctionsStarted = 0;
    uint256  public   contractEnabled;

    // --- Events ---
    event StartAuction(
      uint256 id,
      uint256 amountToSell,
      uint256 initialBid,
      address indexed incomeReceiver
    );

    // --- Init ---
    constructor(address cdpEngine_, address protocolToken_) public {
        authorizedAccounts[msg.sender] = 1;
        cdpEngine = CDPEngineLike(cdpEngine_);
        protocolToken = TokenLike(protocolToken_);
        contractEnabled = 1;
    }

    // --- Math ---
    function add(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function min(uint x, uint y) internal pure returns (uint z) {
        if (x > y) { z = y; } else { z = x; }
    }

    // --- Admin ---
    function modifyParameters(bytes32 parameter, uint data) external emitLog isAuthorized {
        if (parameter == "bidDecrease") bidDecrease = data;
        else if (parameter == "amountSoldIncrease") amountSoldIncrease = data;
        else if (parameter == "bidDuration") bidDuration = uint48(data);
        else if (parameter == "totalAuctionLength") totalAuctionLength = uint48(data);
        else revert("DebtAuctionHouse/modify-unrecognized-param");
    }
    function modifyParameters(bytes32 parameter, address addr) external emitLog isAuthorized {
        require(contractEnabled == 1, "DebtAuctionHouse/contract-not-enabled");
        if (parameter == "protocolToken") protocolToken = TokenLike(addr);
        else if (parameter == "accountingEngine") accountingEngine = AccountingEngineLike(addr);
        else revert("DebtAuctionHouse/modify-unrecognized-param");
    }

    // --- Auction ---
    function startAuction(
        address incomeReceiver,
        uint amountToSell,
        uint initialBid
    ) external isAuthorized returns (uint id) {
        require(contractEnabled == 1, "DebtAuctionHouse/contract-not-enabled");
        require(auctionsStarted < uint(-1), "DebtAuctionHouse/overflow");
        id = ++auctionsStarted;

        bids[id].bidAmount = initialBid;
        bids[id].amountToSell = amountToSell;
        bids[id].highBidder = incomeReceiver;
        bids[id].auctionDeadline = add(uint48(now), totalAuctionLength);

        emit StartAuction(id, amountToSell, initialBid, incomeReceiver);
    }
    function restartAuction(uint id) external emitLog {
        require(bids[id].auctionDeadline < now, "DebtAuctionHouse/not-finished");
        require(bids[id].bidExpiry == 0, "DebtAuctionHouse/bid-already-placed");
        bids[id].amountToSell = mul(amountSoldIncrease, bids[id].amountToSell) / ONE;
        bids[id].auctionDeadline = add(uint48(now), totalAuctionLength);
    }
    function decreaseSoldAmount(uint id, uint amountToBuy, uint bid) external emitLog {
        require(contractEnabled == 1, "DebtAuctionHouse/contract-not-enabled");
        require(bids[id].highBidder != address(0), "DebtAuctionHouse/high-bidder-not-set");
        require(bids[id].bidExpiry > now || bids[id].bidExpiry == 0, "DebtAuctionHouse/bid-already-expired");
        require(bids[id].auctionDeadline > now, "DebtAuctionHouse/auction-already-expired");

        require(bid == bids[id].bidAmount, "DebtAuctionHouse/not-matching-bid");
        require(amountToBuy <  bids[id].amountToSell, "DebtAuctionHouse/amount-bought-not-lower");
        require(mul(bidDecrease, amountToBuy) <= mul(bids[id].amountToSell, ONE), "DebtAuctionHouse/insufficient-decrease");

        cdpEngine.transferInternalCoins(msg.sender, bids[id].highBidder, bid);

        // on first bid submitted, clear as much totalOnAuctionDebt as possible
        if (bids[id].bidExpiry == 0) {
            uint totalOnAuctionDebt = AccountingEngineLike(bids[id].highBidder).totalOnAuctionDebt();
            AccountingEngineLike(bids[id].highBidder).cancelAuctionedDebtWithSurplus(min(bid, totalOnAuctionDebt));
        }

        bids[id].highBidder = msg.sender;
        bids[id].amountToSell = amountToBuy;
        bids[id].bidExpiry = add(uint48(now), bidDuration);
    }
    function settleAuction(uint id) external emitLog {
        require(contractEnabled == 1, "DebtAuctionHouse/not-live");
        require(bids[id].bidExpiry != 0 && (bids[id].bidExpiry < now || bids[id].auctionDeadline < now), "DebtAuctionHouse/not-finished");
        protocolToken.mint(bids[id].highBidder, bids[id].amountToSell);
        accountingEngine.settleDebtAuction(id);
        delete bids[id];
    }

    // --- Shutdown ---
    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
        // Removed line where we set the accounting engine
    }
    function terminateAuctionPrematurely(uint id) external emitLog {
        require(contractEnabled == 0, "DebtAuctionHouse/contract-still-enabled");
        require(bids[id].highBidder != address(0), "DebtAuctionHouse/high-bidder-not-set");
        cdpEngine.createUnbackedDebt(address(accountingEngine), bids[id].highBidder, bids[id].bidAmount);
        accountingEngine.settleDebtAuction(id);
        delete bids[id];
    }
}
