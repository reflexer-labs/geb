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

contract Guy {
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

contract GlobalSettlement {
    uint public contractEnabled = 0;

    function toggle() external {
        contractEnabled = (contractEnabled == 1) ? 0 : 1;
    }
}

contract SurplusAuctionHouseOneTest is DSTest {
    Hevm hevm;

    SurplusAuctionHouseOne surplusAuctionHouse;
    GlobalSettlement globalSettlement;
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
        globalSettlement = new GlobalSettlement();
        surplusAuctionHouse.modifyParameters("globalSettlement", address(globalSettlement));

        ali = address(new Guy(surplusAuctionHouse));
        bob = address(new Guy(surplusAuctionHouse));

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
        Guy(ali).increaseBidSize(id, 100 ether, 190 ether);
        assertEq(protocolToken.balanceOf(ali), 10 ether);
        Guy(ali).increaseBidSize(id, 100 ether, 200 ether);
        assertEq(protocolToken.balanceOf(ali), 0);
    }
    function test_increaseBidSize() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // amount to buy taken from creator
        assertEq(cdpEngine.coinBalance(address(this)), 900 ether);

        Guy(ali).increaseBidSize(id, 100 ether, 1 ether);
        // bid taken from bidder
        assertEq(protocolToken.balanceOf(ali), 199 ether);
        // payment remains in auction
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 1 ether);

        Guy(bob).increaseBidSize(id, 100 ether, 2 ether);
        // bid taken from bidder
        assertEq(protocolToken.balanceOf(bob), 198 ether);
        // prev bidder refunded
        assertEq(protocolToken.balanceOf(ali), 200 ether);
        // excess remains in auction
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 2 ether);

        hevm.warp(now + 5 weeks);
        Guy(bob).settleAuction(id);
        // high bidder gets the amount sold
        assertEq(cdpEngine.coinBalance(address(surplusAuctionHouse)), 0 ether);
        assertEq(cdpEngine.coinBalance(bob), 100 ether);
        // income is burned
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 0 ether);
    }
    function test_bid_increase() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        assertTrue( Guy(ali).try_increaseBidSize(id, 100 ether, 1.00 ether));
        assertTrue(!Guy(bob).try_increaseBidSize(id, 100 ether, 1.01 ether));
        // high bidder is subject to beg
        assertTrue(!Guy(ali).try_increaseBidSize(id, 100 ether, 1.01 ether));
        assertTrue( Guy(bob).try_increaseBidSize(id, 100 ether, 1.07 ether));
    }
    function test_restart_auction() public {
        // start an auction
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // check no tick
        assertTrue(!Guy(ali).try_restartAuction(id));
        // run past the end
        hevm.warp(now + 2 weeks);
        // check not biddable
        assertTrue(!Guy(ali).try_increaseBidSize(id, 100 ether, 1 ether));
        assertTrue( Guy(ali).try_restartAuction(id));
        // check biddable
        assertTrue( Guy(ali).try_increaseBidSize(id, 100 ether, 1 ether));
    }
    function testFail_terminate_prematurely() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // amount to buy taken from creator
        assertEq(cdpEngine.coinBalance(address(this)), 900 ether);

        Guy(ali).increaseBidSize(id, 100 ether, 1 ether);
        // Shutdown
        surplusAuctionHouse.disableContract();
        surplusAuctionHouse.terminateAuctionPrematurely(id);
    }
    function test_terminate_prematurely() public {
        uint id = surplusAuctionHouse.startAuction({ amountToSell: 100 ether, initialBid: 0 });
        // amount to buy taken from creator
        assertEq(cdpEngine.coinBalance(address(this)), 900 ether);

        Guy(ali).increaseBidSize(id, 100 ether, 1 ether);
        // Shutdown
        surplusAuctionHouse.disableContract();
        // Allow termination
        globalSettlement.toggle();
        surplusAuctionHouse.terminateAuctionPrematurely(id);
    }
}

contract DexLike {
    bytes32 public constant INPUT  = bytes32("INPUT");

    uint256 give;

    constructor(
      uint256 give_
    ) public {
      give = give_;
    }

    function tkntkn(bytes32 side, uint amountSold, address dst, address[] calldata swapPath) external returns (uint) {
        DSToken(swapPath[0]).transferFrom(msg.sender, address(this), amountSold);
        DSToken(swapPath[1]).transfer(dst, give);
        return give;
    }
}

