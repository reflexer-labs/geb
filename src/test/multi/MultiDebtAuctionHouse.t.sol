pragma solidity 0.6.7;

import {DSTest}  from "ds-test/test.sol";
import {DSDelegateToken} from "ds-token/delegate.sol";

import "../../multi/MultiDebtAuctionHouse.sol";
import "../../multi/MultiSAFEEngine.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract Guy {
    MultiDebtAuctionHouse debtAuctionHouse;
    constructor(MultiDebtAuctionHouse debtAuctionHouse_) public {
        debtAuctionHouse = debtAuctionHouse_;
        MultiSAFEEngine(address(debtAuctionHouse.safeEngine())).approveSAFEModification(debtAuctionHouse.coinName(), address(debtAuctionHouse));
        DSDelegateToken(address(debtAuctionHouse.protocolToken())).approve(address(debtAuctionHouse));
    }
    function decreaseSoldAmount(uint id, uint amountToBuy, uint bid) public {
        debtAuctionHouse.decreaseSoldAmount(id, amountToBuy, bid);
    }
    function settleAuction(uint id) public {
        debtAuctionHouse.settleAuction(id);
    }
    function try_decreaseSoldAmount(uint id, uint amountToBuy, uint bid)
        public returns (bool ok)
    {
        string memory sig = "decreaseSoldAmount(uint256,uint256,uint256)";
        (ok,) = address(debtAuctionHouse).call(abi.encodeWithSignature(sig, id, amountToBuy, bid));
    }
    function try_settleAuction(uint id)
        public returns (bool ok)
    {
        string memory sig = "settleAuction(uint256)";
        (ok,) = address(debtAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
    function try_restart_auction(uint id)
        public returns (bool ok)
    {
        string memory sig = "restartAuction(uint256)";
        (ok,) = address(debtAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
}

contract Gal {
    uint256 public totalOnAuctionDebt;

    MultiSAFEEngine safeEngine;

    // Mapping of coin states
    mapping (bytes32 => uint256) public coinEnabled;
    // Whether a coin has been initialized or not
    mapping (bytes32 => uint256) public coinInitialized;
    // Unqueued debt for each coin
    mapping (bytes32 => uint256) public unqueuedDebt;

    constructor(MultiSAFEEngine safeEngine_) public {
        safeEngine = safeEngine_;
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function initializeCoin(bytes32 coinName) public {
        coinEnabled[coinName] = 1;
        coinInitialized[coinName] = 1;
    }
    function startAuction(MultiDebtAuctionHouse debtAuctionHouse, uint256 initialBid) external returns (uint) {
        unqueuedDebt[debtAuctionHouse.coinName()] += initialBid;
        uint id = debtAuctionHouse.startAuction();
        return id;
    }
    function settleDebt(bytes32 coinName, uint rad) external {
        unqueuedDebt[coinName] = sub(unqueuedDebt[coinName], rad);
        safeEngine.settleDebt(coinName, rad);
    }
    function disableContract(MultiDebtAuctionHouse debtAuctionHouse) external {
        debtAuctionHouse.disableContract(address(this));
    }
}

contract SAFEEnginish is DSDelegateToken('', '') {
    uint constant ONE = 10 ** 27;

    bytes32 public coinName;

    constructor(bytes32 coinName_) public {
        coinName = coinName_;
    }

    function transferInternalCoins(address src, address dst, uint rad) public {
        super.transferFrom(src, dst, rad);
    }
    function approveSAFEModification(address usr) public {
         super.approve(usr);
    }
    function coin(address usr) public view returns (uint) {
         return super.balanceOf(usr);
    }
}

contract MultiDebtAuctionHouseTest is DSTest {
    Hevm hevm;

    MultiDebtAuctionHouse debtAuctionHouse;
    MultiDebtAuctionHouse secondDebtAuctionHouse;

    MultiSAFEEngine safeEngine;
    DSDelegateToken protocolToken;

    address ali;
    address bob;

    address charlie;
    address dan;

    address accountingEngine;

    bytes32 coinName = "MAI";
    bytes32 secondCoinName = "BAI";

    function settleDebt(uint) public pure { }  // arbitrary callback

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine = new MultiSAFEEngine();
        safeEngine.initializeCoin(coinName, uint(-1));
        safeEngine.initializeCoin(secondCoinName, uint(-1));

        protocolToken = new DSDelegateToken('', '');

        accountingEngine = address(new Gal(safeEngine));
        Gal(accountingEngine).initializeCoin(coinName);
        Gal(accountingEngine).initializeCoin(secondCoinName);

        debtAuctionHouse = new MultiDebtAuctionHouse(coinName, address(safeEngine), address(protocolToken), accountingEngine);
        secondDebtAuctionHouse = new MultiDebtAuctionHouse(secondCoinName, address(safeEngine), address(protocolToken), accountingEngine);

        ali = address(new Guy(debtAuctionHouse));
        bob = address(new Guy(debtAuctionHouse));

        charlie = address(new Guy(secondDebtAuctionHouse));
        dan = address(new Guy(secondDebtAuctionHouse));

        debtAuctionHouse.addAuthorization(accountingEngine);
        secondDebtAuctionHouse.addAuthorization(accountingEngine);

        safeEngine.approveSAFEModification(coinName, address(debtAuctionHouse));
        safeEngine.approveSAFEModification(secondCoinName, address(secondDebtAuctionHouse));

        safeEngine.addAuthorization(coinName, address(debtAuctionHouse));
        safeEngine.addAuthorization(secondCoinName, address(secondDebtAuctionHouse));

        protocolToken.approve(address(debtAuctionHouse));
        protocolToken.approve(address(secondDebtAuctionHouse));

        safeEngine.createUnbackedDebt(coinName, address(accountingEngine), address(this), 1000 ether);
        safeEngine.createUnbackedDebt(secondCoinName, address(accountingEngine), address(this), 1000 ether);

        safeEngine.transferInternalCoins(coinName, address(this), ali, 200 ether);
        safeEngine.transferInternalCoins(coinName, address(this), bob, 200 ether);

        safeEngine.transferInternalCoins(secondCoinName, address(this), charlie, 200 ether);
        safeEngine.transferInternalCoins(secondCoinName, address(this), dan, 200 ether);
    }

    function test_startAuction() public {
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(protocolToken.balanceOf(accountingEngine), 0 ether);

        debtAuctionHouse.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);
        debtAuctionHouse.modifyParameters("debtAuctionBidSize", 5000 ether);

        uint256 id = Gal(accountingEngine).startAuction(debtAuctionHouse, 5000 ether);
        assertEq(debtAuctionHouse.activeDebtAuctions(), id);
        assertEq(debtAuctionHouse.totalOnAuctionDebt(), 5000 ether);
        // no value transferred
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(protocolToken.balanceOf(accountingEngine), 0 ether);
        // auction created with appropriate values
        assertEq(debtAuctionHouse.auctionsStarted(), id);
        (uint256 bid, uint256 amountToSell, address guy, uint48 bidExpiry, uint48 end) = debtAuctionHouse.bids(id);
        assertEq(bid, 5000 ether);
        assertEq(amountToSell, 200 ether);
        assertTrue(guy == accountingEngine);
        assertEq(uint256(bidExpiry), 0);
        assertEq(uint256(end), now + debtAuctionHouse.totalAuctionLength());
    }
    function test_startAuction_two_coins() public {
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(safeEngine.coinBalance(secondCoinName, accountingEngine), 0);

        assertEq(protocolToken.balanceOf(accountingEngine), 0 ether);

        debtAuctionHouse.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);
        debtAuctionHouse.modifyParameters("debtAuctionBidSize", 5000 ether);

        secondDebtAuctionHouse.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);
        secondDebtAuctionHouse.modifyParameters("debtAuctionBidSize", 5000 ether);

        uint256 firstHouseId = Gal(accountingEngine).startAuction(debtAuctionHouse, 5000 ether);
        assertEq(debtAuctionHouse.activeDebtAuctions(), firstHouseId);
        assertEq(debtAuctionHouse.totalOnAuctionDebt(), 5000 ether);

        uint256 secondHouseId = Gal(accountingEngine).startAuction(secondDebtAuctionHouse, 5000 ether);
        assertEq(secondDebtAuctionHouse.activeDebtAuctions(), secondHouseId);
        assertEq(secondDebtAuctionHouse.totalOnAuctionDebt(), 5000 ether);

        // no value transferred
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(safeEngine.coinBalance(secondCoinName, accountingEngine), 0);
        assertEq(protocolToken.balanceOf(accountingEngine), 0 ether);

        // auction created with appropriate values
        assertEq(debtAuctionHouse.auctionsStarted(), firstHouseId);
        assertEq(secondDebtAuctionHouse.auctionsStarted(), secondHouseId);

        (uint256 bid, uint256 amountToSell, address guy, uint48 bidExpiry, uint48 end) = debtAuctionHouse.bids(firstHouseId);
        assertEq(bid, 5000 ether);
        assertEq(amountToSell, 200 ether);
        assertTrue(guy == accountingEngine);
        assertEq(uint256(bidExpiry), 0);
        assertEq(uint256(end), now + debtAuctionHouse.totalAuctionLength());

        (bid, amountToSell, guy, bidExpiry, end) = secondDebtAuctionHouse.bids(secondHouseId);
        assertEq(bid, 5000 ether);
        assertEq(amountToSell, 200 ether);
        assertTrue(guy == accountingEngine);
        assertEq(uint256(bidExpiry), 0);
        assertEq(uint256(end), now + secondDebtAuctionHouse.totalAuctionLength());
    }
    function test_start_auction_leftover_accounting_surplus() public {
        safeEngine.transferInternalCoins(coinName, address(this), accountingEngine, 500 ether);

        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 500 ether);
        assertEq(safeEngine.debtBalance(coinName, accountingEngine), 1000 ether);
        assertEq(protocolToken.balanceOf(accountingEngine), 0 ether);

        debtAuctionHouse.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);
        debtAuctionHouse.modifyParameters("debtAuctionBidSize", 5000 ether);

        uint256 id = Gal(accountingEngine).startAuction(debtAuctionHouse, 5000 ether);
        assertEq(debtAuctionHouse.activeDebtAuctions(), id);
        assertEq(debtAuctionHouse.totalOnAuctionDebt(), 5000 ether);

        // no value transferred
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(coinName, accountingEngine), 500 ether);
        assertEq(protocolToken.balanceOf(accountingEngine), 0 ether);

        // auction created with appropriate values
        assertEq(debtAuctionHouse.auctionsStarted(), id);
        (uint256 bid, uint256 amountToSell, address guy, uint48 bidExpiry, uint48 end) = debtAuctionHouse.bids(id);
        assertEq(bid, 5000 ether);
        assertEq(amountToSell, 200 ether);
        assertTrue(guy == accountingEngine);
        assertEq(uint256(bidExpiry), 0);
        assertEq(uint256(end), now + debtAuctionHouse.totalAuctionLength());
    }
    function testFail_start_auction_leftover_surplus_after_settling() public {
        safeEngine.createUnbackedDebt(coinName, address(0x1), address(this), 1200 ether);
        safeEngine.transferInternalCoins(coinName, address(this), accountingEngine, 2000 ether);

        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 500 ether);
        assertEq(safeEngine.debtBalance(coinName, accountingEngine), 1000 ether);
        assertEq(protocolToken.balanceOf(accountingEngine), 0 ether);

        debtAuctionHouse.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);
        debtAuctionHouse.modifyParameters("debtAuctionBidSize", 5000 ether);

        uint256 id = Gal(accountingEngine).startAuction(debtAuctionHouse, 5000 ether);
    }
    function test_decreaseSoldAmount() public {
        debtAuctionHouse.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);
        debtAuctionHouse.modifyParameters("debtAuctionBidSize", 10 ether);

        uint id = Gal(accountingEngine).startAuction(debtAuctionHouse, 10 ether);

        Guy(ali).decreaseSoldAmount(id, 100 ether, 10 ether);
        // bid taken from bidder
        assertEq(safeEngine.coinBalance(coinName, ali), 190 ether);
        // accountingEngine receives payment
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(coinName, accountingEngine), 990 ether);
        assertEq(Gal(accountingEngine).unqueuedDebt(coinName), 0 ether);
        assertEq(debtAuctionHouse.totalOnAuctionDebt(), 0 ether);

        Guy(bob).decreaseSoldAmount(id, 80 ether, 10 ether);
        // bid taken from bidder
        assertEq(safeEngine.coinBalance(coinName, bob), 190 ether);
        // prev bidder refunded
        assertEq(safeEngine.coinBalance(coinName, ali), 200 ether);
        // accountingEngine receives no more
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(coinName, accountingEngine), 990 ether);

        hevm.warp(now + 5 weeks);
        assertEq(protocolToken.totalSupply(),  0 ether);
        protocolToken.setOwner(address(debtAuctionHouse));
        Guy(bob).settleAuction(id);
        // marked auction in the accounting engine
        assertEq(debtAuctionHouse.activeDebtAuctions(), 0);
        // tokens minted on demand
        assertEq(protocolToken.totalSupply(), 80 ether);
        // bob gets the winnings
        assertEq(protocolToken.balanceOf(bob), 80 ether);
    }
    function test_decreaseSoldAmount_two_coins() public {
        debtAuctionHouse.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);
        debtAuctionHouse.modifyParameters("debtAuctionBidSize", 10 ether);

        secondDebtAuctionHouse.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);
        secondDebtAuctionHouse.modifyParameters("debtAuctionBidSize", 10 ether);

        uint firstHouseId  = Gal(accountingEngine).startAuction(debtAuctionHouse, 10 ether);
        uint secondHouseId = Gal(accountingEngine).startAuction(secondDebtAuctionHouse, 10 ether);

        Guy(ali).decreaseSoldAmount(firstHouseId, 100 ether, 10 ether);
        Guy(charlie).decreaseSoldAmount(secondHouseId, 100 ether, 10 ether);

        // bid taken from bidder
        assertEq(safeEngine.coinBalance(coinName, ali), 190 ether);
        assertEq(safeEngine.coinBalance(secondCoinName, charlie), 190 ether);

        // accountingEngine receives payment
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(coinName, accountingEngine), 990 ether);
        assertEq(Gal(accountingEngine).unqueuedDebt(coinName), 0 ether);
        assertEq(debtAuctionHouse.totalOnAuctionDebt(), 0 ether);

        assertEq(safeEngine.coinBalance(secondCoinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(secondCoinName, accountingEngine), 990 ether);
        assertEq(Gal(accountingEngine).unqueuedDebt(secondCoinName), 0 ether);
        assertEq(secondDebtAuctionHouse.totalOnAuctionDebt(), 0 ether);

        Guy(bob).decreaseSoldAmount(firstHouseId, 80 ether, 10 ether);
        Guy(dan).decreaseSoldAmount(secondHouseId, 80 ether, 10 ether);

        // bid taken from bidder
        assertEq(safeEngine.coinBalance(coinName, bob), 190 ether);
        assertEq(safeEngine.coinBalance(secondCoinName, dan), 190 ether);

        // prev bidder refunded
        assertEq(safeEngine.coinBalance(coinName, ali), 200 ether);
        assertEq(safeEngine.coinBalance(secondCoinName, charlie), 200 ether);

        // accountingEngine receives no more
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(coinName, accountingEngine), 990 ether);

        assertEq(safeEngine.coinBalance(secondCoinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(secondCoinName, accountingEngine), 990 ether);

        hevm.warp(now + 5 weeks);
        assertEq(protocolToken.totalSupply(),  0 ether);
        protocolToken.setOwner(address(debtAuctionHouse));
        Guy(bob).settleAuction(firstHouseId);
    }
    function test_decrease_sold_amount_totalOnAuctionDebt_less_than_bid() public {
        debtAuctionHouse.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);
        debtAuctionHouse.modifyParameters("debtAuctionBidSize", 10 ether);

        uint id = Gal(accountingEngine).startAuction(debtAuctionHouse, 10 ether);
        assertEq(safeEngine.coinBalance(coinName, accountingEngine),  0 ether);
        assertEq(Gal(accountingEngine).unqueuedDebt(coinName), 10 ether);
        assertEq(debtAuctionHouse.totalOnAuctionDebt(), 10 ether);

        Guy(ali).decreaseSoldAmount(id, 100 ether, 10 ether);
        // bid taken from bidder
        assertEq(safeEngine.coinBalance(coinName, ali), 190 ether);
        // accountingEngine receives payment
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(coinName, accountingEngine), 990 ether);
        assertEq(debtAuctionHouse.totalOnAuctionDebt(), 0);
        assertEq(Gal(accountingEngine).unqueuedDebt(coinName), 0);

        Guy(bob).decreaseSoldAmount(id, 80 ether, 10 ether);
        // bid taken from bidder
        assertEq(safeEngine.coinBalance(coinName, bob), 190 ether);
        // prev bidder refunded
        assertEq(safeEngine.coinBalance(coinName, ali), 200 ether);
        // accountingEngine receives no more
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(coinName, accountingEngine), 990 ether);

        hevm.warp(now + 5 weeks);
        assertEq(protocolToken.totalSupply(),  0 ether);
        protocolToken.setOwner(address(debtAuctionHouse));
        Guy(bob).settleAuction(id);
        // marked auction in the accounting engine
        assertEq(debtAuctionHouse.activeDebtAuctions(), 0);
        // tokens minted on demand
        assertEq(protocolToken.totalSupply(), 80 ether);
        // bob gets the winnings
        assertEq(protocolToken.balanceOf(bob), 80 ether);
    }
    function test_decrease_sold_amount_totalOnAuctionDebt_less_than_bid_two_coins() public {
        debtAuctionHouse.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);
        debtAuctionHouse.modifyParameters("debtAuctionBidSize", 10 ether);

        secondDebtAuctionHouse.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);
        secondDebtAuctionHouse.modifyParameters("debtAuctionBidSize", 10 ether);

        uint firstHouseId = Gal(accountingEngine).startAuction(debtAuctionHouse, 10 ether);
        assertEq(safeEngine.coinBalance(coinName, accountingEngine),  0 ether);
        assertEq(Gal(accountingEngine).unqueuedDebt(coinName), 10 ether);
        assertEq(debtAuctionHouse.totalOnAuctionDebt(), 10 ether);

        uint secondHouseId = Gal(accountingEngine).startAuction(secondDebtAuctionHouse, 10 ether);
        assertEq(safeEngine.coinBalance(secondCoinName, accountingEngine),  0 ether);
        assertEq(Gal(accountingEngine).unqueuedDebt(secondCoinName), 10 ether);
        assertEq(secondDebtAuctionHouse.totalOnAuctionDebt(), 10 ether);

        Guy(ali).decreaseSoldAmount(firstHouseId, 100 ether, 10 ether);
        Guy(charlie).decreaseSoldAmount(secondHouseId, 100 ether, 10 ether);

        // bid taken from bidder
        assertEq(safeEngine.coinBalance(coinName, ali), 190 ether);
        assertEq(safeEngine.coinBalance(secondCoinName, charlie), 190 ether);

        // accountingEngine receives payment
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(coinName, accountingEngine), 990 ether);
        assertEq(debtAuctionHouse.totalOnAuctionDebt(), 0);
        assertEq(Gal(accountingEngine).unqueuedDebt(coinName), 0);

        assertEq(safeEngine.coinBalance(secondCoinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(secondCoinName, accountingEngine), 990 ether);
        assertEq(secondDebtAuctionHouse.totalOnAuctionDebt(), 0);
        assertEq(Gal(accountingEngine).unqueuedDebt(secondCoinName), 0);

        Guy(bob).decreaseSoldAmount(firstHouseId, 80 ether, 10 ether);
        Guy(dan).decreaseSoldAmount(secondHouseId, 80 ether, 10 ether);

        // bid taken from bidder
        assertEq(safeEngine.coinBalance(coinName, bob), 190 ether);
        assertEq(safeEngine.coinBalance(secondCoinName, dan), 190 ether);

        // prev bidder refunded
        assertEq(safeEngine.coinBalance(coinName, ali), 200 ether);
        assertEq(safeEngine.coinBalance(secondCoinName, charlie), 200 ether);

        // accountingEngine receives no more
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(coinName, accountingEngine), 990 ether);

        assertEq(safeEngine.coinBalance(secondCoinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(secondCoinName, accountingEngine), 990 ether);
    }
    function test_restart_auction() public {
        debtAuctionHouse.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);
        debtAuctionHouse.modifyParameters("debtAuctionBidSize", 10 ether);

        // start an auction
        uint id = Gal(accountingEngine).startAuction(debtAuctionHouse, 10 ether);
        // check no restarting
        assertTrue(!Guy(ali).try_restart_auction(id));
        // run past the end
        hevm.warp(now + 2 weeks);
        // check not biddable
        assertTrue(!Guy(ali).try_decreaseSoldAmount(id, 100 ether, 10 ether));
        assertTrue( Guy(ali).try_restart_auction(id));
        // left auction in the accounting engine
        assertEq(debtAuctionHouse.activeDebtAuctions(), id);
        // check biddable
        (, uint _amountToSell,,,) = debtAuctionHouse.bids(id);
        // restart should increase the amountToSell by pad (50%) and restart the auction
        assertEq(_amountToSell, 300 ether);
        assertTrue( Guy(ali).try_decreaseSoldAmount(id, 100 ether, 10 ether));
    }
    function test_no_deal_after_settlement() public {
        debtAuctionHouse.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);
        debtAuctionHouse.modifyParameters("debtAuctionBidSize", 10 ether);

        // if there are no bids and the auction ends, then it should not
        // be refundable to the creator. Rather, it restarts indefinitely.
        uint id = Gal(accountingEngine).startAuction(debtAuctionHouse, 10 ether);
        assertTrue(!Guy(ali).try_settleAuction(id));
        hevm.warp(now + 2 weeks);
        assertTrue(!Guy(ali).try_settleAuction(id));
        assertTrue( Guy(ali).try_restart_auction(id));
        // left auction in the accounting engine
        assertEq(debtAuctionHouse.activeDebtAuctions(), id);
        assertTrue(!Guy(ali).try_settleAuction(id));
    }
    function test_terminate_prematurely() public {
        debtAuctionHouse.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);
        debtAuctionHouse.modifyParameters("debtAuctionBidSize", 10 ether);

        // terminating the auction prematurely should refund the last bidder's coin, credit a
        // corresponding amount of sin to the caller of cage, and delete the auction.
        // in practice, accountingEngine == (caller of cage)
        uint id = Gal(accountingEngine).startAuction(debtAuctionHouse, 10 ether);

        // confrim initial state expectations
        assertEq(safeEngine.coinBalance(coinName, ali), 200 ether);
        assertEq(safeEngine.coinBalance(coinName, bob), 200 ether);
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(coinName, accountingEngine), 1000 ether);

        Guy(ali).decreaseSoldAmount(id, 100 ether, 10 ether);
        Guy(bob).decreaseSoldAmount(id, 80 ether, 10 ether);

        // confirm the proper state updates have occurred
        assertEq(safeEngine.coinBalance(coinName, ali), 200 ether);  // ali's coin balance is unchanged
        assertEq(safeEngine.coinBalance(coinName, bob), 190 ether);
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(coinName, address(accountingEngine)), 990 ether);
        assertEq(safeEngine.debtBalance(coinName, address(this)), 0 ether);

        Gal(accountingEngine).disableContract(debtAuctionHouse);
        assertEq(debtAuctionHouse.activeDebtAuctions(), 0);
        debtAuctionHouse.terminateAuctionPrematurely(id);

        // deleted auction from the accounting engine
        assertEq(debtAuctionHouse.activeDebtAuctions(), 0);
        // confirm final state
        assertEq(safeEngine.coinBalance(coinName, ali), 200 ether);
        assertEq(safeEngine.coinBalance(coinName, bob), 200 ether);  // bob's bid has been refunded
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(coinName, accountingEngine), 1000 ether);
        (uint256 _bid, uint256 _amountToSell, address _guy, uint48 _bidExpiry, uint48 _end) = debtAuctionHouse.bids(id);
        assertEq(_bid, 0);
        assertEq(_amountToSell, 0);
        assertEq(_guy, address(0));
        assertEq(uint256(_bidExpiry), 0);
        assertEq(uint256(_end), 0);
    }
    function test_terminate_prematurely_no_bids() public {
        debtAuctionHouse.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);
        debtAuctionHouse.modifyParameters("debtAuctionBidSize", 10 ether);

        // with no bidder to refund, terminating the auction prematurely should simply create equal
        // amounts of coin (credited to the accountingEngine) and bad debt (credited to the caller of disableContract)
        uint id = Gal(accountingEngine).startAuction(debtAuctionHouse, 10 ether);

        // confrim initial state expectations
        assertEq(safeEngine.coinBalance(coinName, ali), 200 ether);
        assertEq(safeEngine.coinBalance(coinName, bob), 200 ether);
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 0);
        assertEq(safeEngine.debtBalance(coinName, accountingEngine), 1000 ether);

        Gal(accountingEngine).disableContract(debtAuctionHouse);
        debtAuctionHouse.terminateAuctionPrematurely(id);

        // deleted auction from the accounting engine
        assertEq(debtAuctionHouse.activeDebtAuctions(), 0);
        // confirm final state
        assertEq(safeEngine.coinBalance(coinName, ali), 200 ether);
        assertEq(safeEngine.coinBalance(coinName, bob), 200 ether);
        assertEq(safeEngine.coinBalance(coinName, accountingEngine), 10 ether);
        assertEq(safeEngine.debtBalance(coinName, accountingEngine), 1010 ether);

        (uint256 _bid, uint256 _amountToSell, address _guy, uint48 _bidExpiry, uint48 _end) = debtAuctionHouse.bids(id);
        assertEq(_bid, 0);
        assertEq(_amountToSell, 0);
        assertEq(_guy, address(0));
        assertEq(uint256(_bidExpiry), 0);
        assertEq(uint256(_end), 0);
    }
}
