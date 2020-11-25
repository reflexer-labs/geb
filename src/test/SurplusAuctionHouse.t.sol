pragma solidity 0.6.7;

import "ds-test/test.sol";
import {DSDelegateToken} from "ds-token/delegate.sol";
import {BurningSurplusAuctionHouse, RecyclingSurplusAuctionHouse, PostSettlementSurplusAuctionHouse} from "../SurplusAuctionHouse.sol";
import "../SAFEEngine.sol";
import {CoinJoin} from '../BasicTokenAdapters.sol';
import {Coin} from "../Coin.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract GuyBurningSurplusAuction {
    BurningSurplusAuctionHouse surplusAuctionHouse;
    constructor(BurningSurplusAuctionHouse surplusAuctionHouse_) public {
        surplusAuctionHouse = surplusAuctionHouse_;
        SAFEEngine(address(surplusAuctionHouse.safeEngine())).approveSAFEModification(address(surplusAuctionHouse));
        DSDelegateToken(address(surplusAuctionHouse.protocolToken())).approve(address(surplusAuctionHouse));
    }
    function increaseBidSize(uint id, uint amountToBuy, uint bid) public {
        surplusAuctionHouse.increaseBidSize(id, amountToBuy, bid);
    }
    function settleAuction(uint id) public {
        surplusAuctionHouse.settleAuction(id);
    }
    function try_increaseBidSize(uint id, uint amountToBuy, uint bid)
        public returns (bool ok)
    {
        string memory sig = "increaseBidSize(uint256,uint256,uint256)";
        (ok,) = address(surplusAuctionHouse).call(abi.encodeWithSignature(sig, id, amountToBuy, bid));
    }
    function try_settleAuction(uint id)
        public returns (bool ok)
    {
        string memory sig = "settleAuction(uint256)";
        (ok,) = address(surplusAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
    function try_restartAuction(uint id)
        public returns (bool ok)
    {
        string memory sig = "restartAuction(uint256)";
        (ok,) = address(surplusAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
}

contract GuyRecyclingSurplusAuction {
    RecyclingSurplusAuctionHouse surplusAuctionHouse;
    constructor(RecyclingSurplusAuctionHouse surplusAuctionHouse_) public {
        surplusAuctionHouse = surplusAuctionHouse_;
        SAFEEngine(address(surplusAuctionHouse.safeEngine())).approveSAFEModification(address(surplusAuctionHouse));
        DSDelegateToken(address(surplusAuctionHouse.protocolToken())).approve(address(surplusAuctionHouse));
    }
    function increaseBidSize(uint id, uint amountToBuy, uint bid) public {
        surplusAuctionHouse.increaseBidSize(id, amountToBuy, bid);
    }
    function settleAuction(uint id) public {
        surplusAuctionHouse.settleAuction(id);
    }
    function try_increaseBidSize(uint id, uint amountToBuy, uint bid)
        public returns (bool ok)
    {
        string memory sig = "increaseBidSize(uint256,uint256,uint256)";
        (ok,) = address(surplusAuctionHouse).call(abi.encodeWithSignature(sig, id, amountToBuy, bid));
    }
    function try_settleAuction(uint id)
        public returns (bool ok)
    {
        string memory sig = "settleAuction(uint256)";
        (ok,) = address(surplusAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
    function try_restartAuction(uint id)
        public returns (bool ok)
    {
        string memory sig = "restartAuction(uint256)";
        (ok,) = address(surplusAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
}

contract GuyPostSurplusAuction {
    PostSettlementSurplusAuctionHouse surplusAuctionHouse;
    constructor(PostSettlementSurplusAuctionHouse surplusAuctionHouse_) public {
        surplusAuctionHouse = surplusAuctionHouse_;
        SAFEEngine(address(surplusAuctionHouse.safeEngine())).approveSAFEModification(address(surplusAuctionHouse));
        DSDelegateToken(address(surplusAuctionHouse.protocolToken())).approve(address(surplusAuctionHouse));
    }
    function increaseBidSize(uint id, uint amountToBuy, uint bid) public {
        surplusAuctionHouse.increaseBidSize(id, amountToBuy, bid);
    }
    function settleAuction(uint id) public {
        surplusAuctionHouse.settleAuction(id);
    }
    function try_increaseBidSize(uint id, uint amountToBuy, uint bid)
        public returns (bool ok)
    {
        string memory sig = "increaseBidSize(uint256,uint256,uint256)";
        (ok,) = address(surplusAuctionHouse).call(abi.encodeWithSignature(sig, id, amountToBuy, bid));
    }
    function try_settleAuction(uint id)
        public returns (bool ok)
    {
        string memory sig = "settleAuction(uint256)";
        (ok,) = address(surplusAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
    function try_restartAuction(uint id)
        public returns (bool ok)
    {
        string memory sig = "restartAuction(uint256)";
        (ok,) = address(surplusAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
}

contract GlobalSettlement {
    uint public contractEnabled = 0;

    function toggle() external {
        contractEnabled = (contractEnabled == 1) ? 0 : 1;
    }
}

contract BurningSurplusAuctionHouseTest is DSTest {
    Hevm hevm;

    BurningSurplusAuctionHouse surplusAuctionHouse;
    SAFEEngine safeEngine;
    DSDelegateToken protocolToken;

    address ali;
    address bob;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine = new SAFEEngine();
        protocolToken = new DSDelegateToken('', '');

        surplusAuctionHouse = new BurningSurplusAuctionHouse(address(safeEngine), address(protocolToken));

        ali = address(new GuyBurningSurplusAuction(surplusAuctionHouse));
        bob = address(new GuyBurningSurplusAuction(surplusAuctionHouse));

        safeEngine.approveSAFEModification(address(surplusAuctionHouse));
        protocolToken.approve(address(surplusAuctionHouse));

        safeEngine.createUnbackedDebt(address(this), address(this), 1000 ether);

        protocolToken.mint(1000 ether);
        protocolToken.setOwner(address(surplusAuctionHouse));

        protocolToken.push(ali, 200 ether);
        protocolToken.push(bob, 200 ether);
    }
    function test_start_auction() public {
        assertEq(safeEngine.coinBalance(address(this)), 1000 ether);
        assertEq(safeEngine.coinBalance(address(surplusAuctionHouse)), 0 ether);
        surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        assertEq(safeEngine.coinBalance(address(this)),  900 ether);
        assertEq(safeEngine.coinBalance(address(surplusAuctionHouse)), 100 ether);
    }
    function test_increase_bid_same_bidder() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        GuyBurningSurplusAuction(ali).increaseBidSize(id, 100 ether, 190 ether);
        assertEq(protocolToken.balanceOf(ali), 10 ether);
        GuyBurningSurplusAuction(ali).increaseBidSize(id, 100 ether, 200 ether);
        assertEq(protocolToken.balanceOf(ali), 0);
    }
    function test_increaseBidSize() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // amount to buy taken from creator
        assertEq(safeEngine.coinBalance(address(this)), 900 ether);

        GuyBurningSurplusAuction(ali).increaseBidSize(id, 100 ether, 1 ether);
        // bid taken from bidder
        assertEq(protocolToken.balanceOf(ali), 199 ether);
        // payment remains in auction
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 1 ether);

        GuyBurningSurplusAuction(bob).increaseBidSize(id, 100 ether, 2 ether);
        // bid taken from bidder
        assertEq(protocolToken.balanceOf(bob), 198 ether);
        // prev bidder refunded
        assertEq(protocolToken.balanceOf(ali), 200 ether);
        // excess remains in auction
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 2 ether);

        hevm.warp(now + 5 weeks);
        GuyBurningSurplusAuction(bob).settleAuction(id);
        // high bidder gets the amount sold
        assertEq(safeEngine.coinBalance(address(surplusAuctionHouse)), 0 ether);
        assertEq(safeEngine.coinBalance(bob), 100 ether);
        // income is burned
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 0 ether);
    }
    function test_bid_increase() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        assertTrue( GuyBurningSurplusAuction(ali).try_increaseBidSize(id, 100 ether, 1.00 ether));
        assertTrue(!GuyBurningSurplusAuction(bob).try_increaseBidSize(id, 100 ether, 1.01 ether));
        // high bidder is subject to beg
        assertTrue(!GuyBurningSurplusAuction(ali).try_increaseBidSize(id, 100 ether, 1.01 ether));
        assertTrue( GuyBurningSurplusAuction(bob).try_increaseBidSize(id, 100 ether, 1.07 ether));
    }
    function test_restart_auction() public {
        // start an auction
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // check no tick
        assertTrue(!GuyBurningSurplusAuction(ali).try_restartAuction(id));
        // run past the end
        hevm.warp(now + 2 weeks);
        // check not biddable
        assertTrue(!GuyBurningSurplusAuction(ali).try_increaseBidSize(id, 100 ether, 1 ether));
        assertTrue( GuyBurningSurplusAuction(ali).try_restartAuction(id));
        // check biddable
        assertTrue( GuyBurningSurplusAuction(ali).try_increaseBidSize(id, 100 ether, 1 ether));
    }
    function testFail_terminate_prematurely() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // amount to buy taken from creator
        assertEq(safeEngine.coinBalance(address(this)), 900 ether);

        GuyBurningSurplusAuction(ali).increaseBidSize(id, 100 ether, 1 ether);
        surplusAuctionHouse.terminateAuctionPrematurely(id);
    }
    function test_terminate_prematurely() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // amount to buy taken from creator
        assertEq(safeEngine.coinBalance(address(this)), 900 ether);

        GuyBurningSurplusAuction(ali).increaseBidSize(id, 100 ether, 1 ether);
        // Shutdown
        surplusAuctionHouse.disableContract();
        surplusAuctionHouse.terminateAuctionPrematurely(id);
    }
}

contract RecyclingSurplusAuctionHouseTest is DSTest {
    Hevm hevm;

    RecyclingSurplusAuctionHouse surplusAuctionHouse;
    SAFEEngine safeEngine;
    DSDelegateToken protocolToken;

    address ali;
    address bob;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine = new SAFEEngine();
        protocolToken = new DSDelegateToken('', '');

        surplusAuctionHouse = new RecyclingSurplusAuctionHouse(address(safeEngine), address(protocolToken));

        ali = address(new GuyRecyclingSurplusAuction(surplusAuctionHouse));
        bob = address(new GuyRecyclingSurplusAuction(surplusAuctionHouse));

        safeEngine.approveSAFEModification(address(surplusAuctionHouse));
        protocolToken.approve(address(surplusAuctionHouse));

        safeEngine.createUnbackedDebt(address(this), address(this), 1000 ether);

        protocolToken.mint(1000 ether);
        protocolToken.setOwner(address(surplusAuctionHouse));

        protocolToken.push(ali, 200 ether);
        protocolToken.push(bob, 200 ether);
    }
    function test_start_auction() public {
        surplusAuctionHouse.modifyParameters("protocolTokenBidReceiver", address(0x123));
        assertEq(safeEngine.coinBalance(address(this)), 1000 ether);
        assertEq(safeEngine.coinBalance(address(surplusAuctionHouse)), 0 ether);
        surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        assertEq(safeEngine.coinBalance(address(this)),  900 ether);
        assertEq(safeEngine.coinBalance(address(surplusAuctionHouse)), 100 ether);
    }
    function testFail_start_auction_when_prot_token_receiver_null() public {
        surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
    }
    function test_increase_bid_same_bidder() public {
        surplusAuctionHouse.modifyParameters("protocolTokenBidReceiver", address(0x123));
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        GuyRecyclingSurplusAuction(ali).increaseBidSize(id, 100 ether, 190 ether);
        assertEq(protocolToken.balanceOf(ali), 10 ether);
        GuyRecyclingSurplusAuction(ali).increaseBidSize(id, 100 ether, 200 ether);
        assertEq(protocolToken.balanceOf(ali), 0);
    }
    function test_increaseBidSize() public {
        surplusAuctionHouse.modifyParameters("protocolTokenBidReceiver", address(0x123));
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // amount to buy taken from creator
        assertEq(safeEngine.coinBalance(address(this)), 900 ether);

        GuyRecyclingSurplusAuction(ali).increaseBidSize(id, 100 ether, 1 ether);
        // bid taken from bidder
        assertEq(protocolToken.balanceOf(ali), 199 ether);
        // payment remains in auction
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 1 ether);

        GuyRecyclingSurplusAuction(bob).increaseBidSize(id, 100 ether, 2 ether);
        // bid taken from bidder
        assertEq(protocolToken.balanceOf(bob), 198 ether);
        // prev bidder refunded
        assertEq(protocolToken.balanceOf(ali), 200 ether);
        // excess remains in auction
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 2 ether);

        hevm.warp(now + 5 weeks);
        GuyRecyclingSurplusAuction(bob).settleAuction(id);
        // high bidder gets the amount sold
        assertEq(safeEngine.coinBalance(address(surplusAuctionHouse)), 0 ether);
        assertEq(safeEngine.coinBalance(bob), 100 ether);
        // income is transferred to address(0)
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 0 ether);
        assertEq(protocolToken.balanceOf(surplusAuctionHouse.protocolTokenBidReceiver()), 2 ether);
    }
    function test_bid_increase() public {
        surplusAuctionHouse.modifyParameters("protocolTokenBidReceiver", address(0x123));
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        assertTrue( GuyRecyclingSurplusAuction(ali).try_increaseBidSize(id, 100 ether, 1.00 ether));
        assertTrue(!GuyRecyclingSurplusAuction(bob).try_increaseBidSize(id, 100 ether, 1.01 ether));
        // high bidder is subject to beg
        assertTrue(!GuyRecyclingSurplusAuction(ali).try_increaseBidSize(id, 100 ether, 1.01 ether));
        assertTrue( GuyRecyclingSurplusAuction(bob).try_increaseBidSize(id, 100 ether, 1.07 ether));
    }
    function test_restart_auction() public {
        // set the protocol token bid receiver
        surplusAuctionHouse.modifyParameters("protocolTokenBidReceiver", address(0x123));
        // start an auction
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // check no tick
        assertTrue(!GuyRecyclingSurplusAuction(ali).try_restartAuction(id));
        // run past the end
        hevm.warp(now + 2 weeks);
        // check not biddable
        assertTrue(!GuyRecyclingSurplusAuction(ali).try_increaseBidSize(id, 100 ether, 1 ether));
        assertTrue( GuyRecyclingSurplusAuction(ali).try_restartAuction(id));
        // check biddable
        assertTrue( GuyRecyclingSurplusAuction(ali).try_increaseBidSize(id, 100 ether, 1 ether));
    }
    function testFail_terminate_prematurely() public {
        surplusAuctionHouse.modifyParameters("protocolTokenBidReceiver", address(0x123));
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // amount to buy taken from creator
        assertEq(safeEngine.coinBalance(address(this)), 900 ether);

        GuyRecyclingSurplusAuction(ali).increaseBidSize(id, 100 ether, 1 ether);
        surplusAuctionHouse.terminateAuctionPrematurely(id);
    }
    function test_terminate_prematurely() public {
        surplusAuctionHouse.modifyParameters("protocolTokenBidReceiver", address(0x123));
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // amount to buy taken from creator
        assertEq(safeEngine.coinBalance(address(this)), 900 ether);

        GuyRecyclingSurplusAuction(ali).increaseBidSize(id, 100 ether, 1 ether);
        // Shutdown
        surplusAuctionHouse.disableContract();
        surplusAuctionHouse.terminateAuctionPrematurely(id);
    }
}

