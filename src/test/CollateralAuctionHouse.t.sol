pragma solidity ^0.6.7;

import "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";

import {CDPEngine} from "../CDPEngine.sol";
import {EnglishCollateralAuctionHouse, FixedDiscountCollateralAuctionHouse} from "../CollateralAuctionHouse.sol";
import {OracleRelayer} from "../OracleRelayer.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract Guy {
    EnglishCollateralAuctionHouse englishCollateralAuctionHouse;
    FixedDiscountCollateralAuctionHouse fixedDiscountCollateralAuctionHouse;

    constructor(
      EnglishCollateralAuctionHouse englishCollateralAuctionHouse_,
      FixedDiscountCollateralAuctionHouse fixedDiscountCollateralAuctionHouse_
    ) public {
        englishCollateralAuctionHouse = englishCollateralAuctionHouse_;
        fixedDiscountCollateralAuctionHouse = fixedDiscountCollateralAuctionHouse_;
    }
    function approveCDPModification(bytes32 auctionType, address cdp) public {
        address cdpEngine = (auctionType == "english") ?
          address(englishCollateralAuctionHouse.cdpEngine()) : address(fixedDiscountCollateralAuctionHouse.cdpEngine());
        CDPEngine(cdpEngine).approveCDPModification(cdp);
    }
    function increaseBidSize(uint id, uint amountToBuy, uint rad) public {
        englishCollateralAuctionHouse.increaseBidSize(id, amountToBuy, rad);
    }
    function buyCollateral(uint id, uint wad) public {
        fixedDiscountCollateralAuctionHouse.buyCollateral(id, wad);
    }
    function decreaseSoldAmount(uint id, uint amountToBuy, uint bid) public {
        englishCollateralAuctionHouse.decreaseSoldAmount(id, amountToBuy, bid);
    }
    function settleAuction(uint id) public {
        englishCollateralAuctionHouse.settleAuction(id);
    }
    function try_increaseBidSize(uint id, uint amountToBuy, uint rad)
        public returns (bool ok)
    {
        string memory sig = "increaseBidSize(uint256,uint256,uint256)";
        (ok,) = address(englishCollateralAuctionHouse).call(abi.encodeWithSignature(sig, id, amountToBuy, rad));
    }
    function try_buyCollateral(uint id, uint wad)
        public returns (bool ok)
    {
        string memory sig = "buyCollateral(uint256,uint256)";
        (ok,) = address(fixedDiscountCollateralAuctionHouse).call(abi.encodeWithSignature(sig, id, wad));
    }
    function try_decreaseSoldAmount(uint id, uint amountToBuy, uint bid)
        public returns (bool ok)
    {
        string memory sig = "decreaseSoldAmount(uint256,uint256,uint256)";
        (ok,) = address(englishCollateralAuctionHouse).call(abi.encodeWithSignature(sig, id, amountToBuy, bid));
    }
    function try_settleAuction(uint id)
        public returns (bool ok)
    {
        string memory sig = "settleAuction(uint256)";
        (ok,) = address(englishCollateralAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
    function try_restartAuction(uint id)
        public returns (bool ok)
    {
        string memory sig = "restartAuction(uint256)";
        (ok,) = address(englishCollateralAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
    function try_english_terminateAuctionPrematurely(uint id)
        public returns (bool ok)
    {
        string memory sig = "terminateAuctionPrematurely(uint256)";
        (ok,) = address(englishCollateralAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
    function try_fixedDiscount_terminateAuctionPrematurely(uint id)
        public returns (bool ok)
    {
        string memory sig = "terminateAuctionPrematurely(uint256)";
        (ok,) = address(fixedDiscountCollateralAuctionHouse).call(abi.encodeWithSignature(sig, id));
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

contract RevertableMedian {
    function getResultWithValidity() external returns (bytes32, bool) {
        revert();
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

contract EnglishCollateralAuctionHouseTest is DSTest {
    Hevm hevm;

    CDPEngine_ cdpEngine;
    EnglishCollateralAuctionHouse collateralAuctionHouse;
    OracleRelayer oracleRelayer;
    Feed    osm;

    address ali;
    address bob;
    address auctionIncomeRecipient;
    address cdpAuctioned = address(0xacab);

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        cdpEngine = new CDPEngine_();

        cdpEngine.initializeCollateralType("collateralType");
        cdpEngine.set_collateral_type("collateralType");

        collateralAuctionHouse = new EnglishCollateralAuctionHouse(address(cdpEngine), "collateralType");

        oracleRelayer = new OracleRelayer(address(cdpEngine));
        collateralAuctionHouse.modifyParameters("oracleRelayer", address(oracleRelayer));

        osm = new Feed(bytes32(uint256(0)), true);
        collateralAuctionHouse.modifyParameters("osm", address(osm));

        ali = address(new Guy(collateralAuctionHouse, FixedDiscountCollateralAuctionHouse(address(0))));
        bob = address(new Guy(collateralAuctionHouse, FixedDiscountCollateralAuctionHouse(address(0))));
        auctionIncomeRecipient = address(new Gal());

        Guy(ali).approveCDPModification("english", address(collateralAuctionHouse));
        Guy(bob).approveCDPModification("english", address(collateralAuctionHouse));
        cdpEngine.approveCDPModification(address(collateralAuctionHouse));

        cdpEngine.modifyCollateralBalance("collateralType", address(this), 1000 ether);
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
    function testFail_increaseBidSize_empty() public {
        // can't increase bid size on non-existent
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
        osm.set_val(bytes32(uint256(200 ether)));
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
        osm.set_val(bytes32(uint256(200 ether)));
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
        osm.set_val(bytes32(uint256(200 ether)));
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
        osm.set_val(bytes32(uint256(200 ether)));
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
        // collateralType go to caller
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
        assertTrue(!Guy(ali).try_english_terminateAuctionPrematurely(id));
    }
}


contract FixedDiscountCollateralAuctionHouseTest is DSTest {
    Hevm hevm;

    CDPEngine_ cdpEngine;
    FixedDiscountCollateralAuctionHouse collateralAuctionHouse;
    OracleRelayer oracleRelayer;
    Feed    collateralOSM;
    Feed    collateralMedian;
    Feed    systemCoinMedian;

    address ali;
    address bob;
    address auctionIncomeRecipient;
    address cdpAuctioned = address(0xacab);

    uint constant WAD = 10 ** 18;
    uint constant RAY = 10 ** 27;
    uint constant RAD = 10 ** 45;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        cdpEngine = new CDPEngine_();

        cdpEngine.initializeCollateralType("collateralType");
        cdpEngine.set_collateral_type("collateralType");

        collateralAuctionHouse = new FixedDiscountCollateralAuctionHouse(address(cdpEngine), "collateralType");

        oracleRelayer = new OracleRelayer(address(cdpEngine));
        oracleRelayer.modifyParameters("redemptionPrice", 5 * RAY);
        collateralAuctionHouse.modifyParameters("oracleRelayer", address(oracleRelayer));

        collateralOSM = new Feed(bytes32(uint256(0)), true);
        collateralAuctionHouse.modifyParameters("collateralOSM", address(collateralOSM));

        collateralMedian = new Feed(bytes32(uint256(0)), true);
        systemCoinMedian = new Feed(bytes32(uint256(0)), true);

        ali = address(new Guy(EnglishCollateralAuctionHouse(address(0)), collateralAuctionHouse));
        bob = address(new Guy(EnglishCollateralAuctionHouse(address(0)), collateralAuctionHouse));
        auctionIncomeRecipient = address(new Gal());

        Guy(ali).approveCDPModification("fixed", address(collateralAuctionHouse));
        Guy(bob).approveCDPModification("fixed", address(collateralAuctionHouse));
        cdpEngine.approveCDPModification(address(collateralAuctionHouse));

        cdpEngine.modifyCollateralBalance("collateralType", address(this), 1000 ether);
        cdpEngine.mint(ali, 200 ether);
        cdpEngine.mint(bob, 200 ether);
    }

    // --- Math ---
    function addition(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function subtract(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function multiply(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function wmultiply(uint x, uint y) internal pure returns (uint z) {
        z = multiply(x, y) / WAD;
    }
    function rdivide(uint x, uint y) internal pure returns (uint z) {
      z = multiply(x, RAY) / y;
    }
    function wdivide(uint x, uint y) internal pure returns (uint z) {
      z = multiply(x, WAD) / y;
    }

    function test_modifyParameters() public {
        collateralAuctionHouse.modifyParameters("discount", 0.90E18);
        collateralAuctionHouse.modifyParameters("minimumBid", 50 * WAD);
        collateralAuctionHouse.modifyParameters("totalAuctionLength", 5 days);
        collateralAuctionHouse.modifyParameters("lowerCollateralMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperCollateralMedianDeviation", 0.90E18);
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        assertEq(collateralAuctionHouse.discount(), 0.90E18);
        assertEq(collateralAuctionHouse.lowerCollateralMedianDeviation(), 0.95E18);
        assertEq(collateralAuctionHouse.upperCollateralMedianDeviation(), 0.90E18);
        assertEq(collateralAuctionHouse.lowerSystemCoinMedianDeviation(), 0.95E18);
        assertEq(collateralAuctionHouse.upperSystemCoinMedianDeviation(), 0.90E18);
        assertEq(collateralAuctionHouse.minimumBid(), 50 * WAD);
        assertEq(uint(collateralAuctionHouse.totalAuctionLength()), 5 days);
    }
    function testFail_no_discount() public {
        collateralAuctionHouse.modifyParameters("discount", 1 ether);
    }
    function test_startAuction() public {
        collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                            , amountToRaise: 50 * RAD
                                            , forgoneCollateralReceiver: cdpAuctioned
                                            , auctionIncomeRecipient: auctionIncomeRecipient
                                            , initialBid: 0
                                            });
    }
    function testFail_buyCollateral_inexistent_auction() public {
        // can't buyCollateral on non-existent
        collateralAuctionHouse.buyCollateral(42, 5 * WAD);
    }
    function testFail_buyCollateral_null_bid() public {
        collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                            , amountToRaise: 50 * RAD
                                            , forgoneCollateralReceiver: cdpAuctioned
                                            , auctionIncomeRecipient: auctionIncomeRecipient
                                            , initialBid: 0
                                            });
        // can't buy collateral on non-existent
        collateralAuctionHouse.buyCollateral(1, 0);
    }
    function testFail_faulty_collateral_osm_price() public {
        Feed faultyFeed = new Feed(bytes32(uint256(1)), false);
        collateralAuctionHouse.modifyParameters("collateralOSM", address(faultyFeed));
        collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                            , amountToRaise: 50 * RAD
                                            , forgoneCollateralReceiver: cdpAuctioned
                                            , auctionIncomeRecipient: auctionIncomeRecipient
                                            , initialBid: 0
                                            });
        collateralAuctionHouse.buyCollateral(1, 5 * WAD);
    }
    function test_buy_some_collateral() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 131578947368421052);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_buy_all_collateral() public {
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        assertEq(collateralAuctionHouse.getDiscountedCollateralPrice(200 ether, 0, oracleRelayer.redemptionPrice(), 0.95E18), 95 ether);
        assertEq(collateralAuctionHouse.getCollateralBought(id, 50 * WAD), 526315789473684210);
        Guy(ali).buyCollateral(id, 50 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, uint256 amountToSell, uint256 amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 526315789473684210);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(cdpAuctioned)), 1 ether - 526315789473684210);
    }
    function testFail_start_tiny_collateral_auction() public {
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100
                                                      , amountToRaise: 50
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
    }
    function test_buyCollateral_small_market_price() public {
        collateralOSM.set_val(bytes32(uint256(0.01 ether)));
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);

        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 5 * WAD);

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 5 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(cdpAuctioned)), 0);
    }
    function test_buyCollateral_small_redemption_price() public {
        oracleRelayer.modifyParameters("redemptionPrice", 0.01E27);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 50 * WAD);

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 2631578947368421);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(cdpAuctioned)), 1 ether - 2631578947368421);
    }
    function test_buyCollateral_insignificant_leftover_to_raise() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        Guy(ali).buyCollateral(id, 49.99E18);
        Guy(ali).buyCollateral(id, 5 * WAD);

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 263157894736842104);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(cdpAuctioned)), 1 ether - 263157894736842104);
    }
    function test_big_discount_buy() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralAuctionHouse.modifyParameters("discount", 0.10E18);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        Guy(ali).buyCollateral(id, 50 * WAD);

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1000000000000000000);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(cdpAuctioned)), 0);
    }
    function test_small_discount_buy() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralAuctionHouse.modifyParameters("discount", 0.99E18);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        Guy(ali).buyCollateral(id, 50 * WAD);

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 252525252525252525);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(cdpAuctioned)), 1 ether - 252525252525252525);
    }
    function test_collateral_median_and_collateral_osm_equal() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        collateralMedian.set_val(bytes32(uint256(200 ether)));
        collateralAuctionHouse.modifyParameters("collateralMedian", address(collateralMedian));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 131578947368421052);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_collateral_median_higher_than_collateral_osm_floor() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        collateralMedian.set_val(bytes32(uint256(181 ether)));
        collateralAuctionHouse.modifyParameters("collateralMedian", address(collateralMedian));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 145391102064553649);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 145391102064553649);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 145391102064553649);
    }
    function test_collateral_median_lower_than_collateral_osm_ceiling() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        collateralMedian.set_val(bytes32(uint256(209 ether)));
        collateralAuctionHouse.modifyParameters("collateralMedian", address(collateralMedian));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 125912868295139763);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 125912868295139763);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 125912868295139763);
    }
    function test_collateral_median_higher_than_collateral_osm_ceiling() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        collateralMedian.set_val(bytes32(uint256(500 ether)));
        collateralAuctionHouse.modifyParameters("collateralMedian", address(collateralMedian));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 125313283208020050);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 125313283208020050);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 125313283208020050);
    }
    function test_collateral_median_lower_than_collateral_osm_floor() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        collateralMedian.set_val(bytes32(uint256(1 ether)));
        collateralAuctionHouse.modifyParameters("collateralMedian", address(collateralMedian));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 146198830409356725);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 146198830409356725);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 146198830409356725);
    }
    function test_collateral_median_lower_than_collateral_osm_buy_all() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        collateralMedian.set_val(bytes32(uint256(1 ether)));
        collateralAuctionHouse.modifyParameters("collateralMedian", address(collateralMedian));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 50 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 292397660818713450);
    }
    function test_collateral_median_reverts() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        RevertableMedian revertMedian = new RevertableMedian();
        collateralAuctionHouse.modifyParameters("collateralMedian", address(revertMedian));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 131578947368421052);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_system_coin_median_and_redemption_equal() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        systemCoinMedian.set_val(bytes32(uint(1 ether)));

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 131578947368421052);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_system_coin_median_higher_than_redemption_floor() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        systemCoinMedian.set_val(bytes32(uint(0.975E18)));

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 128289473684210526);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 128289473684210526);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 128289473684210526);
    }
    function test_system_coin_median_lower_than_redemption_ceiling() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        systemCoinMedian.set_val(bytes32(uint(1.05E18)));

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 138157894736842105);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 138157894736842105);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 138157894736842105);
    }
    function test_system_coin_median_higher_than_redemption_ceiling() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        systemCoinMedian.set_val(bytes32(uint(1.15E18)));

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 144736842105263157);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 144736842105263157);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 144736842105263157);
    }
    function test_system_coin_median_lower_than_redemption_floor() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        systemCoinMedian.set_val(bytes32(uint(0.90E18)));

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 125000000000000000);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 125000000000000000);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 125000000000000000);
    }
    function test_system_coin_median_lower_than_redemption_buy_all() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        systemCoinMedian.set_val(bytes32(uint(0.90E18)));

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 50 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 250000000000000000);
    }
    function test_system_coin_median_reverts() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        RevertableMedian revertMedian = new RevertableMedian();

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(revertMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 131578947368421052);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_system_coin_lower_collateral_median_higher() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        systemCoinMedian.set_val(bytes32(uint(0.90E18)));

        collateralOSM.set_val(bytes32(uint256(200 ether)));
        collateralMedian.set_val(bytes32(uint256(220 ether)));
        collateralAuctionHouse.modifyParameters("collateralMedian", address(collateralMedian));

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 119047619047619047);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 119047619047619047);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 119047619047619047);
    }
    function test_system_coin_higher_collateral_median_lower() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        systemCoinMedian.set_val(bytes32(uint(1.10E18)));

        collateralOSM.set_val(bytes32(uint256(200 ether)));
        collateralMedian.set_val(bytes32(uint256(180 ether)));
        collateralAuctionHouse.modifyParameters("collateralMedian", address(collateralMedian));

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 160818713450292397);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 160818713450292397);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 160818713450292397);
    }
    function test_system_coin_lower_collateral_median_lower() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        systemCoinMedian.set_val(bytes32(uint(0.90E18)));

        collateralOSM.set_val(bytes32(uint256(200 ether)));
        collateralMedian.set_val(bytes32(uint256(180 ether)));
        collateralAuctionHouse.modifyParameters("collateralMedian", address(collateralMedian));

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 138888888888888888);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 138888888888888888);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 138888888888888888);
    }
    function test_system_coin_higher_collateral_median_higher() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        systemCoinMedian.set_val(bytes32(uint(1.10E18)));

        collateralOSM.set_val(bytes32(uint256(200 ether)));
        collateralMedian.set_val(bytes32(uint256(210 ether)));
        collateralAuctionHouse.modifyParameters("collateralMedian", address(collateralMedian));

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 137844611528822055);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 137844611528822055);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 137844611528822055);
    }
    function test_min_system_coin_deviation_exceeds_lower_deviation() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        systemCoinMedian.set_val(bytes32(uint(0.95E18)));

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("minSystemCoinMedianDeviation", 0.94E18);
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 131578947368421052);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_min_system_coin_deviation_exceeds_higher_deviation() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        systemCoinMedian.set_val(bytes32(uint(1.05E18)));

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("minSystemCoinMedianDeviation", 0.89E18);
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 131578947368421052);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_buy_and_settle() public {
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        hevm.warp(now + collateralAuctionHouse.totalAuctionLength() + 1);
        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 263157894736842105);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(cdpAuctioned)), 1 ether - 263157894736842105);
    }
    function test_settle_auction() public {
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        hevm.warp(now + collateralAuctionHouse.totalAuctionLength() + 1);
        collateralAuctionHouse.settleAuction(id);

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 0);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 0);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(cdpAuctioned)), 1 ether);
    }
    function testFail_terminate_inexistent() public {
        collateralAuctionHouse.terminateAuctionPrematurely(1);
    }
    function test_terminateAuctionPrematurely() public {
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        collateralOSM.set_val(bytes32(uint256(200 ether)));
        cdpEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = cdpEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: cdpAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);
        collateralAuctionHouse.terminateAuctionPrematurely(1);

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(cdpEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(this)), 999736842105263157895);
        assertEq(addition(999736842105263157895, 263157894736842105), 1000 ether);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 263157894736842105);
        assertEq(cdpEngine.tokenCollateral("collateralType", address(cdpAuctioned)), 0);
    }
}
