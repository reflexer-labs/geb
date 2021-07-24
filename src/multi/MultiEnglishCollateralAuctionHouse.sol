/// MultiEnglishCollateralAuctionHouse.sol

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

pragma solidity 0.6.7;

abstract contract SAFEEngineLike {
    function transferInternalCoins(bytes32,address,address,uint256) virtual external;
    function transferCollateral(bytes32,bytes32,address,address,uint256) virtual external;
}
abstract contract OracleRelayerLike {
    function redemptionPrice(bytes32) virtual public returns (uint256);
}
abstract contract OracleLike {
    function priceSource() virtual public view returns (address);
    function getResultWithValidity() virtual public view returns (uint256, bool);
}
abstract contract LiquidationEngineLike {
    function removeCoinsFromAuction(bytes32,bytes32,uint256) virtual public;
}

/*
   This thing lets you (English) auction some collateral for a given amount of system coins
*/

contract MultiEnglishCollateralAuctionHouse {
    // --- Auth ---
    mapping (address => uint256) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 1;
        emit AddAuthorization(account);
    }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 0;
        emit RemoveAuthorization(account);
    }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "MultiEnglishCollateralAuctionHouse/account-not-authorized");
        _;
    }

    // --- Data ---
    struct Bid {
        // Bid size (how many coins are offered per collateral sold)
        uint256 bidAmount;                                                                                            // [rad]
        // How much collateral is sold in an auction
        uint256 amountToSell;                                                                                         // [wad]
        // Who the high bidder is
        address highBidder;
        // When the latest bid expires and the auction can be settled
        uint48  bidExpiry;                                                                                            // [unix epoch time]
        // Hard deadline for the auction after which no more bids can be placed
        uint48  auctionDeadline;                                                                                      // [unix epoch time]
        // Who (which SAFE) receives leftover collateral that is not sold in the auction; usually the liquidated SAFE
        address forgoneCollateralReceiver;
        // Who receives the coins raised from the auction; usually the accounting engine
        address auctionIncomeRecipient;
        // Total/max amount of coins to raise
        uint256 amountToRaise;                                                                                        // [rad]
    }

    // Bid data for each separate auction
    mapping (uint256 => Bid) public bids;

    // The name of the coin that this contract handles
    bytes32        public coinName;

    // SAFE database
    SAFEEngineLike public safeEngine;
    // Collateral type name
    bytes32        public collateralType;

    uint256  constant ONE = 1.00E18;                                                                                  // [wad]
    // Minimum bid increase compared to the last bid in order to take the new one in consideration
    uint256  public   bidIncrease = 1.05E18;                                                                          // [wad]
    // How long the auction lasts after a new bid is submitted
    uint48   public   bidDuration = 3 hours;                                                                          // [seconds]
    // Total length of the auction
    uint48   public   totalAuctionLength = 2 days;                                                                    // [seconds]
    // Number of auctions started up until now
    uint256  public   auctionsStarted = 0;

    LiquidationEngineLike public liquidationEngine;

    bytes32 public constant AUCTION_HOUSE_TYPE = bytes32("COLLATERAL");
    bytes32 public constant AUCTION_TYPE       = bytes32("ENGLISH");

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event StartAuction(
        uint256 id,
        uint256 auctionsStarted,
        uint256 amountToSell,
        uint256 initialBid,
        uint256 indexed amountToRaise,
        address indexed forgoneCollateralReceiver,
        address indexed auctionIncomeRecipient,
        uint256 auctionDeadline
    );
    event ModifyParameters(bytes32 parameter, uint256 data);
    event ModifyParameters(bytes32 parameter, address data);
    event RestartAuction(uint256 indexed id, uint256 auctionDeadline);
    event IncreaseBidSize(uint256 indexed id, address highBidder, uint256 amountToBuy, uint256 rad, uint256 bidExpiry);
    event DecreaseSoldAmount(uint256 indexed id, address highBidder, uint256 amountToBuy, uint256 rad, uint256 bidExpiry);
    event SettleAuction(uint256 indexed id);
    event TerminateAuctionPrematurely(uint256 indexed id, address sender, uint256 bidAmount, uint256 collateralAmount);

    // --- Init ---
    constructor(bytes32 coinName_, address safeEngine_, address liquidationEngine_, bytes32 collateralType_) public {
        coinName          = coinName_;
        safeEngine        = SAFEEngineLike(safeEngine_);
        liquidationEngine = LiquidationEngineLike(liquidationEngine_);
        collateralType    = collateralType_;

        authorizedAccounts[msg.sender] = 1;
        emit AddAuthorization(msg.sender);
    }

    // --- Math ---
    function addUint48(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x, "MultiEnglishCollateralAuctionHouse/add-uint48-overflow");
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "MultiEnglishCollateralAuctionHouse/mul-overflow");
    }
    uint256 constant WAD = 10 ** 18;
    function wmultiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = multiply(x, y) / WAD;
    }
    uint256 constant RAY = 10 ** 27;
    function rdivide(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0, "MultiEnglishCollateralAuctionHouse/division-by-zero");
        z = multiply(x, RAY) / y;
    }

    // --- Admin ---
    /**
     * @notice Modify an uint256 parameter
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(bytes32 parameter, uint256 data) external isAuthorized {
        if (parameter == "bidIncrease") bidIncrease = data;
        else if (parameter == "bidDuration") bidDuration = uint48(data);
        else if (parameter == "totalAuctionLength") totalAuctionLength = uint48(data);
        else revert("MultiEnglishCollateralAuctionHouse/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }
    /**
     * @notice Modify an address parameter
     * @param parameter The name of the contract whose address we modify
     * @param data New contract address
     */
    function modifyParameters(bytes32 parameter, address data) external isAuthorized {
        if (parameter == "liquidationEngine") liquidationEngine = LiquidationEngineLike(data);
        else revert("MultiEnglishCollateralAuctionHouse/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }

    // --- Auction ---
    /**
     * @notice Start a new collateral auction
     * @param forgoneCollateralReceiver Address that receives leftover collateral that is not auctioned
     * @param auctionIncomeRecipient Address that receives the amount of system coins raised by the auction
     * @param amountToRaise Total amount of coins to raise (rad)
     * @param amountToSell Total amount of collateral available to sell (wad)
     * @param initialBid Initial bid size (usually zero in this implementation) (rad)
     */
    function startAuction(
        address forgoneCollateralReceiver,
        address auctionIncomeRecipient,
        uint256 amountToRaise,
        uint256 amountToSell,
        uint256 initialBid
    ) public isAuthorized returns (uint256 id)
    {
        require(auctionsStarted < uint256(-1), "MultiEnglishCollateralAuctionHouse/overflow");
        require(amountToSell > 0, "MultiEnglishCollateralAuctionHouse/null-amount-sold");
        id = ++auctionsStarted;

        bids[id].bidAmount = initialBid;
        bids[id].amountToSell = amountToSell;
        bids[id].highBidder = msg.sender;
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);
        bids[id].forgoneCollateralReceiver = forgoneCollateralReceiver;
        bids[id].auctionIncomeRecipient = auctionIncomeRecipient;
        bids[id].amountToRaise = amountToRaise;

        safeEngine.transferCollateral(coinName, collateralType, msg.sender, address(this), amountToSell);

        emit StartAuction(
          id,
          auctionsStarted,
          amountToSell,
          initialBid,
          amountToRaise,
          forgoneCollateralReceiver,
          auctionIncomeRecipient,
          bids[id].auctionDeadline
        );
    }
    /**
     * @notice Restart an auction if no bids were submitted for it
     * @param id ID of the auction to restart
     */
    function restartAuction(uint256 id) external {
        require(bids[id].auctionDeadline < now, "MultiEnglishCollateralAuctionHouse/not-finished");
        require(bids[id].bidExpiry == 0, "MultiEnglishCollateralAuctionHouse/bid-already-placed");
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);
        emit RestartAuction(id, bids[id].auctionDeadline);
    }
    /**
     * @notice First auction phase: submit a higher bid for the same amount of collateral
     * @param id ID of the auction you want to submit the bid for
     * @param amountToBuy Amount of collateral to buy (wad)
     * @param rad New bid submitted (rad)
     */
    function increaseBidSize(uint256 id, uint256 amountToBuy, uint256 rad) external {
        require(bids[id].highBidder != address(0), "MultiEnglishCollateralAuctionHouse/high-bidder-not-set");
        require(bids[id].bidExpiry > now || bids[id].bidExpiry == 0, "MultiEnglishCollateralAuctionHouse/bid-already-expired");
        require(bids[id].auctionDeadline > now, "MultiEnglishCollateralAuctionHouse/auction-already-expired");

        require(amountToBuy == bids[id].amountToSell, "MultiEnglishCollateralAuctionHouse/amounts-not-matching");
        require(rad <= bids[id].amountToRaise, "MultiEnglishCollateralAuctionHouse/higher-than-amount-to-raise");
        require(rad >  bids[id].bidAmount, "MultiEnglishCollateralAuctionHouse/new-bid-not-higher");
        require(multiply(rad, ONE) >= multiply(bidIncrease, bids[id].bidAmount) || rad == bids[id].amountToRaise, "MultiEnglishCollateralAuctionHouse/insufficient-increase");

        if (msg.sender != bids[id].highBidder) {
            safeEngine.transferInternalCoins(coinName, msg.sender, bids[id].highBidder, bids[id].bidAmount);
            bids[id].highBidder = msg.sender;
        }
        safeEngine.transferInternalCoins(coinName, msg.sender, bids[id].auctionIncomeRecipient, rad - bids[id].bidAmount);

        bids[id].bidAmount = rad;
        bids[id].bidExpiry = addUint48(uint48(now), bidDuration);

        emit IncreaseBidSize(id, msg.sender, amountToBuy, rad, bids[id].bidExpiry);
    }
    /**
     * @notice Second auction phase: decrease the collateral amount you're willing to receive in
     *         exchange for providing the same amount of coins as the winning bid
     * @param id ID of the auction for which you want to submit a new amount of collateral to buy
     * @param amountToBuy Amount of collateral to buy (must be smaller than the previous proposed amount) (wad)
     * @param rad New bid submitted; must be equal to the winning bid from the increaseBidSize phase (rad)
     */
    function decreaseSoldAmount(uint256 id, uint256 amountToBuy, uint256 rad) external {
        require(bids[id].highBidder != address(0), "MultiEnglishCollateralAuctionHouse/high-bidder-not-set");
        require(bids[id].bidExpiry > now || bids[id].bidExpiry == 0, "MultiEnglishCollateralAuctionHouse/bid-already-expired");
        require(bids[id].auctionDeadline > now, "MultiEnglishCollateralAuctionHouse/auction-already-expired");

        require(rad == bids[id].bidAmount, "MultiEnglishCollateralAuctionHouse/not-matching-bid");
        require(rad == bids[id].amountToRaise, "MultiEnglishCollateralAuctionHouse/bid-increase-not-finished");
        require(amountToBuy < bids[id].amountToSell, "MultiEnglishCollateralAuctionHouse/amount-bought-not-lower");
        require(multiply(bidIncrease, amountToBuy) <= multiply(bids[id].amountToSell, ONE), "MultiEnglishCollateralAuctionHouse/insufficient-decrease");

        if (msg.sender != bids[id].highBidder) {
            safeEngine.transferInternalCoins(coinName, msg.sender, bids[id].highBidder, rad);
            bids[id].highBidder = msg.sender;
        }
        safeEngine.transferCollateral(
            coinName,
            collateralType,
            address(this),
            bids[id].forgoneCollateralReceiver,
            bids[id].amountToSell - amountToBuy
        );

        bids[id].amountToSell = amountToBuy;
        bids[id].bidExpiry    = addUint48(uint48(now), bidDuration);

        emit DecreaseSoldAmount(id, msg.sender, amountToBuy, rad, bids[id].bidExpiry);
    }
    /**
     * @notice Settle/finish an auction
     * @param id ID of the auction to settle
     */
    function settleAuction(uint256 id) external {
        require(bids[id].bidExpiry != 0 && (bids[id].bidExpiry < now || bids[id].auctionDeadline < now), "MultiEnglishCollateralAuctionHouse/not-finished");
        safeEngine.transferCollateral(coinName, collateralType, address(this), bids[id].highBidder, bids[id].amountToSell);
        liquidationEngine.removeCoinsFromAuction(coinName, collateralType, bids[id].amountToRaise);
        delete bids[id];
        emit SettleAuction(id);
    }
    /**
     * @notice Terminate an auction prematurely (if it's still in the first phase).
     *         Usually called by Global Settlement.
     * @param id ID of the auction to settle
     */
    function terminateAuctionPrematurely(uint256 id) external isAuthorized {
        require(bids[id].highBidder != address(0), "MultiEnglishCollateralAuctionHouse/high-bidder-not-set");
        require(bids[id].bidAmount < bids[id].amountToRaise, "MultiEnglishCollateralAuctionHouse/already-decreasing-sold-amount");
        liquidationEngine.removeCoinsFromAuction(coinName, collateralType, bids[id].amountToRaise);
        safeEngine.transferCollateral(coinName, collateralType, address(this), msg.sender, bids[id].amountToSell);
        safeEngine.transferInternalCoins(coinName, msg.sender, bids[id].highBidder, bids[id].bidAmount);
        emit TerminateAuctionPrematurely(id, msg.sender, bids[id].bidAmount, bids[id].amountToSell);
        delete bids[id];
    }

    // --- Getters ---
    function bidAmount(uint256 id) public view returns (uint256) {
        return bids[id].bidAmount;
    }
    function remainingAmountToSell(uint256 id) public view returns (uint256) {
        return bids[id].amountToSell;
    }
    function forgoneCollateralReceiver(uint256 id) public view returns (address) {
        return bids[id].forgoneCollateralReceiver;
    }
    function raisedAmount(uint256 id) public view returns (uint256) {
        return 0;
    }
    function amountToRaise(uint256 id) public view returns (uint256) {
        return bids[id].amountToRaise;
    }
}
