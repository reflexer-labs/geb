/// MultiSurplusAuctionHouse.sol

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
    function coinBalance(bytes32,address) virtual external view returns (uint256);
    function approveSAFEModification(bytes32,address) virtual external;
    function denySAFEModification(bytes32,address) virtual external;
}
abstract contract TokenLike {
    function approve(address,uint256) virtual public returns (bool);
    function balanceOf(address) virtual public view returns (uint256);
    function move(address,address,uint256) virtual external;
    function burn(address,uint256) virtual external;
}

/*
   This thing lets you auction some system coins in return for protocol tokens that are then burnt
*/

contract BurningMultiSurplusAuctionHouse {
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
        require(authorizedAccounts[msg.sender] == 1, "BurningMultiSurplusAuctionHouse/account-not-authorized");
        _;
    }

    // --- Data ---
    struct Bid {
        // Bid size (how many protocol tokens are offered per system coins sold)
        uint256 bidAmount;                                                            // [wad]
        // How many system coins are sold in an auction
        uint256 amountToSell;                                                         // [rad]
        // Who the high bidder is
        address highBidder;
        // When the latest bid expires and the auction can be settled
        uint48  bidExpiry;                                                            // [unix epoch time]
        // Hard deadline for the auction after which no more bids can be placed
        uint48  auctionDeadline;                                                      // [unix epoch time]
    }

    // The coin handled by this contract
    bytes32  public coinName;

    // Bid data for each separate auction
    mapping (uint256 => Bid) public bids;

    // SAFE database
    SAFEEngineLike public safeEngine;
    // Protocol token address
    TokenLike      public protocolToken;

    uint256  constant ONE = 1.00E18;                                                  // [wad]
    // Minimum bid increase compared to the last bid in order to take the new one in consideration
    uint256  public   bidIncrease = 1.05E18;                                          // [wad]
    // How long the auction lasts after a new bid is submitted
    uint48   public   bidDuration = 3 hours;                                          // [seconds]
    // Total length of the auction
    uint48   public   totalAuctionLength = 2 days;                                    // [seconds]
    // Number of auctions started up until now
    uint256  public   auctionsStarted = 0;
    // Whether the contract is settled or not
    uint256  public   contractEnabled;

    bytes32 public constant AUCTION_HOUSE_TYPE   = bytes32("SURPLUS");
    bytes32 public constant SURPLUS_AUCTION_TYPE = bytes32("BURNING");

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event ModifyParameters(bytes32 parameter, uint256 data);
    event RestartAuction(uint256 id, uint256 auctionDeadline);
    event IncreaseBidSize(uint256 id, address highBidder, uint256 amountToBuy, uint256 bid, uint256 bidExpiry);
    event StartAuction(
        uint256 indexed id,
        uint256 auctionsStarted,
        uint256 amountToSell,
        uint256 initialBid,
        uint256 auctionDeadline
    );
    event SettleAuction(uint256 indexed id);
    event DisableContract();
    event TerminateAuctionPrematurely(uint256 indexed id, address sender, address highBidder, uint256 bidAmount);

    // --- Init ---
    constructor(bytes32 coinName_, address safeEngine_, address protocolToken_) public {
        authorizedAccounts[msg.sender] = 1;
        coinName = coinName_;

        safeEngine = SAFEEngineLike(safeEngine_);
        protocolToken = TokenLike(protocolToken_);

        contractEnabled = 1;

        emit AddAuthorization(msg.sender);
    }

    // --- Math ---
    function addUint48(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x, "BurningMultiSurplusAuctionHouse/add-uint48-overflow");
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "BurningMultiSurplusAuctionHouse/mul-overflow");
    }

    // --- Admin ---
    /**
     * @notice Modify auction parameters
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(bytes32 parameter, uint256 data) external isAuthorized {
        if (parameter == "bidIncrease") bidIncrease = data;
        else if (parameter == "bidDuration") bidDuration = uint48(data);
        else if (parameter == "totalAuctionLength") totalAuctionLength = uint48(data);
        else revert("BurningMultiSurplusAuctionHouse/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }

    // --- Auction ---
    /**
     * @notice Start a new surplus auction
     * @param amountToSell Total amount of system coins to sell (rad)
     * @param initialBid Initial protocol token bid (wad)
     */
    function startAuction(uint256 amountToSell, uint256 initialBid) external isAuthorized returns (uint256 id) {
        require(contractEnabled == 1, "BurningMultiSurplusAuctionHouse/contract-not-enabled");
        require(auctionsStarted < uint256(-1), "BurningMultiSurplusAuctionHouse/overflow");
        id = ++auctionsStarted;

        bids[id].bidAmount = initialBid;
        bids[id].amountToSell = amountToSell;
        bids[id].highBidder = msg.sender;
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);

        safeEngine.transferInternalCoins(coinName, msg.sender, address(this), amountToSell);

        emit StartAuction(id, auctionsStarted, amountToSell, initialBid, bids[id].auctionDeadline);
    }
    /**
     * @notice Restart an auction if no bids were submitted for it
     * @param id ID of the auction to restart
     */
    function restartAuction(uint256 id) external {
        require(bids[id].auctionDeadline < now, "BurningMultiSurplusAuctionHouse/not-finished");
        require(bids[id].bidExpiry == 0, "BurningMultiSurplusAuctionHouse/bid-already-placed");
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);
        emit RestartAuction(id, bids[id].auctionDeadline);
    }
    /**
     * @notice Submit a higher protocol token bid for the same amount of system coins
     * @param id ID of the auction you want to submit the bid for
     * @param amountToBuy Amount of system coins to buy (rad)
     * @param bid New bid submitted (wad)
     */
    function increaseBidSize(uint256 id, uint256 amountToBuy, uint256 bid) external {
        require(contractEnabled == 1, "BurningMultiSurplusAuctionHouse/contract-not-enabled");
        require(bids[id].highBidder != address(0), "BurningMultiSurplusAuctionHouse/high-bidder-not-set");
        require(bids[id].bidExpiry > now || bids[id].bidExpiry == 0, "BurningMultiSurplusAuctionHouse/bid-already-expired");
        require(bids[id].auctionDeadline > now, "BurningMultiSurplusAuctionHouse/auction-already-expired");

        require(amountToBuy == bids[id].amountToSell, "BurningMultiSurplusAuctionHouse/amounts-not-matching");
        require(bid > bids[id].bidAmount, "BurningMultiSurplusAuctionHouse/bid-not-higher");
        require(multiply(bid, ONE) >= multiply(bidIncrease, bids[id].bidAmount), "BurningMultiSurplusAuctionHouse/insufficient-increase");

        if (msg.sender != bids[id].highBidder) {
            protocolToken.move(msg.sender, bids[id].highBidder, bids[id].bidAmount);
            bids[id].highBidder = msg.sender;
        }
        protocolToken.move(msg.sender, address(this), bid - bids[id].bidAmount);

        bids[id].bidAmount = bid;
        bids[id].bidExpiry = addUint48(uint48(now), bidDuration);

        emit IncreaseBidSize(id, msg.sender, amountToBuy, bid, bids[id].bidExpiry);
    }
    /**
     * @notice Settle/finish an auction
     * @param id ID of the auction to settle
     */
    function settleAuction(uint256 id) external {
        require(contractEnabled == 1, "BurningMultiSurplusAuctionHouse/contract-not-enabled");
        require(bids[id].bidExpiry != 0 && (bids[id].bidExpiry < now || bids[id].auctionDeadline < now), "BurningMultiSurplusAuctionHouse/not-finished");
        safeEngine.transferInternalCoins(coinName, address(this), bids[id].highBidder, bids[id].amountToSell);
        protocolToken.burn(address(this), bids[id].bidAmount);
        delete bids[id];
        emit SettleAuction(id);
    }
    /**
    * @notice Disable the auction house
    **/
    function disableContract() external isAuthorized {
        contractEnabled = 0;
        safeEngine.transferInternalCoins(coinName, address(this), msg.sender, safeEngine.coinBalance(coinName, address(this)));
        emit DisableContract();
    }
    /**
     * @notice Terminate an auction prematurely.
     * @param id ID of the auction to settle/terminate
     */
    function terminateAuctionPrematurely(uint256 id) external {
        require(contractEnabled == 0, "BurningMultiSurplusAuctionHouse/contract-still-enabled");
        require(bids[id].highBidder != address(0), "BurningMultiSurplusAuctionHouse/high-bidder-not-set");
        protocolToken.move(address(this), bids[id].highBidder, bids[id].bidAmount);
        emit TerminateAuctionPrematurely(id, msg.sender, bids[id].highBidder, bids[id].bidAmount);
        delete bids[id];
    }
}

