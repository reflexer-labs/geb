/// CollateralAuctionHouse.sol

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
    function transferCollateral(bytes32,address,address,uint) external;
}
contract OracleRelayerLike {
    function redemptionPrice() public returns (uint256);
}
contract OracleLike {
    function getPriceWithValidity() external returns (bytes32, bool);
}

/*
   This thing lets you auction some collateral for a given amount of system coins
*/

contract CollateralAuctionHouse is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "CollateralAuctionHouse/account-not-authorized");
        _;
    }

    // --- Data ---
    struct Bid {
        uint256 bidAmount;
        uint256 amountToSell;
        address highBidder;
        uint48  bidExpiry;
        uint48  auctionDeadline;
        address cdpAuctioned;
        address auctionIncomeRecipient;
        uint256 amountToRaise;
    }

    mapping (uint => Bid) public bids;

    CDPEngineLike public cdpEngine;
    bytes32       public collateralType;

    uint256  constant ONE = 1.00E18;
    uint256  public   bidIncrease = 1.05E18;
    uint48   public   bidDuration = 3 hours;
    uint48   public   totalAuctionLength = 2 days;
    uint256  public   auctionsStarted = 0;

    OracleRelayerLike public oracleRelayer;
    OracleLike        public orcl;                  // medianizer / whatever the OSM reads from
    uint256           public bidToMarketPriceRatio; // [ray]

    // --- Events ---
    event StartAuction(
      uint256 id,
      uint256 amountToSell,
      uint256 initialBid,
      uint256 amountToRaise,
      address indexed cdpAuctioned,
      address indexed auctionIncomeRecipient
    );

    // --- Init ---
    constructor(address cdpEngine_, bytes32 collateralType_) public {
        cdpEngine = CDPEngineLike(cdpEngine_);
        collateralType = collateralType_;
        authorizedAccounts[msg.sender] = 1;
    }

    // --- Math ---
    function add(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    uint256 constant WAD = 10 ** 18;
    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, y) / WAD;
    }
    uint256 constant RAY = 10 ** 27;
    function rdiv(uint x, uint y) internal pure returns (uint z) {
      z = mul(x, RAY) / y;
    }

    // --- Admin ---
    function modifyParameters(bytes32 parameter, uint data) external emitLog isAuthorized {
        if (parameter == "bidIncrease") bidIncrease = data;
        else if (parameter == "bidDuration") bidDuration = uint48(data);
        else if (parameter == "totalAuctionLength") totalAuctionLength = uint48(data);
        else if (what == "bidToMarketPriceRatio") bidToMarketPriceRatio = data;
        else revert("CollateralAuctionHouse/modify-unrecognized-param");
    }
    function modifyParameters(bytes32 parameter, address data) external emitLog isAuthorized {
        if (parameter == "oracleRelayer") oracleRelayer = OracleRelayerLike(data);
        else if (parameter == "orcl") orcl = OracleLike(data);
        else revert("CollateralAuctionHouse/modify-unrecognized-param");
    }

    // --- Auction ---
    function kick(
      address cdpAuctioned,
      address auctionIncomeRecipient,
      uint amountToRaise,
      uint amountToSell,
      uint initialBid
    ) public isAuthorized returns (uint id)
    {
        require(auctionsStarted < uint(-1), "CollateralAuctionHouse/overflow");
        id = ++auctionsStarted;

        bids[id].bidAmount = initialBid;
        bids[id].amountToSell = amountToSell;
        bids[id].highBidder = msg.sender;
        bids[id].auctionDeadline = add(uint48(now), totalAuctionLength);
        bids[id].cdpAuctioned = cdpAuctioned;
        bids[id].auctionIncomeRecipient = auctionIncomeRecipient;
        bids[id].amountToRaise = amountToRaise;

        cdpEngine.transferCollateral(collateralType, msg.sender, address(this), amountToSell);

        emit StartAuction(id, amountToSell, initialBid, amountToRaise, cdpAuctioned, auctionIncomeRecipient);
    }
    function restartAuction(uint id) external emitLog {
        require(bids[id].auctionDeadline < now, "CollateralAuctionHouse/not-finished");
        require(bids[id].bidExpiry == 0, "CollateralAuctionHouse/bid-already-placed");
        bids[id].auctionDeadline = add(uint48(now), totalAuctionLength);
    }
    function increaseBidSize(uint id, uint amountToBuy, uint bid) external emitLog {
        require(bids[id].highBidder != address(0), "CollateralAuctionHouse/high-bidder-not-set");
        require(bids[id].bidExpiry > now || bids[id].bidExpiry == 0, "CollateralAuctionHouse/bid-already-expired");
        require(bids[id].auctionDeadline > now, "CollateralAuctionHouse/auction-already-expired");

        require(amountToBuy == bids[id].amountToSell, "CollateralAuctionHouse/amounts-not-matching");
        require(bid <= bids[id].amountToRaise, "CollateralAuctionHouse/higher-than-amount-to-raise");
        require(bid >  bids[id].bidAmount, "CollateralAuctionHouse/new-bid-not-higher");
        require(mul(bid, ONE) >= mul(bidIncrease, bids[id].bidAmount) || bid == bids[id].amountToRaise, "CollateralAuctionHouse/insufficient-increase");

        // check for first bid only
        if (bids[id].bidAmount == 0) {
            (bytes32 priceFeedValue, bool hasValidValue) = orcl.getPriceWithValidity();
            if (hasValidValue) {
                uint256 redemptionPrice = oracleRelayer.redemptionPrice();
                require(bid >= mul(wmul(rdiv(uint256(priceFeedValue), redemptionPrice), amountToBuy), bidToMarketPriceRatio), "CollateralAuctionHouse/first-bid-too-low");
            }
        }

        if (msg.sender != bids[id].highBidder) {
            cdpEngine.transferInternalCoins(msg.sender, bids[id].highBidder, bids[id].bidAmount);
            bids[id].highBidder = msg.sender;
        }
        cdpEngine.transferInternalCoins(msg.sender, bids[id].auctionIncomeRecipient, bid - bids[id].bidAmount);

        bids[id].bidAmount = bid;
        bids[id].bidExpiry = add(uint48(now), bidDuration);
    }
    function decreaseSoldAmount(uint id, uint amountToBuy, uint bid) external emitLog {
        require(bids[id].highBidder != address(0), "CollateralAuctionHouse/high-bidder-not-set");
        require(bids[id].bidExpiry > now || bids[id].bidExpiry == 0, "CollateralAuctionHouse/bid-already-expired");
        require(bids[id].auctionDeadline > now, "CollateralAuctionHouse/auction-already-expired");

        require(bid == bids[id].bidAmount, "CollateralAuctionHouse/not-matching-bid");
        require(bid == bids[id].amountToRaise, "CollateralAuctionHouse/bid-increase-not-finished");
        require(amountToBuy < bids[id].amountToSell, "CollateralAuctionHouse/amount-bought-not-lower");
        require(mul(bidIncrease, amountToBuy) <= mul(bids[id].amountToSell, ONE), "CollateralAuctionHouse/insufficient-decrease");

        if (msg.sender != bids[id].highBidder) {
            cdpEngine.transferInternalCoins(msg.sender, bids[id].highBidder, bid);
            bids[id].highBidder = msg.sender;
        }
        cdpEngine.transferCollateral(collateralType, address(this), bids[id].cdp, bids[id].amountToSell - amountToBuy);

        bids[id].amountToSell = amountToBuy;
        bids[id].bidExpiry    = add(uint48(now), bidDuration);
    }
    function settleAuction(uint id) external emitLog {
        require(bids[id].bidExpiry != 0 && (bids[id].bidExpiry < now || bids[id].auctionDeadline < now), "CollateralAuctionHouse/not-finished");
        cdpEngine.transferCollateral(collateralType, address(this), bids[id].highBidder, bids[id].amountToSell);
        delete bids[id];
    }

    function terminateAuctionPrematurely(uint id) external emitLog isAuthorized {
        require(bids[id].highBidder != address(0), "CollateralAuctionHouse/high-bidder-not-set");
        require(bids[id].bidAmount < bids[id].amountToRaise, "CollateralAuctionHouse/already-decreasing-sold-amount");
        cdpEngine.transferCollateral(collateralType, address(this), msg.sender, bids[id].amountToSell);
        cdpEngine.transferInternalCoins(msg.sender, bids[id].highBidder, bids[id].bidAmount);
        delete bids[id];
    }
}
