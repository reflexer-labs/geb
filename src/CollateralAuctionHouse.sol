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

pragma solidity ^0.6.7;

import "./Logging.sol";

abstract contract CDPEngineLike {
    function transferInternalCoins(address,address,uint) virtual external;
    function transferCollateral(bytes32,address,address,uint) virtual external;
}
abstract contract OracleRelayerLike {
    function redemptionPrice() virtual public returns (uint256);
}
abstract contract OracleLike {
    function getResultWithValidity() virtual public returns (bytes32, bool);
}

/*
   This thing lets you auction some collateral for a given amount of system coins
*/

contract CollateralAuctionHouse is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "CollateralAuctionHouse/account-not-authorized");
        _;
    }

    // --- Data ---
    struct Bid {
        // Bid size (how many coins are offered per collateral sold)
        uint256 bidAmount;
        // How much collateral is sold in an auction
        uint256 amountToSell;
        // Who the high bidder is
        address highBidder;
        // When the latest bid expires and the auction can be settled
        uint48  bidExpiry;
        // Hard deadline for the auction after which no more bids can be places
        uint48  auctionDeadline;
        // Who (which CDP) receives leftover collateral that is not sold in the auction; usually the liquidated CDP
        address forgoneCollateralReceiver;
        // Who receives the coins raised from the auction; usually the accounting engine
        address auctionIncomeRecipient;
        // Total/max amount of coins to raise
        uint256 amountToRaise;
    }

    // Bid data for each separate auction
    mapping (uint => Bid) public bids;

    // CDP database
    CDPEngineLike public cdpEngine;
    // Collateral type name
    bytes32       public collateralType;

    uint256  constant ONE = 1.00E18;
    // Minimum bid increase compared to the last bid in order to take the new one in consideration
    uint256  public   bidIncrease = 1.05E18;
    // How long the first phase of the auction lasts after a new bid is submitted
    uint48   public   bidDuration = 3 hours;
    // Total length of the auction
    uint48   public   totalAuctionLength = 2 days;
    // Number of auctions started up until now
    uint256  public   auctionsStarted = 0;
    // Minimum mandatory size of the first bid compared to collateral price coming from the oracle
    uint256  public bidToMarketPriceRatio; // [ray]

    OracleRelayerLike public oracleRelayer;
    OracleLike        public orcl;

    // --- Events ---
    event StartAuction(
        uint256 id,
        uint256 amountToSell,
        uint256 initialBid,
        uint256 amountToRaise,
        address indexed forgoneCollateralReceiver,
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
    /**
     * @notice Modify auction parameters
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(bytes32 parameter, uint data) external emitLog isAuthorized {
        if (parameter == "bidIncrease") bidIncrease = data;
        else if (parameter == "bidDuration") bidDuration = uint48(data);
        else if (parameter == "totalAuctionLength") totalAuctionLength = uint48(data);
        else if (parameter == "bidToMarketPriceRatio") bidToMarketPriceRatio = data;
        else revert("CollateralAuctionHouse/modify-unrecognized-param");
    }
    /**
     * @notice Modify oracle related integrations
     * @param parameter The name of the oracle contract modified
     * @param data New address for the oracle contract
     */
    function modifyParameters(bytes32 parameter, address data) external emitLog isAuthorized {
        if (parameter == "oracleRelayer") oracleRelayer = OracleRelayerLike(data);
        else if (parameter == "orcl") orcl = OracleLike(data);
        else revert("CollateralAuctionHouse/modify-unrecognized-param");
    }

    // --- Auction ---
    /**
     * @notice Start a new collateral auction
     * @param forgoneCollateralReceiver Who receives leftover collateral that is not auctioned
     * @param auctionIncomeRecipient Who receives the amount raised in the auction
     * @param amountToRaise Total amount of coins to raise
     * @param amountToSell Total amount of collateral available to sell
     * @param initialBid Initial bid size (usually zero in this implementation)
     */
    function startAuction(
        address forgoneCollateralReceiver,
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
        bids[id].forgoneCollateralReceiver = forgoneCollateralReceiver;
        bids[id].auctionIncomeRecipient = auctionIncomeRecipient;
        bids[id].amountToRaise = amountToRaise;

        cdpEngine.transferCollateral(collateralType, msg.sender, address(this), amountToSell);

        emit StartAuction(id, amountToSell, initialBid, amountToRaise, forgoneCollateralReceiver, auctionIncomeRecipient);
    }
    /**
     * @notice Restart an auction if no bids were submitted for it
     * @param id ID of the auction to restart
     */
    function restartAuction(uint id) external emitLog {
        require(bids[id].auctionDeadline < now, "CollateralAuctionHouse/not-finished");
        require(bids[id].bidExpiry == 0, "CollateralAuctionHouse/bid-already-placed");
        bids[id].auctionDeadline = add(uint48(now), totalAuctionLength);
    }
    /**
     * @notice First auction phase: submit a higher bid for the same amount of collateral
     * @param id ID of the auction you want to submit the bid for
     * @param amountToBuy Amount of collateral to buy (must be equal to the amount sold in this implementation)
     * @param bid New bid submitted
     */
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
            (bytes32 priceFeedValue, bool hasValidValue) = orcl.getResultWithValidity();
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
    /**
     * @notice Second auction phase: decrease the collateral amount you're willing to receive in
     *         exchange for providing the same amount of coins as the winning bid
     * @param id ID of the auction for which you want to submit a new amount of collateral to buy
     * @param amountToBuy Amount of collateral to buy (must be smaller than the previous proposed amount)
     * @param bid New bid submitted; must be equal to the winning bid in this implementation
     */
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
        cdpEngine.transferCollateral(
          collateralType,
          address(this),
          bids[id].forgoneCollateralReceiver,
          bids[id].amountToSell - amountToBuy
        );

        bids[id].amountToSell = amountToBuy;
        bids[id].bidExpiry    = add(uint48(now), bidDuration);
    }
    /**
     * @notice Settle/finish an auction
     * @param id ID of the auction to settle
     */
    function settleAuction(uint id) external emitLog {
        require(bids[id].bidExpiry != 0 && (bids[id].bidExpiry < now || bids[id].auctionDeadline < now), "CollateralAuctionHouse/not-finished");
        cdpEngine.transferCollateral(collateralType, address(this), bids[id].highBidder, bids[id].amountToSell);
        delete bids[id];
    }
    /**
     * @notice Terminate an auction prematurely (if it's still in the first phase).
     *         Usually called by Global Settlement
     * @param id ID of the auction to terminate
     */
    function terminateAuctionPrematurely(uint id) external emitLog isAuthorized {
        require(bids[id].highBidder != address(0), "CollateralAuctionHouse/high-bidder-not-set");
        require(bids[id].bidAmount < bids[id].amountToRaise, "CollateralAuctionHouse/already-decreasing-sold-amount");
        cdpEngine.transferCollateral(collateralType, address(this), msg.sender, bids[id].amountToSell);
        cdpEngine.transferInternalCoins(msg.sender, bids[id].highBidder, bids[id].bidAmount);
        delete bids[id];
    }
}
