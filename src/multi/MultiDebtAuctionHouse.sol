/// MultiDebtAuctionHouse.sol

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
    function coinBalance(bytes32,address) virtual public view returns (uint256);
    function debtBalance(bytes32,address) virtual public view returns (uint256);
    function transferInternalCoins(bytes32,address,address,uint256) virtual external;
    function createUnbackedDebt(bytes32,address,address,uint256) virtual external;
}
abstract contract TokenLike {
    function mint(address,uint256) virtual external;
}
abstract contract AccountingEngineLike {
    function unqueuedDebt(bytes32) virtual public view returns (uint256);
    function settleDebt(bytes32, uint256) virtual public;
    function coinEnabled(bytes32) virtual public view returns (uint256);
    function coinInitialized(bytes32) virtual public view returns (uint256);
}

/*
   This thing creates protocol tokens on demand in return for system coins
*/

contract MultiDebtAuctionHouse {
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
        require(authorizedAccounts[msg.sender] == 1, "MultiDebtAuctionHouse/account-not-authorized");
        _;
    }

    // --- Data ---
    struct Bid {
        // Bid size
        uint256 bidAmount;                                                        // [rad]
        // How many protocol tokens are sold in an auction
        uint256 amountToSell;                                                     // [wad]
        // Who the high bidder is
        address highBidder;
        // When the latest bid expires and the auction can be settled
        uint48  bidExpiry;                                                        // [unix epoch time]
        // Hard deadline for the auction after which no more bids can be placed
        uint48  auctionDeadline;                                                  // [unix epoch time]
    }

    // Bid data for each separate auction
    mapping (uint256 => Bid) public bids;

    // The coin handled by this contract
    bytes32  public coinName;

    // SAFE database
    SAFEEngineLike public safeEngine;
    // Protocol token address
    TokenLike public protocolToken;
    // Accounting engine
    AccountingEngineLike public accountingEngine;

    uint256  constant ONE = 1.00E18;                                              // [wad]
    // Minimum bid increase compared to the last bid in order to take the new one in consideration
    uint256  public   bidDecrease = 1.05E18;                                      // [wad]
    // Increase in protocol tokens sold in case an auction is restarted
    uint256  public   amountSoldIncrease = 1.50E18;                               // [wad]
    // How long the auction lasts after a new bid is submitted
    uint48   public   bidDuration = 3 hours;                                      // [seconds]
    // Total length of the auction
    uint48   public   totalAuctionLength = 2 days;                                // [seconds]
    // Number of auctions started up until now
    uint256  public   auctionsStarted = 0;
    // Accumulator for all debt auctions currently not settled
    uint256  public   activeDebtAuctions;
    // Total debt being currently auctioned
    uint256  public   totalOnAuctionDebt;                                         // [rad]
    // Amount of protocol tokens to be minted post-auction
    uint256  public   initialDebtAuctionMintedTokens;                             // [wad]
    // Amount of debt sold in one debt auction (initial coin bid for initialDebtAuctionMintedTokens protocol tokens)
    uint256  public   debtAuctionBidSize;                                         // [rad]
    // Flag that indicates whether this contract is enabled or not
    uint256  public   contractEnabled;

    bytes32 public constant AUCTION_HOUSE_TYPE = bytes32("DEBT");

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event StartAuction(
      uint256 indexed id,
      uint256 auctionsStarted,
      uint256 amountToSell,
      uint256 initialBid,
      uint256 indexed auctionDeadline,
      uint256 activeDebtAuctions
    );
    event ModifyParameters(bytes32 parameter, uint256 data);
    event ModifyParameters(bytes32 parameter, address data);
    event RestartAuction(uint256 indexed id, uint256 auctionDeadline);
    event DecreaseSoldAmount(uint256 indexed id, address highBidder, uint256 amountToBuy, uint256 bid, uint256 bidExpiry);
    event SettleAuction(uint256 indexed id, uint256 activeDebtAuctions);
    event TerminateAuctionPrematurely(uint256 indexed id, address sender, address highBidder, uint256 bidAmount, uint256 activeDebtAuctions);
    event DisableContract(address sender);

    // --- Init ---
    constructor(bytes32 coinName_, address safeEngine_, address protocolToken_, address accountingEngine_) public {
        authorizedAccounts[msg.sender] = 1;

        coinName = coinName_;

        safeEngine = SAFEEngineLike(safeEngine_);
        protocolToken = TokenLike(protocolToken_);
        accountingEngine = AccountingEngineLike(accountingEngine_);

        contractEnabled = 1;

        emit AddAuthorization(msg.sender);
    }

    // --- Boolean Logic ---
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- Math ---
    function addUint48(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x, "MultiDebtAuctionHouse/add-uint48-overflow");
    }
    function addUint256(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "MultiDebtAuctionHouse/add-uint256-overflow");
    }
    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "MultiDebtAuctionHouse/sub-underflow");
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "MultiDebtAuctionHouse/mul-overflow");
    }
    function minimum(uint256 x, uint256 y) internal pure returns (uint256 z) {
        if (x > y) { z = y; } else { z = x; }
    }

    // --- Admin ---
    /**
     * @notice Modify an uint256 parameter
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(bytes32 parameter, uint256 data) external isAuthorized {
        if (parameter == "bidDecrease") bidDecrease = data;
        else if (parameter == "amountSoldIncrease") amountSoldIncrease = data;
        else if (parameter == "bidDuration") bidDuration = uint48(data);
        else if (parameter == "totalAuctionLength") totalAuctionLength = uint48(data);
        else if (parameter == "debtAuctionBidSize") debtAuctionBidSize = data;
        else if (parameter == "initialDebtAuctionMintedTokens") initialDebtAuctionMintedTokens = data;
        else revert("MultiDebtAuctionHouse/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }
    /**
     * @notice Modify an address parameter
     * @param parameter The name of the oracle contract modified
     * @param addr New contract address
     */
    function modifyParameters(bytes32 parameter, address addr) external isAuthorized {
        require(contractEnabled == 1, "MultiDebtAuctionHouse/contract-not-enabled");
        if (parameter == "protocolToken") protocolToken = TokenLike(addr);
        else revert("MultiDebtAuctionHouse/modify-unrecognized-param");
        emit ModifyParameters(parameter, addr);
    }

    // --- Auction ---
    /**
     * @notice Start a new debt auction
     */
    function startAuction() external isAuthorized returns (uint256 id) {
        require(contractEnabled == 1, "MultiDebtAuctionHouse/contract-not-enabled");
        require(
          both(accountingEngine.coinEnabled(coinName) == 1, accountingEngine.coinInitialized(coinName) == 1),
          "MultiDebtAuctionHouse/coin-not-enabled-and-initialized"
        );
        require(both(debtAuctionBidSize > 0, initialDebtAuctionMintedTokens > 0), "MultiDebtAuctionHouse/null-auction-params");
        require(auctionsStarted < uint256(-1), "MultiDebtAuctionHouse/overflow");
        require(debtAuctionBidSize <= subtract(accountingEngine.unqueuedDebt(coinName), totalOnAuctionDebt), "MultiDebtAuctionHouse/insufficient-debt");

        accountingEngine.settleDebt(coinName, safeEngine.coinBalance(coinName, address(accountingEngine)));
        require(safeEngine.coinBalance(coinName, address(accountingEngine)) == 0, "MultiDebtAuctionHouse/accounting-surplus-not-zero");

        id                       = ++auctionsStarted;
        totalOnAuctionDebt       = addUint256(totalOnAuctionDebt, debtAuctionBidSize);

        bids[id].bidAmount       = debtAuctionBidSize;
        bids[id].amountToSell    = initialDebtAuctionMintedTokens;
        bids[id].highBidder      = address(accountingEngine);
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);

        activeDebtAuctions       = addUint256(activeDebtAuctions, 1);

        emit StartAuction(
          id,
          auctionsStarted,
          initialDebtAuctionMintedTokens,
          debtAuctionBidSize,
          bids[id].auctionDeadline,
          activeDebtAuctions
        );
    }
    /**
     * @notice Restart an auction if no bids were submitted for it
     * @param id ID of the auction to restart
     */
    function restartAuction(uint256 id) external {
        require(id <= auctionsStarted, "MultiDebtAuctionHouse/auction-never-started");
        require(bids[id].auctionDeadline < now, "MultiDebtAuctionHouse/not-finished");
        require(bids[id].bidExpiry == 0, "MultiDebtAuctionHouse/bid-already-placed");
        bids[id].amountToSell = multiply(amountSoldIncrease, bids[id].amountToSell) / ONE;
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);
        emit RestartAuction(id, bids[id].auctionDeadline);
    }
    /**
     * @notice Decrease the protocol token amount you're willing to receive in
     *         exchange for providing the same amount of system coins being raised by the auction
     * @param id ID of the auction for which you want to submit a new bid
     * @param amountToBuy Amount of protocol tokens to buy (must be smaller than the previous proposed amount) (wad)
     * @param bid New system coin bid (must always equal the total amount raised by the auction) (rad)
     */
    function decreaseSoldAmount(uint256 id, uint256 amountToBuy, uint256 bid) external {
        require(contractEnabled == 1, "MultiDebtAuctionHouse/contract-not-enabled");
        require(bids[id].highBidder != address(0), "MultiDebtAuctionHouse/high-bidder-not-set");
        require(bids[id].bidExpiry > now || bids[id].bidExpiry == 0, "MultiDebtAuctionHouse/bid-already-expired");
        require(bids[id].auctionDeadline > now, "MultiDebtAuctionHouse/auction-already-expired");

        require(bid == bids[id].bidAmount, "MultiDebtAuctionHouse/not-matching-bid");
        require(amountToBuy <  bids[id].amountToSell, "MultiDebtAuctionHouse/amount-bought-not-lower");
        require(multiply(bidDecrease, amountToBuy) <= multiply(bids[id].amountToSell, ONE), "MultiDebtAuctionHouse/insufficient-decrease");

        safeEngine.transferInternalCoins(coinName, msg.sender, address(accountingEngine), bid);

        // on first bid submitted, clear as much debt as possible
        if (bids[id].bidExpiry == 0) {
            accountingEngine.settleDebt(
              coinName,
              minimum(safeEngine.coinBalance(coinName, address(accountingEngine)), safeEngine.debtBalance(coinName, address(accountingEngine)))
            );
            totalOnAuctionDebt = subtract(totalOnAuctionDebt, bid);
        }

        bids[id].highBidder   = msg.sender;
        bids[id].amountToSell = amountToBuy;
        bids[id].bidExpiry    = addUint48(uint48(now), bidDuration);

        emit DecreaseSoldAmount(id, msg.sender, amountToBuy, bid, bids[id].bidExpiry);
    }
    /**
     * @notice Settle/finish an auction
     * @param id ID of the auction to settle
     */
    function settleAuction(uint256 id) external {
        require(contractEnabled == 1, "MultiDebtAuctionHouse/not-live");
        require(bids[id].bidExpiry != 0 && (bids[id].bidExpiry < now || bids[id].auctionDeadline < now), "MultiDebtAuctionHouse/not-finished");
        protocolToken.mint(bids[id].highBidder, bids[id].amountToSell);
        activeDebtAuctions = subtract(activeDebtAuctions, 1);
        delete bids[id];
        emit SettleAuction(id, activeDebtAuctions);
    }

    // --- Shutdown ---
    /**
    * @notice Disable the auction house
    * @param engine New accounting engine
    */
    function disableContract(address engine) external isAuthorized {
        contractEnabled    = 0;
        accountingEngine   = AccountingEngineLike(engine);
        activeDebtAuctions = 0;
        totalOnAuctionDebt = 0;
        emit DisableContract(msg.sender);
    }
    /**
     * @notice Terminate an auction prematurely
     * @param id ID of the auction to terminate
     */
    function terminateAuctionPrematurely(uint256 id) external {
        require(contractEnabled == 0, "MultiDebtAuctionHouse/contract-still-enabled");
        require(bids[id].highBidder != address(0), "MultiDebtAuctionHouse/high-bidder-not-set");
        safeEngine.createUnbackedDebt(coinName, address(accountingEngine), bids[id].highBidder, bids[id].bidAmount);
        emit TerminateAuctionPrematurely(id, msg.sender, bids[id].highBidder, bids[id].bidAmount, activeDebtAuctions);
        delete bids[id];
    }
}
