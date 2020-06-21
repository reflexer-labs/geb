/// SurplusAuctionHouse.sol

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
// Copyright (C) 2020 Stefan C. Ionescu <stefanionescu@protonmail.com>
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
    function coinBalance(address) external view returns (uint);
    function approveCDPModification(address) external;
    function denyCDPModification(address) external;
}
contract TokenLike {
    function approve(address, uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
    function move(address,address,uint) external;
    function burn(address,uint) external;
}

/*
   This thing lets you auction some coins in return for protocol tokens
*/

contract SurplusAuctionHouseOne is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 1;
    }
    function removeAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 0;
    }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "SurplusAuctionHouseOne/account-not-authorized");
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
    function add(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Admin ---
    function modifyParameters(bytes32 parameter, uint data) external emitLog isAuthorized {
        if (parameter == "bidIncrease") bidIncrease = data;
        else if (parameter == "bidDuration") bidDuration = uint48(data);
        else if (parameter == "totalAuctionLength") totalAuctionLength = uint48(data);
        else revert("SurplusAuctionHouseOne/modify-unrecognized-param");
    }

    // --- Auction ---
    function startAuction(uint amountToSell, uint initialBid) external isAuthorized returns (uint id) {
        require(contractEnabled == 1, "SurplusAuctionHouseOne/contract-not-enabled");
        require(auctionsStarted < uint(-1), "SurplusAuctionHouseOne/overflow");
        id = ++auctionsStarted;

        bids[id].bidAmount = initialBid;
        bids[id].amountToSell = amountToSell;
        bids[id].highBidder = msg.sender;
        bids[id].auctionDeadline = add(uint48(now), totalAuctionLength);

        cdpEngine.transferInternalCoins(msg.sender, address(this), amountToSell);

        emit StartAuction(id, amountToSell, initialBid);
    }
    function restartAuction(uint id) external emitLog {
        require(bids[id].auctionDeadline < now, "SurplusAuctionHouseOne/not-finished");
        require(bids[id].bidExpiry == 0, "SurplusAuctionHouseOne/bid-already-placed");
        bids[id].auctionDeadline = add(uint48(now), totalAuctionLength);
    }
    function increaseBidSize(uint id, uint amountToBuy, uint bid) external emitLog {
        require(contractEnabled == 1, "SurplusAuctionHouseOne/contract-not-enabled");
        require(bids[id].highBidder != address(0), "SurplusAuctionHouseOne/high-bidder-not-set");
        require(bids[id].bidExpiry > now || bids[id].bidExpiry == 0, "SurplusAuctionHouseOne/bid-already-expired");
        require(bids[id].auctionDeadline > now, "SurplusAuctionHouseOne/auction-already-expired");

        require(amountToBuy == bids[id].amountToSell, "SurplusAuctionHouseOne/amounts-not-matching");
        require(bid > bids[id].bidAmount, "SurplusAuctionHouseOne/bid-not-higher");
        require(mul(bid, ONE) >= mul(bidIncrease, bids[id].bidAmount), "SurplusAuctionHouseOne/insufficient-increase");

        if (msg.sender != bids[id].highBidder) {
            protocolToken.move(msg.sender, bids[id].highBidder, bids[id].bidAmount);
            bids[id].highBidder = msg.sender;
        }
        protocolToken.move(msg.sender, address(this), bid - bids[id].bidAmount);

        bids[id].bidAmount = bid;
        bids[id].bidExpiry = add(uint48(now), bidDuration);
    }
    function settleAuction(uint id) external emitLog {
        require(contractEnabled == 1, "SurplusAuctionHouseOne/contract-not-enabled");
        require(bids[id].bidExpiry != 0 && (bids[id].bidExpiry < now || bids[id].auctionDeadline < now), "SurplusAuctionHouseOne/not-finished");
        cdpEngine.transferInternalCoins(address(this), bids[id].highBidder, bids[id].amountToSell);
        protocolToken.burn(address(this), bids[id].bidAmount);
        delete bids[id];
    }

    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
        cdpEngine.transferInternalCoins(address(this), msg.sender, cdpEngine.coinBalance(address(this)));
    }
    function terminateAuctionPrematurely(uint id) external emitLog {
        require(contractEnabled == 0, "SurplusAuctionHouseOne/contract-still-enabled");
        require(bids[id].highBidder != address(0), "SurplusAuctionHouseOne/high-bidder-not-set");
        protocolToken.move(address(this), bids[id].highBidder, bids[id].bidAmount);
        delete bids[id];
    }
}

