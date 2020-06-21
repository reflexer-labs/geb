pragma solidity ^0.5.15;

import "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";
import {SurplusAuctionHouseOne, SurplusAuctionHouseTwo} from "../SurplusAuctionHouse.sol";
import "../CDPEngine.sol";
import {CoinJoin} from '../BasicTokenAdapters.sol';
import {Coin} from "../Coin.sol";

contract Hevm {
    function warp(uint256) public;
}

contract GuySurplusAuctionOne {
    SurplusAuctionHouseOne surplusAuctionHouse;
    constructor(SurplusAuctionHouseOne surplusAuctionHouse_) public {
        surplusAuctionHouse = surplusAuctionHouse_;
        CDPEngine(address(surplusAuctionHouse.cdpEngine())).approveCDPModification(address(surplusAuctionHouse));
        DSToken(address(surplusAuctionHouse.protocolToken())).approve(address(surplusAuctionHouse));
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

contract GuySurplusAuctionTwo {
    SurplusAuctionHouseTwo surplusAuctionHouse;
    constructor(SurplusAuctionHouseTwo surplusAuctionHouse_) public {
        surplusAuctionHouse = surplusAuctionHouse_;
        CDPEngine(address(surplusAuctionHouse.cdpEngine())).approveCDPModification(address(surplusAuctionHouse));
        DSToken(address(surplusAuctionHouse.protocolToken())).approve(address(surplusAuctionHouse));
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

contract SurplusAuctionHouseOneTest is DSTest {
    Hevm hevm;

    SurplusAuctionHouseOne surplusAuctionHouse;
    CDPEngine cdpEngine;
    DSToken protocolToken;

    address ali;
    address bob;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        cdpEngine = new CDPEngine();
        protocolToken = new DSToken('');

        surplusAuctionHouse = new SurplusAuctionHouseOne(address(cdpEngine), address(protocolToken));

        ali = address(new GuySurplusAuctionOne(surplusAuctionHouse));
        bob = address(new GuySurplusAuctionOne(surplusAuctionHouse));

        cdpEngine.approveCDPModification(address(surplusAuctionHouse));
        protocolToken.approve(address(surplusAuctionHouse));

        cdpEngine.createUnbackedDebt(address(this), address(this), 1000 ether);

        protocolToken.mint(1000 ether);
        protocolToken.setOwner(address(surplusAuctionHouse));

        protocolToken.push(ali, 200 ether);
        protocolToken.push(bob, 200 ether);
    }
    function test_start_auction() public {
        assertEq(cdpEngine.coinBalance(address(this)), 1000 ether);
        assertEq(cdpEngine.coinBalance(address(surplusAuctionHouse)), 0 ether);
        surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        assertEq(cdpEngine.coinBalance(address(this)),  900 ether);
        assertEq(cdpEngine.coinBalance(address(surplusAuctionHouse)), 100 ether);
    }
    function test_increase_bid_same_bidder() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        GuySurplusAuctionOne(ali).increaseBidSize(id, 100 ether, 190 ether);
        assertEq(protocolToken.balanceOf(ali), 10 ether);
        GuySurplusAuctionOne(ali).increaseBidSize(id, 100 ether, 200 ether);
        assertEq(protocolToken.balanceOf(ali), 0);
    }
    function test_increaseBidSize() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // amount to buy taken from creator
        assertEq(cdpEngine.coinBalance(address(this)), 900 ether);

        GuySurplusAuctionOne(ali).increaseBidSize(id, 100 ether, 1 ether);
        // bid taken from bidder
        assertEq(protocolToken.balanceOf(ali), 199 ether);
        // payment remains in auction
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 1 ether);

        GuySurplusAuctionOne(bob).increaseBidSize(id, 100 ether, 2 ether);
        // bid taken from bidder
        assertEq(protocolToken.balanceOf(bob), 198 ether);
        // prev bidder refunded
        assertEq(protocolToken.balanceOf(ali), 200 ether);
        // excess remains in auction
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 2 ether);

        hevm.warp(now + 5 weeks);
        GuySurplusAuctionOne(bob).settleAuction(id);
        // high bidder gets the amount sold
        assertEq(cdpEngine.coinBalance(address(surplusAuctionHouse)), 0 ether);
        assertEq(cdpEngine.coinBalance(bob), 100 ether);
        // income is burned
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 0 ether);
    }
    function test_bid_increase() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        assertTrue( GuySurplusAuctionOne(ali).try_increaseBidSize(id, 100 ether, 1.00 ether));
        assertTrue(!GuySurplusAuctionOne(bob).try_increaseBidSize(id, 100 ether, 1.01 ether));
        // high bidder is subject to beg
        assertTrue(!GuySurplusAuctionOne(ali).try_increaseBidSize(id, 100 ether, 1.01 ether));
        assertTrue( GuySurplusAuctionOne(bob).try_increaseBidSize(id, 100 ether, 1.07 ether));
    }
    function test_restart_auction() public {
        // start an auction
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // check no tick
        assertTrue(!GuySurplusAuctionOne(ali).try_restartAuction(id));
        // run past the end
        hevm.warp(now + 2 weeks);
        // check not biddable
        assertTrue(!GuySurplusAuctionOne(ali).try_increaseBidSize(id, 100 ether, 1 ether));
        assertTrue( GuySurplusAuctionOne(ali).try_restartAuction(id));
        // check biddable
        assertTrue( GuySurplusAuctionOne(ali).try_increaseBidSize(id, 100 ether, 1 ether));
    }
    function testFail_terminate_prematurely() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // amount to buy taken from creator
        assertEq(cdpEngine.coinBalance(address(this)), 900 ether);

        GuySurplusAuctionOne(ali).increaseBidSize(id, 100 ether, 1 ether);
        // Shutdown
        surplusAuctionHouse.disableContract();
        surplusAuctionHouse.terminateAuctionPrematurely(id);
    }
    function test_terminate_prematurely() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // amount to buy taken from creator
        assertEq(cdpEngine.coinBalance(address(this)), 900 ether);

        GuySurplusAuctionOne(ali).increaseBidSize(id, 100 ether, 1 ether);
        // Shutdown
        surplusAuctionHouse.disableContract();
        surplusAuctionHouse.terminateAuctionPrematurely(id);
    }
}