// This thing lets you auction surplus for protocol tokens that are then sent to another address

contract RecyclingMultiSurplusAuctionHouse {
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
        require(authorizedAccounts[msg.sender] == 1, "RecyclingMultiSurplusAuctionHouse/account-not-authorized");
        _;
    }

    // --- Data ---
    struct Bid {
        // Bid size (how many protocol tokens are offered per system coins sold)
        uint256 bidAmount;                                                            // [wad]
        // How many system coins are sold in an auction
        uint256 amountToSell;                                                         // [rad]
        // Who the high bidder is
        address highBidder;
        // When the latest bid expires and the auction can be settled
        uint48  bidExpiry;                                                            // [unix epoch time]
        // Hard deadline for the auction after which no more bids can be placed
        uint48  auctionDeadline;                                                      // [unix epoch time]
    }

    // Bid data for each separate auction
    mapping (uint256 => Bid) public bids;

    // The coin handled by this contract
    bytes32  public coinName;

    // SAFE database
    SAFEEngineLike public safeEngine;
    // Protocol token address
    TokenLike      public protocolToken;
    // Receiver of protocol tokens
    address        public protocolTokenBidReceiver;

    uint256  constant ONE = 1.00E18;                                                  // [wad]
    // Minimum bid increase compared to the last bid in order to take the new one in consideration
    uint256  public   bidIncrease = 1.05E18;                                          // [wad]
    // How long the auction lasts after a new bid is submitted
    uint48   public   bidDuration = 3 hours;                                          // [seconds]
    // Total length of the auction
    uint48   public   totalAuctionLength = 2 days;                                    // [seconds]
    // Number of auctions started up until now
    uint256  public   auctionsStarted = 0;
    // Whether the contract is settled or not
    uint256  public   contractEnabled;

    bytes32 public constant AUCTION_HOUSE_TYPE = bytes32("SURPLUS");
    bytes32 public constant SURPLUS_AUCTION_TYPE = bytes32("RECYCLING");

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event ModifyParameters(bytes32 parameter, uint256 data);
    event ModifyParameters(bytes32 parameter, address addr);
    event RestartAuction(uint256 id, uint256 auctionDeadline);
    event IncreaseBidSize(uint256 id, address highBidder, uint256 amountToBuy, uint256 bid, uint256 bidExpiry);
    event StartAuction(
        uint256 indexed id,
        uint256 auctionsStarted,
        uint256 amountToSell,
        uint256 initialBid,
        uint256 auctionDeadline
    );
    event SettleAuction(uint256 indexed id);
    event DisableContract();
    event TerminateAuctionPrematurely(uint256 indexed id, address sender, address highBidder, uint256 bidAmount);

    // --- Init ---
    constructor(bytes32 coinName_, address safeEngine_, address protocolToken_) public {
        authorizedAccounts[msg.sender] = 1;
        coinName = coinName_;

        safeEngine = SAFEEngineLike(safeEngine_);
        protocolToken = TokenLike(protocolToken_);

        contractEnabled = 1;

        emit AddAuthorization(msg.sender);
    }

    // --- Math ---
    function addUint48(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x, "RecyclingMultiSurplusAuctionHouse/add-uint48-overflow");
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "RecyclingMultiSurplusAuctionHouse/mul-overflow");
    }

    // --- Admin ---
    /**
     * @notice Modify uint256 parameters
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(bytes32 parameter, uint256 data) external isAuthorized {
        if (parameter == "bidIncrease") bidIncrease = data;
        else if (parameter == "bidDuration") bidDuration = uint48(data);
        else if (parameter == "totalAuctionLength") totalAuctionLength = uint48(data);
        else revert("RecyclingMultiSurplusAuctionHouse/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }
    /**
     * @notice Modify address parameters
     * @param parameter The name of the parameter modified
     * @param addr New address value
     */
    function modifyParameters(bytes32 parameter, address addr) external isAuthorized {
        require(addr != address(0), "RecyclingMultiSurplusAuctionHouse/invalid-address");
        if (parameter == "protocolTokenBidReceiver") protocolTokenBidReceiver = addr;
        else revert("RecyclingMultiSurplusAuctionHouse/modify-unrecognized-param");
        emit ModifyParameters(parameter, addr);
    }

    // --- Auction ---
    /**
     * @notice Start a new surplus auction
     * @param amountToSell Total amount of system coins to sell (rad)
     * @param initialBid Initial protocol token bid (wad)
     */
    function startAuction(uint256 amountToSell, uint256 initialBid) external isAuthorized returns (uint256 id) {
        require(contractEnabled == 1, "RecyclingMultiSurplusAuctionHouse/contract-not-enabled");
        require(auctionsStarted < uint256(-1), "RecyclingMultiSurplusAuctionHouse/overflow");
        require(protocolTokenBidReceiver != address(0), "RecyclingMultiSurplusAuctionHouse/null-prot-token-receiver");
        id = ++auctionsStarted;

        bids[id].bidAmount = initialBid;
        bids[id].amountToSell = amountToSell;
        bids[id].highBidder = msg.sender;
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);

        safeEngine.transferInternalCoins(coinName, msg.sender, address(this), amountToSell);

        emit StartAuction(id, auctionsStarted, amountToSell, initialBid, bids[id].auctionDeadline);
    }
    /**
     * @notice Restart an auction if no bids were submitted for it
     * @param id ID of the auction to restart
     */
    function restartAuction(uint256 id) external {
        require(bids[id].auctionDeadline < now, "RecyclingMultiSurplusAuctionHouse/not-finished");
        require(bids[id].bidExpiry == 0, "RecyclingMultiSurplusAuctionHouse/bid-already-placed");
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);
        emit RestartAuction(id, bids[id].auctionDeadline);
    }
    /**
     * @notice Submit a higher protocol token bid for the same amount of system coins
     * @param id ID of the auction you want to submit the bid for
     * @param amountToBuy Amount of system coins to buy (rad)
     * @param bid New bid submitted (wad)
     */
    function increaseBidSize(uint256 id, uint256 amountToBuy, uint256 bid) external {
        require(contractEnabled == 1, "RecyclingMultiSurplusAuctionHouse/contract-not-enabled");
        require(bids[id].highBidder != address(0), "RecyclingMultiSurplusAuctionHouse/high-bidder-not-set");
        require(bids[id].bidExpiry > now || bids[id].bidExpiry == 0, "RecyclingMultiSurplusAuctionHouse/bid-already-expired");
        require(bids[id].auctionDeadline > now, "RecyclingMultiSurplusAuctionHouse/auction-already-expired");

        require(amountToBuy == bids[id].amountToSell, "RecyclingMultiSurplusAuctionHouse/amounts-not-matching");
        require(bid > bids[id].bidAmount, "RecyclingMultiSurplusAuctionHouse/bid-not-higher");
        require(multiply(bid, ONE) >= multiply(bidIncrease, bids[id].bidAmount), "RecyclingMultiSurplusAuctionHouse/insufficient-increase");

        if (msg.sender != bids[id].highBidder) {
            protocolToken.move(msg.sender, bids[id].highBidder, bids[id].bidAmount);
            bids[id].highBidder = msg.sender;
        }
        protocolToken.move(msg.sender, address(this), bid - bids[id].bidAmount);

        bids[id].bidAmount = bid;
        bids[id].bidExpiry = addUint48(uint48(now), bidDuration);

        emit IncreaseBidSize(id, msg.sender, amountToBuy, bid, bids[id].bidExpiry);
    }
    /**
     * @notice Settle/finish an auction
     * @param id ID of the auction to settle
     */
    function settleAuction(uint256 id) external {
        require(contractEnabled == 1, "RecyclingMultiSurplusAuctionHouse/contract-not-enabled");
        require(bids[id].bidExpiry != 0 && (bids[id].bidExpiry < now || bids[id].auctionDeadline < now), "RecyclingMultiSurplusAuctionHouse/not-finished");
        safeEngine.transferInternalCoins(coinName, address(this), bids[id].highBidder, bids[id].amountToSell);
        protocolToken.move(address(this), protocolTokenBidReceiver, bids[id].bidAmount);
        delete bids[id];
        emit SettleAuction(id);
    }
    /**
    * @notice Disable the auction house
    **/
    function disableContract() external isAuthorized {
        contractEnabled = 0;
        safeEngine.transferInternalCoins(coinName, address(this), msg.sender, safeEngine.coinBalance(coinName, address(this)));
        emit DisableContract();
    }
    /**
     * @notice Terminate an auction prematurely.
     * @param id ID of the auction to settle/terminate
     */
    function terminateAuctionPrematurely(uint256 id) external {
        require(contractEnabled == 0, "RecyclingMultiSurplusAuctionHouse/contract-still-enabled");
        require(bids[id].highBidder != address(0), "RecyclingMultiSurplusAuctionHouse/high-bidder-not-set");
        protocolToken.move(address(this), bids[id].highBidder, bids[id].bidAmount);
        emit TerminateAuctionPrematurely(id, msg.sender, bids[id].highBidder, bids[id].bidAmount);
        delete bids[id];
    }
}
