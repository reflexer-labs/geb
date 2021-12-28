pragma solidity ^0.6.7;

import "./mocks/SurplusAuctionHouseMock.sol";
import "../../../../lib/ds-token/lib/ds-test/src/test.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract SAFEEngineMock {
    mapping (address => uint) public receivedCoin;
    mapping (address => uint) public sentCollateral;


    function transferInternalCoins(address,address to,uint256 val) public {
        receivedCoin[to] += val;
    }
    function transferCollateral(bytes32,address from,address,uint256 val) public {
        sentCollateral[from] += val;
    }
}

contract TokenMock {
    uint constant maxUint = uint(0) - 1;
    mapping (address => uint256) public received;
    mapping (address => uint256) public sent;
    mapping (address => uint256) public burned;

    function totalSupply() public view returns (uint) {
        return maxUint;
    }
    function balanceOf(address src) public view returns (uint) {
        return maxUint;
    }
    function allowance(address src, address guy) public view returns (uint) {
        return maxUint;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        public
        returns (bool)
    {
        received[dst] += wad;
        sent[src]     += wad;
        return true;
    }

    function move(address src, address dst, uint wad) public {
        transferFrom(src, dst, wad);
    }

    function approve(address guy, uint wad) virtual public returns (bool) {
        return true;
    }

    function burn(address src,uint256 wad) virtual external {
        burned[src] += wad;
    }
}

abstract contract FuzzHelpers is MixedStratSurplusAuctionHouseMock {
    uint currentBid;

    // adding a directed bidding and settling function
    // we trust the fuzzer will find it's way to the active auction (it does), but here we're forcing valid bids to make we make the most of the runs.
    // (the increaseBidSize function is also fuzzed)
    // setting it's visibility to internal will prevent it to be called by echidna
    function bid(uint256 val) public {
        if (val < 1 ether) return;
        increaseBidSize(1, bids[1].amountToSell, val);
        currentBid = val;
    }

    function settleAuction() public {
        settleAuction(1);
    }
}

// @notice Fuzz the whole thing, assess the results to see if failures make sense
contract GeneralFuzz is FuzzHelpers {

    constructor() public
        MixedStratSurplusAuctionHouseMock(
            address(new SAFEEngineMock()),
            address(new TokenMock())
        ){
            protocolTokenBidReceiver = address(0x123);

            // starting an auction
            startAuction({ amountToSell: 100 ether,
                            initialBid: 0
                        });

            // auction initiated
            assert(bids[1].amountToSell == 100 ether);
        }
}

// @notice Will create an auction, to enable fuzzing the bidding function
contract FuzzBids is DSTest, FuzzHelpers {
    Hevm hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    uint initialBid = 0; // hardcoded on the accountingEngine
    uint initialAmountToSell = 100 ether;

    constructor() public
        MixedStratSurplusAuctionHouseMock(
            address(new SAFEEngineMock()),
            address(new TokenMock())
        ){
            setUp();
        }

    function setUp() public {

        protocolTokenBidReceiver = address(0x123);

        // starting an auction
        startAuction({ amountToSell: initialAmountToSell,
                        initialBid: initialBid
                    });

        // auction initiated
        assertEq(bids[1].amountToSell, initialAmountToSell);
        assertEq(bids[1].highBidder, msg.sender);

    }

    function test_fuzz() public {
        assertTrue(echidna_bids());
        bid(105127396751461993632);
        assertTrue(echidna_bids());
        bid(135 ether);
        assertTrue(echidna_bids());
        hevm.warp(now + 3 days);
        settleAuction();
        assertTrue(echidna_bids());
    }

    // properties
    function echidna_auctionsStarted() public returns (bool) {
        return auctionsStarted == 1;
    }

    function echidna_bidIncrease() public returns (bool) {
        return bidIncrease == 1.05E18;
    }

    function echidna_bidDuration() public returns (bool) {
        return bidDuration == 3 hours;
    }

    function echidna_totalAuctionLength() public returns (bool) {
        return totalAuctionLength == 2 days;
    }

    function echidna_bids() public returns (bool) {

        // auction not started
        if (auctionsStarted == 0) return true;

        // auction settled, bid is deleted
        if (bids[1].amountToSell == 0) {
            if (TokenMock(address(protocolToken)).burned(address(this)) < (currentBid / 2) - 1) return false;
            if (TokenMock(address(protocolToken)).received(protocolTokenBidReceiver) < (currentBid / 2) - 1) return false;
            return true;
        }

        // auction ongoing
        if (bids[1].bidAmount < initialBid) return false;
        if (bids[1].amountToSell != initialAmountToSell) return false;

        // bids were made
        if (currentBid > 0) {
            if (TokenMock(address(protocolToken)).received(address(this)) != currentBid) return false;
        }
        return true;
    }
}