contract SurplusAuctionHouseTwo is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 1;
    }
    function removeAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 0;
    }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "SurplusAuctionHouseTwo/account-not-authorized");
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
    function add(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Admin ---
    function modifyParameters(bytes32 parameter, uint data) external emitLog isAuthorized {
        if (parameter == "bidIncrease") bidIncrease = data;
        else if (parameter == "bidDuration") bidDuration = uint48(data);
        else if (parameter == "totalAuctionLength") totalAuctionLength = uint48(data);
        else revert("SurplusAuctionHouseTwo/modify-unrecognized-param");
    }

    // --- Auction ---
    function startAuction(uint amountToSell, uint initialBid) external //isAuthorized
    returns (uint id) {
        require(auctionsStarted < uint(-1), "SurplusAuctionHouseTwo/overflow");
        id = ++auctionsStarted;

        bids[id].bidAmount = initialBid;
        bids[id].amountToSell = amountToSell;
        bids[id].highBidder = msg.sender;
        bids[id].auctionDeadline = add(uint48(now), totalAuctionLength);

        cdpEngine.transferInternalCoins(msg.sender, address(this), amountToSell);

        emit StartAuction(id, amountToSell, initialBid);
    }
    function restartAuction(uint id) external emitLog {
        require(bids[id].auctionDeadline < now, "SurplusAuctionHouseTwo/not-finished");
        require(bids[id].bidExpiry == 0, "SurplusAuctionHouseTwo/bid-already-placed");
        bids[id].auctionDeadline = add(uint48(now), totalAuctionLength);
    }
    function increaseBidSize(uint id, uint amountToBuy, uint bid) external emitLog {
        require(bids[id].highBidder != address(0), "SurplusAuctionHouseTwo/high-bidder-not-set");
        require(bids[id].bidExpiry > now || bids[id].bidExpiry == 0, "SurplusAuctionHouseTwo/bid-already-expired");
        require(bids[id].auctionDeadline > now, "SurplusAuctionHouseTwo/auction-already-expired");

        require(amountToBuy == bids[id].amountToSell, "SurplusAuctionHouseTwo/amounts-not-matching");
        require(bid > bids[id].bidAmount, "SurplusAuctionHouseTwo/bid-not-higher");
        require(mul(bid, ONE) >= mul(bidIncrease, bids[id].bidAmount), "SurplusAuctionHouseTwo/insufficient-increase");

        if (msg.sender != bids[id].highBidder) {
            protocolToken.move(msg.sender, bids[id].highBidder, bids[id].bidAmount);
            bids[id].highBidder = msg.sender;
        }
        protocolToken.move(msg.sender, address(this), bid - bids[id].bidAmount);

        bids[id].bidAmount = bid;
        bids[id].bidExpiry = add(uint48(now), bidDuration);
    }
    function settleAuction(uint id) external emitLog {
        require(bids[id].bidExpiry != 0 && (bids[id].bidExpiry < now || bids[id].auctionDeadline < now), "SurplusAuctionHouseOne/not-finished");
        cdpEngine.transferInternalCoins(address(this), bids[id].highBidder, bids[id].amountToSell);
        protocolToken.burn(address(this), bids[id].bidAmount);
        delete bids[id];
    }
}
