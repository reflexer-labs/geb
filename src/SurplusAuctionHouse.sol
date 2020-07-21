/// SurplusAuctionHouse.sol

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

pragma solidity ^0.6.7;

import "./Logging.sol";

abstract contract CDPEngineLike {
    function transferInternalCoins(address,address,uint) virtual external;
    function coinBalance(address) virtual external view returns (uint);
    function approveCDPModification(address) virtual external;
    function denyCDPModification(address) virtual external;
}
abstract contract TokenLike {
    function approve(address, uint) virtual public returns (bool);
    function balanceOf(address) virtual public view returns (uint);
    function move(address,address,uint) virtual external;
    function burn(address,uint) virtual external;
}

/*
   This thing lets you auction some coins in return for protocol tokens
*/

contract PreSettlementSurplusAuctionHouse is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 1;
    }
    function removeAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 0;
    }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "PreSettlementSurplusAuctionHouse/account-not-authorized");
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

    CDPEngineLike        public cdpEngine;
    TokenLike            public protocolToken;

    uint256  constant ONE = 1.00E18;
    uint256  public   bidIncrease = 1.05E18;
    uint48   public   bidDuration = 3 hours;
    uint48   public   totalAuctionLength = 2 days;
    uint256  public   auctionsStarted = 0;
    uint256  public   contractEnabled;

    bytes32 public constant AUCTION_HOUSE_TYPE = bytes32("SURPLUS");

    // --- Events ---
    event StartAuction(
        uint256 id,
        uint256 amountToSell,
        uint256 initialBid
    );

    // --- Init ---
    constructor(address cdpEngine_, address protocolToken_) public {
        authorizedAccounts[msg.sender] = 1;
        cdpEngine = CDPEngineLike(cdpEngine_);
        protocolToken = TokenLike(protocolToken_);
        contractEnabled = 1;
    }

    // --- Math ---
    function addUint48(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x);
    }
    function multiply(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Admin ---
    function modifyParameters(bytes32 parameter, uint data) external emitLog isAuthorized {
        if (parameter == "bidIncrease") bidIncrease = data;
        else if (parameter == "bidDuration") bidDuration = uint48(data);
        else if (parameter == "totalAuctionLength") totalAuctionLength = uint48(data);
        else revert("PreSettlementSurplusAuctionHouse/modify-unrecognized-param");
    }

    // --- Auction ---
    function startAuction(uint amountToSell, uint initialBid) external isAuthorized returns (uint id) {
        require(contractEnabled == 1, "PreSettlementSurplusAuctionHouse/contract-not-enabled");
        require(auctionsStarted < uint(-1), "PreSettlementSurplusAuctionHouse/overflow");
        id = ++auctionsStarted;

        bids[id].bidAmount = initialBid;
        bids[id].amountToSell = amountToSell;
        bids[id].highBidder = msg.sender;
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);

        cdpEngine.transferInternalCoins(msg.sender, address(this), amountToSell);

        emit StartAuction(id, amountToSell, initialBid);
    }
    function restartAuction(uint id) external emitLog {
        require(bids[id].auctionDeadline < now, "PreSettlementSurplusAuctionHouse/not-finished");
        require(bids[id].bidExpiry == 0, "PreSettlementSurplusAuctionHouse/bid-already-placed");
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);
    }
    function increaseBidSize(uint id, uint amountToBuy, uint bid) external emitLog {
        require(contractEnabled == 1, "PreSettlementSurplusAuctionHouse/contract-not-enabled");
        require(bids[id].highBidder != address(0), "PreSettlementSurplusAuctionHouse/high-bidder-not-set");
        require(bids[id].bidExpiry > now || bids[id].bidExpiry == 0, "PreSettlementSurplusAuctionHouse/bid-already-expired");
        require(bids[id].auctionDeadline > now, "PreSettlementSurplusAuctionHouse/auction-already-expired");

        require(amountToBuy == bids[id].amountToSell, "PreSettlementSurplusAuctionHouse/amounts-not-matching");
        require(bid > bids[id].bidAmount, "PreSettlementSurplusAuctionHouse/bid-not-higher");
        require(multiply(bid, ONE) >= multiply(bidIncrease, bids[id].bidAmount), "PreSettlementSurplusAuctionHouse/insufficient-increase");

        if (msg.sender != bids[id].highBidder) {
            protocolToken.move(msg.sender, bids[id].highBidder, bids[id].bidAmount);
            bids[id].highBidder = msg.sender;
        }
        protocolToken.move(msg.sender, address(this), bid - bids[id].bidAmount);

        bids[id].bidAmount = bid;
        bids[id].bidExpiry = addUint48(uint48(now), bidDuration);
    }
    function settleAuction(uint id) external emitLog {
        require(contractEnabled == 1, "PreSettlementSurplusAuctionHouse/contract-not-enabled");
        require(bids[id].bidExpiry != 0 && (bids[id].bidExpiry < now || bids[id].auctionDeadline < now), "PreSettlementSurplusAuctionHouse/not-finished");
        cdpEngine.transferInternalCoins(address(this), bids[id].highBidder, bids[id].amountToSell);
        protocolToken.burn(address(this), bids[id].bidAmount);
        delete bids[id];
    }

    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
        cdpEngine.transferInternalCoins(address(this), msg.sender, cdpEngine.coinBalance(address(this)));
    }
    function terminateAuctionPrematurely(uint id) external emitLog {
        require(contractEnabled == 0, "PreSettlementSurplusAuctionHouse/contract-still-enabled");
        require(bids[id].highBidder != address(0), "PreSettlementSurplusAuctionHouse/high-bidder-not-set");
        protocolToken.move(address(this), bids[id].highBidder, bids[id].bidAmount);
        delete bids[id];
    }
}