contract SurplusAuctionHouseTwoTest is DSTest {
    Hevm hevm;

    SurplusAuctionHouseTwo surplusAuctionHouse;
    CDPEngine cdpEngine;
    DSToken protocolToken;

    address ali;
    address bob;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        cdpEngine = new CDPEngine();
        protocolToken = new DSToken('');

        surplusAuctionHouse = new SurplusAuctionHouseTwo(address(cdpEngine), address(protocolToken));

        ali = address(new GuySurplusAuctionTwo(surplusAuctionHouse));
        bob = address(new GuySurplusAuctionTwo(surplusAuctionHouse));

        cdpEngine.approveCDPModification(address(surplusAuctionHouse));
        protocolToken.approve(address(surplusAuctionHouse));

        cdpEngine.createUnbackedDebt(address(this), address(this), 1000 ether);

        protocolToken.mint(1000 ether);
        protocolToken.setOwner(address(surplusAuctionHouse));

        protocolToken.push(ali, 200 ether);
        protocolToken.push(bob, 200 ether);
    }
    function test_start_auction() public {
        assertEq(cdpEngine.coinBalance(address(this)), 1000 ether);
        assertEq(cdpEngine.coinBalance(address(surplusAuctionHouse)), 0 ether);
        surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        assertEq(cdpEngine.coinBalance(address(this)),  900 ether);
        assertEq(cdpEngine.coinBalance(address(surplusAuctionHouse)), 100 ether);
    }
    function test_increase_bid_same_bidder() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        GuySurplusAuctionTwo(ali).increaseBidSize(id, 100 ether, 190 ether);
        assertEq(protocolToken.balanceOf(ali), 10 ether);
        GuySurplusAuctionTwo(ali).increaseBidSize(id, 100 ether, 200 ether);
        assertEq(protocolToken.balanceOf(ali), 0);
    }
    function test_increaseBidSize() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // amount to buy taken from creator
        assertEq(cdpEngine.coinBalance(address(this)), 900 ether);

        GuySurplusAuctionTwo(ali).increaseBidSize(id, 100 ether, 1 ether);
        // bid taken from bidder
        assertEq(protocolToken.balanceOf(ali), 199 ether);
        // payment remains in auction
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 1 ether);

        GuySurplusAuctionTwo(bob).increaseBidSize(id, 100 ether, 2 ether);
        // bid taken from bidder
        assertEq(protocolToken.balanceOf(bob), 198 ether);
        // prev bidder refunded
        assertEq(protocolToken.balanceOf(ali), 200 ether);
        // excess remains in auction
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 2 ether);

        hevm.warp(now + 5 weeks);
        GuySurplusAuctionTwo(bob).settleAuction(id);
        // high bidder gets the amount sold
        assertEq(cdpEngine.coinBalance(address(surplusAuctionHouse)), 0 ether);
        assertEq(cdpEngine.coinBalance(bob), 100 ether);
        // income is burned
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 0 ether);
    }
    function test_bid_increase() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        assertTrue( GuySurplusAuctionTwo(ali).try_increaseBidSize(id, 100 ether, 1.00 ether));
        assertTrue(!GuySurplusAuctionTwo(bob).try_increaseBidSize(id, 100 ether, 1.01 ether));
        // high bidder is subject to beg
        assertTrue(!GuySurplusAuctionTwo(ali).try_increaseBidSize(id, 100 ether, 1.01 ether));
        assertTrue( GuySurplusAuctionTwo(bob).try_increaseBidSize(id, 100 ether, 1.07 ether));
    }
    function test_restart_auction() public {
        // start an auction
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // check no tick
        assertTrue(!GuySurplusAuctionTwo(ali).try_restartAuction(id));
        // run past the end
        hevm.warp(now + 2 weeks);
        // check not biddable
        assertTrue(!GuySurplusAuctionTwo(ali).try_increaseBidSize(id, 100 ether, 1 ether));
        assertTrue( GuySurplusAuctionTwo(ali).try_restartAuction(id));
        // check biddable
        assertTrue( GuySurplusAuctionTwo(ali).try_increaseBidSize(id, 100 ether, 1 ether));
    }
}
