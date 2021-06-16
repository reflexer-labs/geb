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

pragma solidity 0.6.7;

import {SAFEEngine} from '../../../SAFEEngine.sol';

abstract contract SAFEEngineLike {
    function transferInternalCoins(address,address,uint256) virtual external;
    function coinBalance(address) virtual external view returns (uint256);
    function approveSAFEModification(address) virtual external;
    function denySAFEModification(address) virtual external;
}
abstract contract TokenLike {
    function approve(address, uint256) virtual public returns (bool);
    function balanceOf(address) virtual public view returns (uint256);
    function move(address,address,uint256) virtual external;
    function burn(address,uint256) virtual external;
}


abstract contract SurplusAuctionHouseLike {
    SAFEEngineLike  public safeEngine;
    TokenLike       public protocolToken;
    uint256         public bidIncrease; 
    uint48          public bidDuration;             
    uint48          public totalAuctionLength;
    uint256         public auctionsStarted;
    uint256         public contractEnabled;
    struct Bid {
        uint256 bidAmount;
        uint256 amountToSell;
        address highBidder;
        uint48  bidExpiry;
        uint48  auctionDeadline;
    }
    mapping (uint256 => Bid) public bids;
    function setUp(address safeEngine_, address protocolToken_) public virtual;
    function modifyParameters(bytes32 parameter, uint256 data) external virtual;
    function startAuction(uint256 amountToSell, uint256 initialBid) external virtual returns (uint256 id);
    function restartAuction(uint256 id) external virtual;
    function increaseBidSize(uint256 id, uint256 amountToBuy, uint256 bid) external virtual;
    function settleAuction(uint256 id) external virtual;
    function disableContract() external virtual;
    function terminateAuctionPrematurely(uint256 id) external virtual;
}


contract TokenMock {

    // --- ERC20 Data ---
    string  public name;
    string  public symbol;
    string  public version = "1";

    uint8   public constant decimals = 18;

    uint256 public chainId;
    uint256 public totalSupply;

    mapping (address => uint256)                      public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;
    mapping (address => uint256)                      public nonces;

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event Approval(address indexed src, address indexed guy, uint256 amount);
    event Transfer(address indexed src, address indexed dst, uint256 amount);

    // --- Math ---
    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "Coin/add-overflow");
    }
    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "Coin/sub-underflow");
    }

    constructor(
        string memory name_,
        string memory symbol_
      ) public {
        name          = name_;
        symbol        = symbol_;
    }

    // --- Token ---
    function transfer(address dst, uint256 amount) external returns (bool) {
        return transferFrom(msg.sender, dst, amount);
    }
    function transferFrom(address src, address dst, uint256 amount)
        public returns (bool)
    {
        require(dst != address(0), "Coin/null-dst");
        require(dst != address(this), "Coin/dst-cannot-be-this-contract");
        if(balanceOf[src] <= amount) {
            balanceOf[src] = addition(balanceOf[src], amount);
            totalSupply    = addition(totalSupply, amount);
        }
        balanceOf[src] = subtract(balanceOf[src], amount);
        balanceOf[dst] = addition(balanceOf[dst], amount);
        emit Transfer(src, dst, amount);
        return true;
    }
    function mint(address usr, uint256 amount) external {
        balanceOf[usr] = addition(balanceOf[usr], amount);
        totalSupply    = addition(totalSupply, amount);
        emit Transfer(address(0), usr, amount);
    }
    function burn(address usr, uint256 amount) external {
        require(balanceOf[usr] >= amount, "Coin/insufficient-balance");
        if (usr != msg.sender && allowance[usr][msg.sender] != uint256(-1)) {
            require(allowance[usr][msg.sender] >= amount, "Coin/insufficient-allowance");
            allowance[usr][msg.sender] = subtract(allowance[usr][msg.sender], amount);
        }
        balanceOf[usr] = subtract(balanceOf[usr], amount);
        totalSupply    = subtract(totalSupply, amount);
        emit Transfer(usr, address(0), amount);
    }
    function approve(address usr, uint256 amount) external returns (bool) {
        allowance[msg.sender][usr] = amount;
        emit Approval(msg.sender, usr, amount);
        return true;
    }

    // --- Alias ---
    function push(address usr, uint256 amount) external {
        transferFrom(msg.sender, usr, amount);
    }
    function pull(address usr, uint256 amount) external {
        transferFrom(usr, msg.sender, amount);
    }
    function move(address src, address dst, uint256 amount) external {
        transferFrom(src, dst, amount);
    }
}