contract PostSettlementSurplusAuctionHouseTest is DSTest {
    Hevm hevm;

    PostSettlementSurplusAuctionHouse surplusAuctionHouse;
    SAFEEngine safeEngine;
    DSDelegateToken protocolToken;

    address ali;
    address bob;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine = new SAFEEngine();
        protocolToken = new DSDelegateToken('', '');

        surplusAuctionHouse = new PostSettlementSurplusAuctionHouse(address(safeEngine), address(protocolToken));

        ali = address(new GuyPostSurplusAuction(surplusAuctionHouse));
        bob = address(new GuyPostSurplusAuction(surplusAuctionHouse));

        safeEngine.approveSAFEModification(address(surplusAuctionHouse));
        protocolToken.approve(address(surplusAuctionHouse));

        safeEngine.createUnbackedDebt(address(this), address(this), 1000 ether);

        protocolToken.mint(1000 ether);
        protocolToken.setOwner(address(surplusAuctionHouse));

        protocolToken.push(ali, 200 ether);
        protocolToken.push(bob, 200 ether);
    }
    function test_start_auction() public {
        assertEq(safeEngine.coinBalance(address(this)), 1000 ether);
        assertEq(safeEngine.coinBalance(address(surplusAuctionHouse)), 0 ether);
        surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        assertEq(safeEngine.coinBalance(address(this)),  900 ether);
        assertEq(safeEngine.coinBalance(address(surplusAuctionHouse)), 100 ether);
    }
    function test_increase_bid_same_bidder() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        GuyPostSurplusAuction(ali).increaseBidSize(id, 100 ether, 190 ether);
        assertEq(protocolToken.balanceOf(ali), 10 ether);
        GuyPostSurplusAuction(ali).increaseBidSize(id, 100 ether, 200 ether);
        assertEq(protocolToken.balanceOf(ali), 0);
    }
    function test_increaseBidSize() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // amount to buy taken from creator
        assertEq(safeEngine.coinBalance(address(this)), 900 ether);

        GuyPostSurplusAuction(ali).increaseBidSize(id, 100 ether, 1 ether);
        // bid taken from bidder
        assertEq(protocolToken.balanceOf(ali), 199 ether);
        // payment remains in auction
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 1 ether);

        GuyPostSurplusAuction(bob).increaseBidSize(id, 100 ether, 2 ether);
        // bid taken from bidder
        assertEq(protocolToken.balanceOf(bob), 198 ether);
        // prev bidder refunded
        assertEq(protocolToken.balanceOf(ali), 200 ether);
        // excess remains in auction
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 2 ether);

        hevm.warp(now + 5 weeks);
        GuyPostSurplusAuction(bob).settleAuction(id);
        // high bidder gets the amount sold
        assertEq(safeEngine.coinBalance(address(surplusAuctionHouse)), 0 ether);
        assertEq(safeEngine.coinBalance(bob), 100 ether);
        // income is burned
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 0 ether);
    }
    function test_bid_increase() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        assertTrue( GuyPostSurplusAuction(ali).try_increaseBidSize(id, 100 ether, 1.00 ether));
        assertTrue(!GuyPostSurplusAuction(bob).try_increaseBidSize(id, 100 ether, 1.01 ether));
        // high bidder is subject to beg
        assertTrue(!GuyPostSurplusAuction(ali).try_increaseBidSize(id, 100 ether, 1.01 ether));
        assertTrue( GuyPostSurplusAuction(bob).try_increaseBidSize(id, 100 ether, 1.07 ether));
    }
    function test_restart_auction() public {
        // start an auction
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // check no tick
        assertTrue(!GuyPostSurplusAuction(ali).try_restartAuction(id));
        // run past the end
        hevm.warp(now + 2 weeks);
        // check not biddable
        assertTrue(!GuyPostSurplusAuction(ali).try_increaseBidSize(id, 100 ether, 1 ether));
        assertTrue( GuyPostSurplusAuction(ali).try_restartAuction(id));
        // check biddable
        assertTrue( GuyPostSurplusAuction(ali).try_increaseBidSize(id, 100 ether, 1 ether));
    }
}
