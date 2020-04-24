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
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
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
    uint256  public   startedAuctions = 0;
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
        require(startedAuctions < uint(-1), "SurplusAuctionHouseOne/overflow");
        id = ++startedAuctions;

        bids[id].initialBid = initialBid;
        bids[id].amountToSell = amountToSell;
        bids[id].highBidder = msg.sender;
        bids[id].auctionDeadline = add(uint48(now), totalAuctionLength);

        cdpEngine.transferInternalCoins(msg.sender, address(this), amountToSell);

        emit StartedAuction(id, amountToSell, initialBid);
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

    function disableContract(uint rad) external emitLog isAuthorized {
        contractEnabled = 0;
        cdpEngine.transferInternalCoins(address(this), msg.sender, rad);
    }
    function terminateAuctionPrematurely(uint id) external emitLog {
        require(contractEnabled == 0, "SurplusAuctionHouseOne/still-live");
        require(bids[id].highBidder != address(0), "SurplusAuctionHouseOne/hihg-bidder-not-set");
        protocolToken.move(address(this), bids[id].highBidder, bids[id].bidAmount);
        delete bids[id];
    }
}

/*
  This thing automatically buys protocol tokens from DEXs and burns them
*/

contract Flapper2 is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Flapper2/not-authorized");
        _;
    }

    VatLike     public vat;
    CoinJoinLike public join;
    TokenLike     public coin;
    TokenLike     public gov;
    DexLike     public bin;
    address     public safe;

    address[]   public path;

    uint8       public mutex;
    uint256     public startedAuctions;
    uint256     public live;

    // --- Events ---
    event Kick(
      uint256 id,
      uint256 lot,
      address lad
    );

    // --- Init ---
    constructor(address vat_) public {
        wards[msg.sender] = 1;
        vat = VatLike(vat_);
        path.push(address(0));
        path.push(address(0));
        live = 1;
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
    function file(bytes32 what, address addr) external note auth {
        require(live == 1, "Flapper2/not-live");
        if (what == "coin") {
          coin    = TokenLike(addr);
          path[0] = addr;
        }
        else if (what == "gov") {
          gov     = TokenLike(addr);
          path[1] = addr;
        }
        else if (what == "join") {
          if (address(coin) != address(0)) {
            coin.approve(address(join), 0);
          }
          vat.nope(address(join));
          vat.hope(addr);
          join = CoinJoinLike(addr);
        }
        else if (what == "bin") bin = DexLike(addr);
        else if (what == "safe") safe = addr;
        else revert("Flapper2/file-unrecognized-param");
    }
    function cage() external note auth {
        live = 0;
        loot();
        vat.move(address(this), msg.sender, vat.good(address(this)));
    }

    // --- Utils ---
    function loot() internal {
        uint own = coin.balanceOf(address(this));
        if (own > 0) {
          coin.approve(address(join), own);
          join.join(safe, own);
        }
    }

    // --- Buyout ---
    function kick(uint lot, uint bid) external auth returns (uint id) {
        require(live == 1, "Flapper2/not-live");
        require(mutex == 0, "Flapper2/non-null-mutex");
        mutex = 1;

        require(startedAuctions < uint(-1), "Flapper2/overflow");
        require(safe != address(0), "Flapper2/no-safe");
        require(both(path[0] != address(0), path[1] != address(0)), "Flapper2/null-path");
        require(mul(div(lot, RAY), RAY) == lot, "Flapper2/wasted-lot");

        id = ++startedAuctions;

        uint own = coin.balanceOf(address(this));
        require(fund(lot, address(bin)) == true, "Flapper2/cannot-fund");
        uint bid = bin.tkntkn(bin.INPUT(), div(lot, RAY), address(this), path);

        require(bid > 0, "Flapper2/invalid-bid");
        require(coin.balanceOf(address(this)) == own, "Flapper2/cannot-buy");
        require(gov.balanceOf(address(this)) >= bid, "Flapper2/bid-not-received");

        loot();

        if (vat.good(address(this)) > 0) {
          vat.move(address(this), safe, vat.good(address(this)));
        }
        gov.burn(address(this), gov.balanceOf(address(this)));

        emit Kick(id, lot, address(bin));

        mutex = 0;
    }
    function fund(uint lot, address guy) internal auth returns (bool) {
        uint own = coin.balanceOf(address(this));
        vat.move(msg.sender, address(this), lot);
        join.exit(address(this), div(lot, RAY));
        if (add(own, div(lot, RAY)) != coin.balanceOf(address(this))) {
          return false;
        }
        return coin.approve(guy, lot);
    }
}