contract PostSettlementSurplusAuctionHouse is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 1;
    }
    function removeAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 0;
    }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "PostSettlementSurplusAuctionHouse/account-not-authorized");
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

    CDPEngineLike        public cdpEngine;
    TokenLike            public protocolToken;

    uint256  constant ONE = 1.00E18;
    uint256  public   bidIncrease = 1.05E18;
    uint48   public   bidDuration = 3 hours;
    uint48   public   totalAuctionLength = 2 days;
    uint256  public   auctionsStarted = 0;
    uint256  public   contractEnabled;

    bytes32 public constant AUCTION_HOUSE_TYPE = bytes32("SURPLUS");

    // --- Events ---
    event StartAuction(
        uint256 id,
        uint256 amountToSell,
        uint256 initialBid
    );

    // --- Init ---
    constructor(address cdpEngine_, address protocolToken_) public {
        authorizedAccounts[msg.sender] = 1;
        cdpEngine = CDPEngineLike(cdpEngine_);
        protocolToken = TokenLike(protocolToken_);
        contractEnabled = 1;
    }

    // --- Math ---
    function addUint48(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x);
    }
    function multiply(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Admin ---
    function modifyParameters(bytes32 parameter, uint data) external emitLog isAuthorized {
        if (parameter == "bidIncrease") bidIncrease = data;
        else if (parameter == "bidDuration") bidDuration = uint48(data);
        else if (parameter == "totalAuctionLength") totalAuctionLength = uint48(data);
        else revert("PostSettlementSurplusAuctionHouse/modify-unrecognized-param");
    }

    // --- Auction ---
    function startAuction(uint amountToSell, uint initialBid) external //isAuthorized
    returns (uint id) {
        require(auctionsStarted < uint(-1), "PostSettlementSurplusAuctionHouse/overflow");
        id = ++auctionsStarted;

        bids[id].bidAmount = initialBid;
        bids[id].amountToSell = amountToSell;
        bids[id].highBidder = msg.sender;
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);

        cdpEngine.transferInternalCoins(msg.sender, address(this), amountToSell);

        emit StartAuction(id, amountToSell, initialBid);
    }
    function restartAuction(uint id) external emitLog {
        require(bids[id].auctionDeadline < now, "PostSettlementSurplusAuctionHouse/not-finished");
        require(bids[id].bidExpiry == 0, "PostSettlementSurplusAuctionHouse/bid-already-placed");
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);
    }
    function increaseBidSize(uint id, uint amountToBuy, uint bid) external emitLog {
        require(bids[id].highBidder != address(0), "PostSettlementSurplusAuctionHouse/high-bidder-not-set");
        require(bids[id].bidExpiry > now || bids[id].bidExpiry == 0, "PostSettlementSurplusAuctionHouse/bid-already-expired");
        require(bids[id].auctionDeadline > now, "PostSettlementSurplusAuctionHouse/auction-already-expired");

        require(amountToBuy == bids[id].amountToSell, "PostSettlementSurplusAuctionHouse/amounts-not-matching");
        require(bid > bids[id].bidAmount, "PostSettlementSurplusAuctionHouse/bid-not-higher");
        require(multiply(bid, ONE) >= multiply(bidIncrease, bids[id].bidAmount), "PostSettlementSurplusAuctionHouse/insufficient-increase");

        if (msg.sender != bids[id].highBidder) {
            protocolToken.move(msg.sender, bids[id].highBidder, bids[id].bidAmount);
            bids[id].highBidder = msg.sender;
        }
        protocolToken.move(msg.sender, address(this), bid - bids[id].bidAmount);

        bids[id].bidAmount = bid;
        bids[id].bidExpiry = addUint48(uint48(now), bidDuration);
    }
    function settleAuction(uint id) external emitLog {
        require(bids[id].bidExpiry != 0 && (bids[id].bidExpiry < now || bids[id].auctionDeadline < now), "PostSettlementSurplusAuctionHouse/not-finished");
        cdpEngine.transferInternalCoins(address(this), bids[id].highBidder, bids[id].amountToSell);
        protocolToken.burn(address(this), bids[id].bidAmount);
        delete bids[id];
    }
}