contract SurplusAuctionHouseTwoTest is DSTest {
    Hevm hevm;

    SurplusAuctionHouseTwo surplusAuctionHouse;
    DexLike dex;
    CDPEngine cdpEngine;
    DSToken protocolToken;
    DSToken systemCoin;
    CoinJoin systemCoinJoin;

    address ali;
    address bob;

    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        cdpEngine  = new CDPEngine();
        protocolToken  = new DSToken('');
        systemCoin = new DSToken("Coin");
        dex  = new DexLike(1 ether);

        systemCoinJoin = new CoinJoin(address(cdpEngine), address(systemCoin));
        cdpEngine.addAuthorization(address(systemCoinJoin));
        systemCoin.mint(address(this), 50 ether);
        systemCoin.setOwner(address(systemCoinJoin));

        surplusAuctionHouse = new SurplusAuctionHouseTwo(address(cdpEngine), address(protocolToken));
        surplusAuctionHouse.modifyParameters("systemCoin", address(systemCoin));
        surplusAuctionHouse.modifyParameters("dex", address(dex));
        surplusAuctionHouse.modifyParameters("coinJoin", address(systemCoinJoin));
        surplusAuctionHouse.modifyParameters("leftoverReceiver", address(this));

        cdpEngine.approveCDPModification(address(surplusAuctionHouse));
        protocolToken.approve(address(surplusAuctionHouse));

        cdpEngine.createUnbackedDebt(address(this), address(this), rad(1000 ether));

        protocolToken.mint(1000 ether);
        protocolToken.setOwner(address(surplusAuctionHouse));
        protocolToken.push(address(dex), 200 ether);
    }
    function test_setup() public {
        assertEq(surplusAuctionHouse.swapPath(0), address(systemCoin));
        assertEq(surplusAuctionHouse.swapPath(1), address(protocolToken));
    }
    function test_start_auction() public {
        assertEq(cdpEngine.coinBalance(address(this)), rad(1000 ether));
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 0);
        assertEq(cdpEngine.coinBalance(address(surplusAuctionHouse)), 0 ether);
        assertEq(systemCoin.balanceOf(address(surplusAuctionHouse)), 0 ether);
        surplusAuctionHouse.startAuction({ amountToSell: rad(100 ether), initialBid: 0 });
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 0);
        assertEq(cdpEngine.coinBalance(address(surplusAuctionHouse)), 0 ether);
        assertEq(systemCoin.balanceOf(address(surplusAuctionHouse)), 0 ether);
        assertEq(cdpEngine.coinBalance(address(this)),  rad(900 ether));
    }
    function testFail_wasted_amount_sold() public {
        surplusAuctionHouse.startAuction({ amountToSell: rad(100 ether) + 1, initialBid: 0 });
    }
    function test_kick_protocol_token_prefunded() public {
        protocolToken.transfer(address(surplusAuctionHouse), 2 ether);
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 2 ether);
        surplusAuctionHouse.startAuction({ amountToSell: rad(100 ether), initialBid: 0 });
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 0);
    }
    function test_kick_system_coin_prefunded() public {
        systemCoin.transfer(address(surplusAuctionHouse), 50 ether);
        assertEq(cdpEngine.coinBalance(address(this)), rad(1000 ether));
        assertEq(systemCoin.balanceOf(address(this)), 0 ether);
        assertEq(systemCoin.balanceOf(address(surplusAuctionHouse)), 50 ether);
        surplusAuctionHouse.startAuction({ amountToSell: rad(100 ether), initialBid: 0 });
        assertEq(systemCoin.balanceOf(address(surplusAuctionHouse)), 0);
        assertEq(cdpEngine.coinBalance(address(surplusAuctionHouse)), 0 ether);
        assertEq(systemCoin.balanceOf(address(surplusAuctionHouse)), 0 ether);
    }
    function test_kick_internal_coins_prefunded() public {
        cdpEngine.transferInternalCoins(address(this), address(surplusAuctionHouse), rad(50 ether));
        assertEq(cdpEngine.coinBalance(address(this)), rad(950 ether));
        assertEq(cdpEngine.coinBalance(address(surplusAuctionHouse)), rad(50 ether));
        surplusAuctionHouse.startAuction({ amountToSell: rad(100 ether), initialBid: 0 });
        assertEq(cdpEngine.coinBalance(address(this)), rad(900 ether));
        assertEq(cdpEngine.coinBalance(address(surplusAuctionHouse)), 0);
    }
    function test_internal_and_external_prefunded() public {
        systemCoin.transfer(address(surplusAuctionHouse), 50 ether);
        cdpEngine.transferInternalCoins(address(this), address(surplusAuctionHouse), rad(50 ether));
        surplusAuctionHouse.startAuction({ amountToSell: rad(150 ether), initialBid: 0 });
        assertEq(protocolToken.balanceOf(address(surplusAuctionHouse)), 0);
        assertEq(cdpEngine.coinBalance(address(surplusAuctionHouse)), 0 ether);
        assertEq(systemCoin.balanceOf(address(surplusAuctionHouse)), 0 ether);
    }
}