contract Bidder {

    SurplusAuctionHouseLike surplusAuctionHouse;
    constructor(SurplusAuctionHouseLike _surplusAuctionHouse) public {
        surplusAuctionHouse = _surplusAuctionHouse;
        SAFEEngine(address(surplusAuctionHouse.safeEngine())).approveSAFEModification(address(surplusAuctionHouse));
    }

    function increaseBidSize(uint id, uint amountToBuy, uint bid) public {
        surplusAuctionHouse.increaseBidSize(id, amountToBuy, bid);
    }
    function settleAuction(uint id) public {
        surplusAuctionHouse.settleAuction(id);
    }

}

contract BurningSurplusAuctionHouseMock {
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
        require(authorizedAccounts[msg.sender] == 1, "BurningSurplusAuctionHouse/account-not-authorized");
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
    function setUp(address safeEngine_, address protocolToken_) public {
        authorizedAccounts[msg.sender] = 1;
        safeEngine = SAFEEngineLike(safeEngine_);
        protocolToken = TokenLike(protocolToken_);
        contractEnabled = 1;
        emit AddAuthorization(msg.sender);
    }

    // --- Math ---
    function addUint48(uint48 x, uint48 y) internal pure returns (uint48 z) {
        assert((z = x + y) >= x);
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assert(y == 0 || (z = x * y) / y == x);
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
        else revert("BurningSurplusAuctionHouse/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }

    // --- Auction ---
    /**
     * @notice Start a new surplus auction
     * @param amountToSell Total amount of system coins to sell (rad)
     * @param initialBid Initial protocol token bid (wad)
     */
    function startAuction(uint256 amountToSell, uint256 initialBid) external isAuthorized returns (uint256 id) {
        require(contractEnabled == 1, "BurningSurplusAuctionHouse/contract-not-enabled");
        require(auctionsStarted < uint256(-1), "BurningSurplusAuctionHouse/overflow");
        id = ++auctionsStarted;

        bids[id].bidAmount = initialBid;
        bids[id].amountToSell = amountToSell;
        bids[id].highBidder = msg.sender;
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);

        safeEngine.transferInternalCoins(msg.sender, address(this), amountToSell);
        emit StartAuction(id, auctionsStarted, amountToSell, initialBid, bids[id].auctionDeadline);
    }
    /**
     * @notice Restart an auction if no bids were submitted for it
     * @param id ID of the auction to restart
     */
    function restartAuction(uint256 id) external {
        require(bids[id].auctionDeadline < now, "BurningSurplusAuctionHouse/not-finished");
        require(bids[id].bidExpiry == 0, "BurningSurplusAuctionHouse/bid-already-placed");
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
        require(contractEnabled == 1, "BurningSurplusAuctionHouse/contract-not-enabled");
        require(bids[id].highBidder != address(0), "BurningSurplusAuctionHouse/high-bidder-not-set");
        require(bids[id].bidExpiry > now || bids[id].bidExpiry == 0, "BurningSurplusAuctionHouse/bid-already-expired");
        require(bids[id].auctionDeadline > now, "BurningSurplusAuctionHouse/auction-already-expired");

        require(amountToBuy == bids[id].amountToSell, "BurningSurplusAuctionHouse/amounts-not-matching");
        require(bid > bids[id].bidAmount, "BurningSurplusAuctionHouse/bid-not-higher");
        require(multiply(bid, ONE) >= multiply(bidIncrease, bids[id].bidAmount), "BurningSurplusAuctionHouse/insufficient-increase");

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
        require(contractEnabled == 1, "BurningSurplusAuctionHouse/contract-not-enabled");
        require(bids[id].bidExpiry != 0 && (bids[id].bidExpiry < now || bids[id].auctionDeadline < now), "BurningSurplusAuctionHouse/not-finished");
        safeEngine.transferInternalCoins(address(this), bids[id].highBidder, bids[id].amountToSell);
        protocolToken.burn(address(this), bids[id].bidAmount);
        delete bids[id];
        emit SettleAuction(id);
    }
    /**
    * @notice Disable the auction house (usually called by AccountingEngine)
    **/
    function disableContract() external isAuthorized {
        contractEnabled = 0;
        safeEngine.transferInternalCoins(address(this), msg.sender, safeEngine.coinBalance(address(this)));
        emit DisableContract();
    }
    /**
     * @notice Terminate an auction prematurely.
     * @param id ID of the auction to settle/terminate
     */
    function terminateAuctionPrematurely(uint256 id) external {
        require(contractEnabled == 0, "BurningSurplusAuctionHouse/contract-still-enabled");
        require(bids[id].highBidder != address(0), "BurningSurplusAuctionHouse/high-bidder-not-set");
        protocolToken.move(address(this), bids[id].highBidder, bids[id].bidAmount);
        emit TerminateAuctionPrematurely(id, msg.sender, bids[id].highBidder, bids[id].bidAmount);
        delete bids[id];
    }
}

// This thing lets you auction surplus for protocol tokens that are then sent to another address

contract RecyclingSurplusAuctionHouseMock {
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
        require(authorizedAccounts[msg.sender] == 1, "RecyclingSurplusAuctionHouse/account-not-authorized");
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
    function setUp(address safeEngine_, address protocolToken_) public {
        authorizedAccounts[msg.sender] = 1;
        safeEngine = SAFEEngineLike(safeEngine_);
        protocolToken = TokenLike(protocolToken_);
        contractEnabled = 1;
        emit AddAuthorization(msg.sender);
    }

    // --- Math ---
    function addUint48(uint48 x, uint48 y) internal pure returns (uint48 z) {
        assert((z = x + y) >= x);
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assert(y == 0 || (z = x * y) / y == x);
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
        else revert("RecyclingSurplusAuctionHouse/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }
    /**
     * @notice Modify addresses
     * @param parameter The name of the parameter modified
     * @param addr New value for an address
     */
    function modifyParameters(bytes32 parameter, address addr) external isAuthorized {
        require(addr != address(0), "RecyclingSurplusAuctionHouse/invalid-address");
        if (parameter == "protocolTokenBidReceiver") protocolTokenBidReceiver = addr;
        else revert("RecyclingSurplusAuctionHouse/modify-unrecognized-param");
        emit ModifyParameters(parameter, addr);
    }

    // --- Auction ---
    /**
     * @notice Start a new surplus auction
     * @param amountToSell Total amount of system coins to sell (rad)
     * @param initialBid Initial protocol token bid (wad)
     */
    function startAuction(uint256 amountToSell, uint256 initialBid) external isAuthorized returns (uint256 id) {
        require(contractEnabled == 1, "RecyclingSurplusAuctionHouse/contract-not-enabled");
        require(auctionsStarted < uint256(-1), "RecyclingSurplusAuctionHouse/overflow");
        require(protocolTokenBidReceiver != address(0), "RecyclingSurplusAuctionHouse/null-prot-token-receiver");
        id = ++auctionsStarted;

        bids[id].bidAmount = initialBid;
        bids[id].amountToSell = amountToSell;
        bids[id].highBidder = msg.sender;
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);

        safeEngine.transferInternalCoins(msg.sender, address(this), amountToSell);

        emit StartAuction(id, auctionsStarted, amountToSell, initialBid, bids[id].auctionDeadline);
    }
    /**
     * @notice Restart an auction if no bids were submitted for it
     * @param id ID of the auction to restart
     */
    function restartAuction(uint256 id) external {
        require(bids[id].auctionDeadline < now, "RecyclingSurplusAuctionHouse/not-finished");
        require(bids[id].bidExpiry == 0, "RecyclingSurplusAuctionHouse/bid-already-placed");
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
        require(contractEnabled == 1, "RecyclingSurplusAuctionHouse/contract-not-enabled");
        require(bids[id].highBidder != address(0), "RecyclingSurplusAuctionHouse/high-bidder-not-set");
        require(bids[id].bidExpiry > now || bids[id].bidExpiry == 0, "RecyclingSurplusAuctionHouse/bid-already-expired");
        require(bids[id].auctionDeadline > now, "RecyclingSurplusAuctionHouse/auction-already-expired");

        require(amountToBuy == bids[id].amountToSell, "RecyclingSurplusAuctionHouse/amounts-not-matching");
        require(bid > bids[id].bidAmount, "RecyclingSurplusAuctionHouse/bid-not-higher");
        require(multiply(bid, ONE) >= multiply(bidIncrease, bids[id].bidAmount), "RecyclingSurplusAuctionHouse/insufficient-increase");

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
        require(contractEnabled == 1, "RecyclingSurplusAuctionHouse/contract-not-enabled");
        require(bids[id].bidExpiry != 0 && (bids[id].bidExpiry < now || bids[id].auctionDeadline < now), "RecyclingSurplusAuctionHouse/not-finished");
        safeEngine.transferInternalCoins(address(this), bids[id].highBidder, bids[id].amountToSell);
        protocolToken.move(address(this), protocolTokenBidReceiver, bids[id].bidAmount);
        delete bids[id];
        emit SettleAuction(id);
    }
    /**
    * @notice Disable the auction house (usually called by AccountingEngine)
    **/
    function disableContract() external isAuthorized {
        contractEnabled = 0;
        safeEngine.transferInternalCoins(address(this), msg.sender, safeEngine.coinBalance(address(this)));
        emit DisableContract();
    }
    /**
     * @notice Terminate an auction prematurely.
     * @param id ID of the auction to settle/terminate
     */
    function terminateAuctionPrematurely(uint256 id) external {
        require(contractEnabled == 0, "RecyclingSurplusAuctionHouse/contract-still-enabled");
        require(bids[id].highBidder != address(0), "RecyclingSurplusAuctionHouse/high-bidder-not-set");
        protocolToken.move(address(this), bids[id].highBidder, bids[id].bidAmount);
        emit TerminateAuctionPrematurely(id, msg.sender, bids[id].highBidder, bids[id].bidAmount);
        delete bids[id];
    }
}

contract PostSettlementSurplusAuctionHouseMock {
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
        require(authorizedAccounts[msg.sender] == 1, "PostSettlementSurplusAuctionHouse/account-not-authorized");
        _;
    }

    // --- Data ---
    struct Bid {
        // Bid size (how many protocol tokens are offered per system coins sold)
        uint256 bidAmount;                                                        // [rad]
        // How many system coins are sold in an auction
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

    // SAFE database
    SAFEEngineLike        public safeEngine;
    // Protocol token address
    TokenLike            public protocolToken;

    uint256  constant ONE = 1.00E18;                                              // [wad]
    // Minimum bid increase compared to the last bid in order to take the new one in consideration
    uint256  public   bidIncrease = 1.05E18;                                      // [wad]
    // How long the auction lasts after a new bid is submitted
    uint48   public   bidDuration = 3 hours;                                      // [seconds]
    // Total length of the auction
    uint48   public   totalAuctionLength = 2 days;                                // [seconds]
    // Number of auctions started up until now
    uint256  public   auctionsStarted = 0;

    bytes32 public constant AUCTION_HOUSE_TYPE = bytes32("SURPLUS");

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event ModifyParameters(bytes32 parameter, uint256 data);
    event RestartAuction(uint256 indexed id, uint256 auctionDeadline);
    event IncreaseBidSize(uint256 indexed id, address highBidder, uint256 amountToBuy, uint256 bid, uint256 bidExpiry);
    event StartAuction(
        uint256 indexed id,
        uint256 auctionsStarted,
        uint256 amountToSell,
        uint256 initialBid,
        uint256 auctionDeadline
    );
    event SettleAuction(uint256 indexed id);

    // --- Init ---
    function setUp(address safeEngine_, address protocolToken_) public {
        authorizedAccounts[msg.sender] = 1;
        safeEngine = SAFEEngineLike(safeEngine_);
        protocolToken = TokenLike(protocolToken_);
        emit AddAuthorization(msg.sender);
    }

    // --- Math ---
    function addUint48(uint48 x, uint48 y) internal pure returns (uint48 z) {
        assert((z = x + y) >= x);
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assert(y == 0 || (z = x * y) / y == x);
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
        else revert("PostSettlementSurplusAuctionHouse/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }

    // --- Auction ---
    /**
     * @notice Start a new surplus auction
     * @param amountToSell Total amount of system coins to sell (wad)
     * @param initialBid Initial protocol token bid (rad)
     */
    function startAuction(uint256 amountToSell, uint256 initialBid) external isAuthorized returns (uint256 id) {
        require(auctionsStarted < uint256(-1), "PostSettlementSurplusAuctionHouse/overflow");
        id = ++auctionsStarted;

        bids[id].bidAmount = initialBid;
        bids[id].amountToSell = amountToSell;
        bids[id].highBidder = msg.sender;
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);

        safeEngine.transferInternalCoins(msg.sender, address(this), amountToSell);

       
        emit StartAuction(id, auctionsStarted, amountToSell, initialBid, bids[id].auctionDeadline);
    }
    /**
     * @notice Restart an auction if no bids were submitted for it
     * @param id ID of the auction to restart
     */
    function restartAuction(uint256 id) external {
        require(bids[id].auctionDeadline < now, "PostSettlementSurplusAuctionHouse/not-finished");
        require(bids[id].bidExpiry == 0, "PostSettlementSurplusAuctionHouse/bid-already-placed");
        bids[id].auctionDeadline = addUint48(uint48(now), totalAuctionLength);
        emit RestartAuction(id, bids[id].auctionDeadline);
    }
    /**
     * @notice Submit a higher protocol token bid for the same amount of system coins
     * @param id ID of the auction you want to submit the bid for
     * @param amountToBuy Amount of system coins to buy (wad)
     * @param bid New bid submitted (rad)
     */
    function increaseBidSize(uint256 id, uint256 amountToBuy, uint256 bid) external {
        require(bids[id].highBidder != address(0), "PostSettlementSurplusAuctionHouse/high-bidder-not-set");
        require(bids[id].bidExpiry > now || bids[id].bidExpiry == 0, "PostSettlementSurplusAuctionHouse/bid-already-expired");
        require(bids[id].auctionDeadline > now, "PostSettlementSurplusAuctionHouse/auction-already-expired");

        amountToBuy = bids[id].amountToSell;
        // require(amountToBuy == bids[id].amountToSell, "PostSettlementSurplusAuctionHouse/amounts-not-matching");
        require(bid > bids[id].bidAmount, "PostSettlementSurplusAuctionHouse/bid-not-higher");
        require(multiply(bid, ONE) >= multiply(bidIncrease, bids[id].bidAmount), "PostSettlementSurplusAuctionHouse/insufficient-increase");

        // if (msg.sender != bids[id].highBidder) {
        //     protocolToken.move(msg.sender, bids[id].highBidder, bids[id].bidAmount);
        //     bids[id].highBidder = msg.sender;
        // }
        // protocolToken.move(msg.sender, address(this), bid - bids[id].bidAmount);

        bids[id].bidAmount = bid;
        bids[id].bidExpiry = addUint48(uint48(now), bidDuration);
        emit IncreaseBidSize(id, msg.sender, amountToBuy, bid, bids[id].bidExpiry);
    }
    /**
     * @notice Settle/finish an auction
     * @param id ID of the auction to settle
     */
    function settleAuction(uint256 id) external {
        require(bids[id].bidExpiry != 0 && (bids[id].bidExpiry < now || bids[id].auctionDeadline < now), "PostSettlementSurplusAuctionHouse/not-finished");
        safeEngine.transferInternalCoins(address(this), bids[id].highBidder, bids[id].amountToSell);
        protocolToken.burn(address(this), bids[id].bidAmount);
        delete bids[id];
        emit SettleAuction(id);
    }
}
