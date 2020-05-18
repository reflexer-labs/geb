pragma solidity ^0.5.15;

import "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";

import {CDPEngine} from "../CDPEngine.sol";
import {CollateralAuctionHouse} from "../CollateralAuctionHouse.sol";
import {OracleRelayer} from "../OracleRelayer.sol";

contract Hevm {
    function warp(uint256) public;
}

contract Guy {
    CollateralAuctionHouse collateralAuctionHouse;
    constructor(CollateralAuctionHouse collateralAuctionHouse_) public {
        collateralAuctionHouse = collateralAuctionHouse_;
    }
    function approveCDPModification(address cdp) public {
        CDPEngine(address(collateralAuctionHouse.cdpEngine())).approveCDPModification(cdp);
    }
    function increaseBidSize(uint id, uint amountToBuy, uint bid) public {
        collateralAuctionHouse.increaseBidSize(id, amountToBuy, bid);
    }
    function decreaseSoldAmount(uint id, uint amountToBuy, uint bid) public {
        collateralAuctionHouse.decreaseSoldAmount(id, amountToBuy, bid);
    }
    function settleAuction(uint id) public {
        collateralAuctionHouse.settleAuction(id);
    }
    function try_increaseBidSize(uint id, uint amountToBuy, uint bid)
        public returns (bool ok)
    {
        string memory sig = "increaseBidSize(uint256,uint256,uint256)";
        (ok,) = address(collateralAuctionHouse).call(abi.encodeWithSignature(sig, id, amountToBuy, bid));
    }
    function try_decreaseSoldAmount(uint id, uint amountToBuy, uint bid)
        public returns (bool ok)
    {
        string memory sig = "decreaseSoldAmount(uint256,uint256,uint256)";
        (ok,) = address(collateralAuctionHouse).call(abi.encodeWithSignature(sig, id, amountToBuy, bid));
    }
    function try_settleAuction(uint id)
        public returns (bool ok)
    {
        string memory sig = "settleAuction(uint256)";
        (ok,) = address(collateralAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
    function try_restartAuction(uint id)
        public returns (bool ok)
    {
        string memory sig = "restartAuction(uint256)";
        (ok,) = address(collateralAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
    function try_terminateAuctionPrematurely(uint id)
        public returns (bool ok)
    {
        string memory sig = "terminateAuctionPrematurely(uint256)";
        (ok,) = address(collateralAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
}


contract Gal {}

contract CDPEngine_ is CDPEngine {
    function mint(address usr, uint wad) public {
        coinBalance[usr] += wad;
    }
    function coin_balance(address usr) public view returns (uint) {
        return coinBalance[usr];
    }
    bytes32 collateralType;
    function set_collateral_type(bytes32 collateralType_) public {
        collateralType = collateralType_;
    }
    function token_collateral_balance(address usr) public view returns (uint) {
        return tokenCollateral[collateralType][usr];
    }
}

contract Feed {
    bytes32 public priceFeedValue;
    bool public hasValidValue;
    constructor(bytes32 initPrice, bool initHas) public {
        priceFeedValue = initPrice;
        hasValidValue = initHas;
    }
    function set_val(bytes32 newPrice) external {
        priceFeedValue = newPrice;
    }
    function set_has(bool newHas) external {
        hasValidValue = newHas;
    }
    function getResultWithValidity() external returns (bytes32, bool) {
        return (priceFeedValue, hasValidValue);
    }
}

contract CollateralAuctionHouseTest is DSTest {
    Hevm hevm;

    CDPEngine_ cdpEngine;
    CollateralAuctionHouse collateralAuctionHouse;
    OracleRelayer oracleRelayer;
    Feed    feed;

    address ali;
    address bob;
    address auctionIncomeRecipient;
    address cdpAuctioned = address(0xacab);

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        cdpEngine = new CDPEngine_();

        cdpEngine.initializeCollateralType("gems");
        cdpEngine.set_collateral_type("gems");

        collateralAuctionHouse = new CollateralAuctionHouse(address(cdpEngine), "gems");

        oracleRelayer = new OracleRelayer(address(cdpEngine));
        collateralAuctionHouse.modifyParameters("oracleRelayer", address(oracleRelayer));

        feed = new Feed(bytes32(uint256(0)), true);
        collateralAuctionHouse.modifyParameters("orcl", address(feed));

        ali = address(new Guy(collateralAuctionHouse));
        bob = address(new Guy(collateralAuctionHouse));
        auctionIncomeRecipient = address(new Gal());

        Guy(ali).approveCDPModification(address(collateralAuctionHouse));
        Guy(bob).approveCDPModification(address(collateralAuctionHouse));
        cdpEngine.approveCDPModification(address(collateralAuctionHouse));

        cdpEngine.modifyCollateralBalance("gems", address(this), 1000 ether);
        cdpEngine.mint(ali, 200 ether);
        cdpEngine.mint(bob, 200 ether);
    }
    function test_startAuction() public {
        collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                            , amountToRaise: 50 ether
                                            , forgoneCollateralReceiver: cdpAuctioned
                                            , auctionIncomeRecipient: auctionIncomeRecipient
                                            , initialBid: 0
                                            });
    }
    function testFail_tend_empty() public {
        // can't tend on non-existent
        collateralAuctionHouse.increaseBidSize(42, 0, 0);
    }
    function test_increase_bid_decrease_sold_same_bidder() public {
       uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                     , amountToRaise: 200 ether
                                                     , forgoneCollateralReceiver: cdpAuctioned
                                                     , auctionIncomeRecipient: auctionIncomeRecipient
                                                     , initialBid: 0
                                                     });

        assertEq(cdpEngine.coin_balance(ali), 200 ether);
        Guy(ali).increaseBidSize(id, 100 ether, 190 ether);
        assertEq(cdpEngine.coin_balance(ali), 10 ether);
        Guy(ali).increaseBidSize(id, 100 ether, 200 ether);
        assertEq(cdpEngine.coin_balance(ali), 0);
        Guy(ali).decreaseSoldAmount(id, 80 ether, 200 ether);
    }
    function test_increase_bid() public {
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).increaseBidSize(id, 100 ether, 1 ether);
        // initialBid taken from bidder
        assertEq(cdpEngine.coin_balance(ali),   199 ether);
        // auctionIncomeRecipient receives payment
        assertEq(cdpEngine.coin_balance(auctionIncomeRecipient), 1 ether);

        Guy(bob).increaseBidSize(id, 100 ether, 2 ether);
        // initialBid taken from bidder
        assertEq(cdpEngine.coin_balance(bob), 198 ether);
        // prev bidder refunded
        assertEq(cdpEngine.coin_balance(ali), 200 ether);
        // auctionIncomeRecipient receives excess
        assertEq(cdpEngine.coin_balance(auctionIncomeRecipient), 2 ether);

        hevm.warp(now + 5 hours);
        Guy(bob).settleAuction(id);
        // bob gets the winnings
        assertEq(cdpEngine.token_collateral_balance(bob), 100 ether);
    }
    function test_increase_bid_size_later() public {
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        hevm.warp(now + 5 hours);

        Guy(ali).increaseBidSize(id, 100 ether, 1 ether);
        // initialBid taken from bidder
        assertEq(cdpEngine.coin_balance(ali), 199 ether);
        // auctionIncomeRecipient receives payment
        assertEq(cdpEngine.coin_balance(auctionIncomeRecipient),   1 ether);
    }
    function test_increase_bid_size_nonzero_bid_to_market_ratio() public {
        cdpEngine.mint(ali, 200 * 10**45 - 200 ether);
        collateralAuctionHouse.modifyParameters("bidToMarketPriceRatio", 5 * 10**26); // one half
        feed.set_val(bytes32(uint256(200 ether)));
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 150 * 10**45
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        Guy(ali).increaseBidSize(id, 1 ether, 100 * 10**45);
    }
    function testFail_increase_bid_size_nonzero_bid_to_market_ratio() public {
        cdpEngine.mint(ali, 200 * 10**45 - 200 ether);
        collateralAuctionHouse.modifyParameters("bidToMarketPriceRatio", 5 * 10**26); // one half
        feed.set_val(bytes32(uint256(200 ether)));
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 150 * 10**45
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        Guy(ali).increaseBidSize(id, 1 ether, 100 * 10**45 - 1);
    }
    function test_increase_bid_size_nonzero_bid_to_market_ratio_nonzero_redemptionPrice() public {
        cdpEngine.mint(ali, 200 * 10**45 - 200 ether);
        collateralAuctionHouse.modifyParameters("bidToMarketPriceRatio", 5 * 10**26); // one half
        oracleRelayer.modifyParameters("redemptionPrice", 2 * 10**27); // 2 REF per RAI
        feed.set_val(bytes32(uint256(200 ether)));
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 75 * 10**45
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        Guy(ali).increaseBidSize(id, 1 ether, 50 * 10**45);
    }
    function testFail_increase_bid_size_nonzero_bid_to_market_ratio_nonzero_redemptionPrice() public {
        cdpEngine.mint(ali, 200 * 10**45 - 200 ether);
        collateralAuctionHouse.modifyParameters("bidToMarketPriceRatio", 5 * 10**26); // one half
        oracleRelayer.modifyParameters("redemptionPrice", 2 * 10**27); // 2 REF per RAI
        feed.set_val(bytes32(uint256(200 ether)));
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 75 * 10**45
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        Guy(ali).increaseBidSize(id, 1 ether, 50 * 10**45 - 1);
    }
    function test_decrease_sold() public {
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        Guy(ali).increaseBidSize(id, 100 ether,  1 ether);
        Guy(bob).increaseBidSize(id, 100 ether, 50 ether);

        Guy(ali).decreaseSoldAmount(id,  95 ether, 50 ether);

        assertEq(cdpEngine.token_collateral_balance(address(0xacab)), 5 ether);
        assertEq(cdpEngine.coin_balance(ali),  150 ether);
        assertEq(cdpEngine.coin_balance(bob),  200 ether);
    }
    function test_beg() public {
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        assertTrue( Guy(ali).try_increaseBidSize(id, 100 ether, 1.00 ether));
        assertTrue(!Guy(bob).try_increaseBidSize(id, 100 ether, 1.01 ether));
        // high bidder is subject to bid increase
        assertTrue(!Guy(ali).try_increaseBidSize(id, 100 ether, 1.01 ether));
        assertTrue( Guy(bob).try_increaseBidSize(id, 100 ether, 1.07 ether));

        // can bid by less than bid increase
        assertTrue( Guy(ali).try_increaseBidSize(id, 100 ether, 49 ether));
        assertTrue( Guy(bob).try_increaseBidSize(id, 100 ether, 50 ether));

        assertTrue(!Guy(ali).try_decreaseSoldAmount(id, 100 ether, 50 ether));
        assertTrue(!Guy(ali).try_decreaseSoldAmount(id,  99 ether, 50 ether));
        assertTrue( Guy(ali).try_decreaseSoldAmount(id,  95 ether, 50 ether));
    }
    function test_settle_auction() public {
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        // only after bid expiry
        Guy(ali).increaseBidSize(id, 100 ether, 1 ether);
        assertTrue(!Guy(bob).try_settleAuction(id));
        hevm.warp(now + 4.1 hours);
        assertTrue( Guy(bob).try_settleAuction(id));

        uint ie = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        // or after end
        hevm.warp(now + 44 hours);
        Guy(ali).increaseBidSize(ie, 100 ether, 1 ether);
        assertTrue(!Guy(bob).try_settleAuction(ie));
        hevm.warp(now + 1 days);
        assertTrue( Guy(bob).try_settleAuction(ie));
    }
    function test_restart_auction() public {
        // start an auction
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        // check no restart
        assertTrue(!Guy(ali).try_restartAuction(id));
        // run past the end
        hevm.warp(now + 2 weeks);
        // check not biddable
        assertTrue(!Guy(ali).try_increaseBidSize(id, 100 ether, 1 ether));
        assertTrue( Guy(ali).try_restartAuction(id));
        // check biddable
        assertTrue( Guy(ali).try_increaseBidSize(id, 100 ether, 1 ether));
    }
    function test_no_deal_after_end() public {
        // if there are no bids and the auction ends, then it should not
        // be refundable to the creator. Rather, it restarts indefinitely.
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        assertTrue(!Guy(ali).try_settleAuction(id));
        hevm.warp(now + 2 weeks);
        assertTrue(!Guy(ali).try_settleAuction(id));
        assertTrue( Guy(ali).try_restartAuction(id));
        assertTrue(!Guy(ali).try_settleAuction(id));
    }
    function test_terminate_prematurely_increase_bid() public {
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).increaseBidSize(id, 100 ether, 1 ether);
        // initialBid taken from bidder
        assertEq(cdpEngine.coin_balance(ali),   199 ether);
        assertEq(cdpEngine.coin_balance(auctionIncomeRecipient), 1 ether);

        cdpEngine.mint(address(this), 1 ether);
        collateralAuctionHouse.terminateAuctionPrematurely(id);
        // initialBid is refunded to bidder from caller
        assertEq(cdpEngine.coin_balance(ali),            200 ether);
        assertEq(cdpEngine.coin_balance(address(this)),    0 ether);
        // gems go to caller
        assertEq(cdpEngine.token_collateral_balance(address(this)), 1000 ether);
    }
    function test_terminate_prematurely_decrease_sold() public {
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        Guy(ali).increaseBidSize(id, 100 ether,  1 ether);
        Guy(bob).increaseBidSize(id, 100 ether, 50 ether);
        Guy(ali).decreaseSoldAmount(id,  95 ether, 50 ether);

        // cannot terminate_prematurely in the dent phase
        assertTrue(!Guy(ali).try_terminateAuctionPrematurely(id));
    }
}
