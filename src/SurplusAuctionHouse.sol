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
contract CoinJoinLike {
    function join(address, uint) external;
    function exit(address, uint) external;
}
contract TokenLike {
    function approve(address, uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
    function move(address,address,uint) external;
    function burn(address,uint) external;
}
contract DexLike {
    function INPUT() public view returns (bytes32);
    function tkntkn(bytes32,uint256,address,address[] calldata) external returns (uint256);
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

    CDPEngineLike public cdpEngine;
    TokenLike     public protocolToken;

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
        require(bids[id].bidExpiry != 0 && (bids[id].bidExpiry < now || bids[id].auctionDeadline < now), "SurplusAuctionHouseOne/not-finished");
        cdpEngine.transferInternalCoins(address(this), bids[id].highBidder, bids[id].amountToSell);
        protocolToken.burn(address(this), bids[id].bidAmount);
        delete bids[id];
    }

    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
    }
}

/*
  This thing automatically buys protocol tokens from DEXs and burns them
*/

contract SurplusAuctionHouseTwo is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "SurplusAuctionHouseTwo/account-not-authorized");
        _;
    }

    CDPEngineLike public cdpEngine;
    CoinJoinLike  public coinJoin;
    TokenLike     public systemCoin;
    TokenLike     public protocolToken;
    DexLike       public dex;
    address       public leftoverReceiver;
    address       public settlementSurplusAuctioner;

    address[]     public swapPath;

    uint8         public mutex;
    uint256       public auctionsStarted;
    uint256       public contractEnabled;

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
        swapPath.push(address(0));
        swapPath.push(protocolToken_);
        contractEnabled = 1;
    }

    // --- Math ---
    uint256 constant RAD = 10 ** 45;
    uint256 constant RAY = 10 ** 27;

    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function div(uint x, uint y) internal pure returns (uint z) {
        z = x / y;
    }

    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- Admin ---
    function modifyParameters(bytes32 parameter, address addr) external emitLog isAuthorized {
        require(contractEnabled == 1, "SurplusAuctionHouseTwo/contract-not-enabled");
        if (parameter == "systemCoin") {
          systemCoin = TokenLike(addr);
          swapPath[0] = addr;
        }
        else if (parameter == "protocolToken") {
          protocolToken = TokenLike(addr);
          swapPath[1] = addr;
        }
        else if (parameter == "coinJoin") {
          if (address(systemCoin) != address(0)) {
            systemCoin.approve(address(coinJoin), 0);
          }
          cdpEngine.denyCDPModification(address(coinJoin));
          cdpEngine.approveCDPModification(addr);
          coinJoin = CoinJoinLike(addr);
        }
        else if (parameter == "settlementSurplusAuctioner") {
          settlementSurplusAuctioner = addr;
        }
        else if (parameter == "dex") dex = DexLike(addr);
        else if (parameter == "leftoverReceiver") leftoverReceiver = addr;
        else revert("SurplusAuctionHouseTwo/modify-unrecognized-param");
    }
    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
        leftoverReceiver = msg.sender;
        joinCoinsInSystem();
        cdpEngine.transferInternalCoins(address(this), leftoverReceiver, cdpEngine.coinBalance(address(this)));
        leftoverReceiver = settlementSurplusAuctioner;
    }

    // --- Utils ---
    function joinCoinsInSystem() internal {
        uint externalCoinBalance = systemCoin.balanceOf(address(this));
        //TODO: wrap in try/catch
        if (externalCoinBalance > 0) {
          systemCoin.approve(address(coinJoin), externalCoinBalance);
          coinJoin.join(leftoverReceiver, externalCoinBalance);
        }
    }

    // --- Buyout ---
    function startAuction(uint amountToSell, uint initialBid) external isAuthorized returns (uint id) {
        require(mutex == 0, "SurplusAuctionHouseTwo/non-null-mutex");
        mutex = 1;

        require(auctionsStarted < uint(-1), "SurplusAuctionHouseTwo/overflow");
        require(leftoverReceiver != address(0), "SurplusAuctionHouseTwo/no-leftover-receiver");
        require(both(swapPath[0] != address(0), swapPath[1] != address(0)), "SurplusAuctionHouseTwo/null-swap-path");
        require(mul(div(amountToSell, RAY), RAY) == amountToSell, "SurplusAuctionHouseTwo/wasted-sold-amount");

        id = ++auctionsStarted;

        uint externalCoinBalance = systemCoin.balanceOf(address(this));
        require(exitAndApproveInternalCoins(amountToSell, address(dex)) == true, "SurplusAuctionHouseTwo/cannot-exit-coins");
        uint swapResult = dex.tkntkn(dex.INPUT(), div(amountToSell, RAY), address(this), swapPath);

        require(swapResult > 0, "SurplusAuctionHouseTwo/invalid-swap-result");
        require(systemCoin.balanceOf(address(this)) == externalCoinBalance, "SurplusAuctionHouseTwo/could-not-swap");
        require(protocolToken.balanceOf(address(this)) >= swapResult, "SurplusAuctionHouseTwo/swapped-amount-not-received");

        joinCoinsInSystem();

        if (cdpEngine.coinBalance(address(this)) > 0) {
          cdpEngine.transferInternalCoins(address(this), leftoverReceiver, cdpEngine.coinBalance(address(this)));
        }
        protocolToken.burn(address(this), protocolToken.balanceOf(address(this)));

        emit StartAuction(id, amountToSell, initialBid);

        mutex = 0;
    }
    function exitAndApproveInternalCoins(uint amountToSell, address dst) internal isAuthorized returns (bool) {
        uint externalCoinBalance = systemCoin.balanceOf(address(this));
        cdpEngine.transferInternalCoins(msg.sender, address(this), amountToSell);
        coinJoin.exit(address(this), div(amountToSell, RAY));
        if (add(externalCoinBalance, div(amountToSell, RAY)) != systemCoin.balanceOf(address(this))) {
          return false;
        }
        return systemCoin.approve(dst, amountToSell);
    }
}
