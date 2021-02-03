pragma solidity 0.6.7;

import "ds-test/test.sol";
import {DSDelegateToken} from "ds-token/delegate.sol";

import {SAFEEngine} from "../SAFEEngine.sol";
import {EnglishCollateralAuctionHouse, FixedDiscountCollateralAuctionHouse, IncreasingDiscountCollateralAuctionHouse} from "../CollateralAuctionHouse.sol";
import {OracleRelayer} from "../OracleRelayer.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract Guy {
    EnglishCollateralAuctionHouse englishCollateralAuctionHouse;
    FixedDiscountCollateralAuctionHouse fixedDiscountCollateralAuctionHouse;
    IncreasingDiscountCollateralAuctionHouse increasingDiscountCollateralAuctionHouse;

    constructor(
      EnglishCollateralAuctionHouse englishCollateralAuctionHouse_,
      FixedDiscountCollateralAuctionHouse fixedDiscountCollateralAuctionHouse_,
      IncreasingDiscountCollateralAuctionHouse increasingDiscountCollateralAuctionHouse_
    ) public {
        englishCollateralAuctionHouse = englishCollateralAuctionHouse_;
        fixedDiscountCollateralAuctionHouse = fixedDiscountCollateralAuctionHouse_;
        increasingDiscountCollateralAuctionHouse = increasingDiscountCollateralAuctionHouse_;
    }
    function approveSAFEModification(bytes32 auctionType, address safe) public {
        address safeEngine;
        if (auctionType == "english") {
          safeEngine = address(englishCollateralAuctionHouse.safeEngine());
        }
        else if (auctionType == "increasing") {
          safeEngine = address(increasingDiscountCollateralAuctionHouse.safeEngine());
        }
        else {
          safeEngine = address(fixedDiscountCollateralAuctionHouse.safeEngine());
        }
        SAFEEngine(safeEngine).approveSAFEModification(safe);
    }
    function increaseBidSize(uint id, uint amountToBuy, uint rad) public {
        englishCollateralAuctionHouse.increaseBidSize(id, amountToBuy, rad);
    }
    function buyCollateral(uint id, uint wad) public {
        fixedDiscountCollateralAuctionHouse.buyCollateral(id, wad);
    }
    function buyCollateral_increasingDiscount(uint id, uint wad) public {
        increasingDiscountCollateralAuctionHouse.buyCollateral(id, wad);
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
    function try_buyCollateral_increasingDiscount(uint id, uint wad)
        public returns (bool ok)
    {
        string memory sig = "buyCollateral(uint256,uint256)";
        (ok,) = address(increasingDiscountCollateralAuctionHouse).call(abi.encodeWithSignature(sig, id, wad));
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
    function try_increasingDiscount_terminateAuctionPrematurely(uint id)
        public returns (bool ok)
    {
        string memory sig = "terminateAuctionPrematurely(uint256)";
        (ok,) = address(increasingDiscountCollateralAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
}

contract Gal {}

contract SAFEEngine_ is SAFEEngine {
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
    address public priceSource;
    uint256 public priceFeedValue;
    bool public hasValidValue;
    constructor(bytes32 initPrice, bool initHas) public {
        priceFeedValue = uint(initPrice);
        hasValidValue = initHas;
    }
    function set_val(uint newPrice) external {
        priceFeedValue = newPrice;
    }
    function set_price_source(address priceSource_) external {
        priceSource = priceSource_;
    }
    function set_has(bool newHas) external {
        hasValidValue = newHas;
    }
    function getResultWithValidity() external returns (uint256, bool) {
        return (priceFeedValue, hasValidValue);
    }
}

contract PartiallyImplementedFeed {
    uint256 public priceFeedValue;
    bool public hasValidValue;
    constructor(bytes32 initPrice, bool initHas) public {
        priceFeedValue = uint(initPrice);
        hasValidValue = initHas;
    }
    function set_val(uint newPrice) external {
        priceFeedValue = newPrice;
    }
    function set_has(bool newHas) external {
        hasValidValue = newHas;
    }
    function getResultWithValidity() external returns (uint256, bool) {
        return (priceFeedValue, hasValidValue);
    }
}

contract DummyLiquidationEngine {
    uint256 public currentOnAuctionSystemCoins;

    constructor(uint rad) public {
        currentOnAuctionSystemCoins = rad;
    }

    function subtract(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    function removeCoinsFromAuction(uint rad) public {
      currentOnAuctionSystemCoins = subtract(currentOnAuctionSystemCoins, rad);
    }
}

contract EnglishCollateralAuctionHouseTest is DSTest {
    Hevm hevm;

    DummyLiquidationEngine liquidationEngine;
    SAFEEngine_ safeEngine;
    EnglishCollateralAuctionHouse collateralAuctionHouse;

    address ali;
    address bob;
    address auctionIncomeRecipient;
    address safeAuctioned = address(0xacab);

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine = new SAFEEngine_();

        safeEngine.initializeCollateralType("collateralType");
        safeEngine.set_collateral_type("collateralType");

        liquidationEngine = new DummyLiquidationEngine(rad(1000 ether));
        collateralAuctionHouse = new EnglishCollateralAuctionHouse(address(safeEngine), address(liquidationEngine), "collateralType");

        ali = address(new Guy(collateralAuctionHouse, FixedDiscountCollateralAuctionHouse(address(0)), IncreasingDiscountCollateralAuctionHouse(address(0))));
        bob = address(new Guy(collateralAuctionHouse, FixedDiscountCollateralAuctionHouse(address(0)), IncreasingDiscountCollateralAuctionHouse(address(0))));
        auctionIncomeRecipient = address(new Gal());

        Guy(ali).approveSAFEModification("english", address(collateralAuctionHouse));
        Guy(bob).approveSAFEModification("english", address(collateralAuctionHouse));
        safeEngine.approveSAFEModification(address(collateralAuctionHouse));

        safeEngine.modifyCollateralBalance("collateralType", address(this), 1000 ether);
        safeEngine.mint(ali, 200 ether);
        safeEngine.mint(bob, 200 ether);
    }

    function rad(uint wad) internal pure returns (uint z) {
        z = wad * 10 ** 27;
    }

    function test_startAuction() public {
        collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                            , amountToRaise: 50 ether
                                            , forgoneCollateralReceiver: safeAuctioned
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
                                                     , forgoneCollateralReceiver: safeAuctioned
                                                     , auctionIncomeRecipient: auctionIncomeRecipient
                                                     , initialBid: 0
                                                     });

        assertEq(safeEngine.coin_balance(ali), 200 ether);
        Guy(ali).increaseBidSize(id, 100 ether, 190 ether);
        assertEq(safeEngine.coin_balance(ali), 10 ether);
        Guy(ali).increaseBidSize(id, 100 ether, 200 ether);
        assertEq(safeEngine.coin_balance(ali), 0);
        Guy(ali).decreaseSoldAmount(id, 80 ether, 200 ether);
    }
    function test_increase_bid() public {
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).increaseBidSize(id, 100 ether, 1 ether);
        // initialBid taken from bidder
        assertEq(safeEngine.coin_balance(ali),   199 ether);
        // auctionIncomeRecipient receives payment
        assertEq(safeEngine.coin_balance(auctionIncomeRecipient), 1 ether);

        Guy(bob).increaseBidSize(id, 100 ether, 2 ether);
        // initialBid taken from bidder
        assertEq(safeEngine.coin_balance(bob), 198 ether);
        // prev bidder refunded
        assertEq(safeEngine.coin_balance(ali), 200 ether);
        // auctionIncomeRecipient receives excess
        assertEq(safeEngine.coin_balance(auctionIncomeRecipient), 2 ether);

        hevm.warp(now + 5 hours);
        Guy(bob).settleAuction(id);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(1000 ether) - 50 ether);
        // bob gets the winnings
        assertEq(safeEngine.token_collateral_balance(bob), 100 ether);
    }
    function test_increase_bid_size_later() public {
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        hevm.warp(now + 5 hours);

        Guy(ali).increaseBidSize(id, 100 ether, 1 ether);
        // initialBid taken from bidder
        assertEq(safeEngine.coin_balance(ali), 199 ether);
        // auctionIncomeRecipient receives payment
        assertEq(safeEngine.coin_balance(auctionIncomeRecipient),   1 ether);
    }
    function test_decrease_sold() public {
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        Guy(ali).increaseBidSize(id, 100 ether,  1 ether);
        Guy(bob).increaseBidSize(id, 100 ether, 50 ether);

        Guy(ali).decreaseSoldAmount(id,  95 ether, 50 ether);

        assertEq(safeEngine.token_collateral_balance(address(0xacab)), 5 ether);
        assertEq(safeEngine.coin_balance(ali),  150 ether);
        assertEq(safeEngine.coin_balance(bob),  200 ether);
    }
    function test_increase_bid_size() public {
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: safeAuctioned
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
                                                      , forgoneCollateralReceiver: safeAuctioned
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
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        // or after end
        hevm.warp(now + 44 hours);
        Guy(ali).increaseBidSize(ie, 100 ether, 1 ether);
        assertTrue(!Guy(bob).try_settleAuction(ie));
        hevm.warp(now + 1 days);
        assertTrue( Guy(bob).try_settleAuction(ie));

        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(1000 ether) - 100 ether);
    }
    function test_restart_auction() public {
        // start an auction
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: safeAuctioned
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

        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(1000 ether));
    }
    function test_no_deal_after_end() public {
        // if there are no bids and the auction ends, then it should not
        // be refundable to the creator. Rather, it restarts indefinitely.
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: safeAuctioned
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
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).increaseBidSize(id, 100 ether, 1 ether);
        // initialBid taken from bidder
        assertEq(safeEngine.coin_balance(ali),   199 ether);
        assertEq(safeEngine.coin_balance(auctionIncomeRecipient), 1 ether);

        safeEngine.mint(address(this), 1 ether);
        collateralAuctionHouse.terminateAuctionPrematurely(id);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(1000 ether) - 50 ether);

        // initialBid is refunded to bidder from caller
        assertEq(safeEngine.coin_balance(ali),            200 ether);
        assertEq(safeEngine.coin_balance(address(this)),    0 ether);
        // collateralType go to caller
        assertEq(safeEngine.token_collateral_balance(address(this)), 1000 ether);
    }
    function test_terminate_prematurely_decrease_sold() public {
        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                                      , amountToRaise: 50 ether
                                                      , forgoneCollateralReceiver: safeAuctioned
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

    DummyLiquidationEngine liquidationEngine;
    SAFEEngine_ safeEngine;
    FixedDiscountCollateralAuctionHouse collateralAuctionHouse;
    OracleRelayer oracleRelayer;
    Feed    collateralFSM;
    Feed    collateralMedian;
    Feed    systemCoinMedian;

    address ali;
    address bob;
    address auctionIncomeRecipient;
    address safeAuctioned = address(0xacab);

    uint constant WAD = 10 ** 18;
    uint constant RAY = 10 ** 27;
    uint constant RAD = 10 ** 45;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine = new SAFEEngine_();

        safeEngine.initializeCollateralType("collateralType");
        safeEngine.set_collateral_type("collateralType");

        liquidationEngine = new DummyLiquidationEngine(rad(1000 ether));
        collateralAuctionHouse = new FixedDiscountCollateralAuctionHouse(address(safeEngine), address(liquidationEngine), "collateralType");

        oracleRelayer = new OracleRelayer(address(safeEngine));
        oracleRelayer.modifyParameters("redemptionPrice", 5 * RAY);
        collateralAuctionHouse.modifyParameters("oracleRelayer", address(oracleRelayer));

        collateralFSM = new Feed(bytes32(uint256(0)), true);
        collateralAuctionHouse.modifyParameters("collateralFSM", address(collateralFSM));

        collateralMedian = new Feed(bytes32(uint256(0)), true);
        systemCoinMedian = new Feed(bytes32(uint256(0)), true);

        collateralFSM.set_price_source(address(collateralMedian));

        ali = address(new Guy(EnglishCollateralAuctionHouse(address(0)), collateralAuctionHouse, IncreasingDiscountCollateralAuctionHouse(address(0))));
        bob = address(new Guy(EnglishCollateralAuctionHouse(address(0)), collateralAuctionHouse, IncreasingDiscountCollateralAuctionHouse(address(0))));
        auctionIncomeRecipient = address(new Gal());

        Guy(ali).approveSAFEModification("fixed", address(collateralAuctionHouse));
        Guy(bob).approveSAFEModification("fixed", address(collateralAuctionHouse));
        safeEngine.approveSAFEModification(address(collateralAuctionHouse));

        safeEngine.modifyCollateralBalance("collateralType", address(this), 1000 ether);
        safeEngine.mint(ali, 200 ether);
        safeEngine.mint(bob, 200 ether);
    }

    // --- Math ---
    function rad(uint wad) internal pure returns (uint z) {
        z = wad * 10 ** 27;
    }
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
        require(y > 0, "division-by-zero");
        z = multiply(x, RAY) / y;
    }
    function wdivide(uint x, uint y) internal pure returns (uint z) {
        require(y > 0, "division-by-zero");
        z = multiply(x, WAD) / y;
    }

    function test_modifyParameters() public {
        collateralAuctionHouse.modifyParameters("discount", 0.90E18);
        collateralAuctionHouse.modifyParameters("minimumBid", 50 * WAD);
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
        assertEq(uint(collateralAuctionHouse.totalAuctionLength()), uint(uint48(-1)));
    }
    function testFail_set_partially_implemented_collateralFSM() public {
        PartiallyImplementedFeed partiallyImplementedCollateralFSM = new PartiallyImplementedFeed(bytes32(uint256(0)), true);
        collateralAuctionHouse.modifyParameters("collateralFSM", address(partiallyImplementedCollateralFSM));
    }
    function testFail_no_discount() public {
        collateralAuctionHouse.modifyParameters("discount", 1 ether);
    }
    function test_getSystemCoinFloorDeviatedPrice() public {
        collateralAuctionHouse.modifyParameters("minSystemCoinMedianDeviation", 0.90E18);

        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 1E18);
        assertEq(collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice()), oracleRelayer.redemptionPrice());

        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        assertEq(collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice()), oracleRelayer.redemptionPrice());

        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.90E18);
        assertEq(collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice()), 4.5E27);

        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.89E18);
        assertEq(collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice()), 4.45E27);
    }
    function test_getSystemCoinCeilingDeviatedPrice() public {
        collateralAuctionHouse.modifyParameters("minSystemCoinMedianDeviation", 0.90E18);

        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 1E18);
        assertEq(collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice()), oracleRelayer.redemptionPrice());

        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.95E18);
        assertEq(collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice()), oracleRelayer.redemptionPrice());

        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
        assertEq(collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice()), 5.5E27);

        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.89E18);
        assertEq(collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice()), 5.55E27);
    }
    function test_startAuction() public {
        collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                            , amountToRaise: 50 * RAD
                                            , forgoneCollateralReceiver: safeAuctioned
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
                                            , forgoneCollateralReceiver: safeAuctioned
                                            , auctionIncomeRecipient: auctionIncomeRecipient
                                            , initialBid: 0
                                            });
        // can't buy collateral on non-existent
        collateralAuctionHouse.buyCollateral(1, 0);
    }
    function testFail_faulty_collateral_fsm_price() public {
        Feed faultyFeed = new Feed(bytes32(uint256(1)), false);
        collateralAuctionHouse.modifyParameters("collateralFSM", address(faultyFeed));
        collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                            , amountToRaise: 50 * RAD
                                            , forgoneCollateralReceiver: safeAuctioned
                                            , auctionIncomeRecipient: auctionIncomeRecipient
                                            , initialBid: 0
                                            });
        collateralAuctionHouse.buyCollateral(1, 5 * WAD);
    }
    function test_buy_some_collateral() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 25 * WAD);
        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 131578947368421052);

        assertTrue(canBidThisAmount);
        assertEq(adjustedBid, 25 * WAD);
        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_buy_all_collateral() public {
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        assertEq(collateralAuctionHouse.getDiscountedCollateralPrice(200 ether, 0, oracleRelayer.redemptionPrice(), 0.95E18), 95 ether);

        (uint collateralBought, uint collateralBoughtAdjustedBid) =
          collateralAuctionHouse.getCollateralBought(id, 50 * WAD);

        assertEq(collateralBought, 526315789473684210);
        assertEq(collateralBoughtAdjustedBid, 50 * WAD);

        (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 50 * WAD);
        Guy(ali).buyCollateral(id, 50 * WAD);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(950 ether));

        (uint256 raisedAmount, uint256 soldAmount, uint256 amountToSell, uint256 amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertTrue(canBidThisAmount);
        assertEq(adjustedBid, 50 * WAD);
        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 526315789473684210);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 1 ether - 526315789473684210);
    }
    function testFail_start_tiny_collateral_auction() public {
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100
                                                      , amountToRaise: 50
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
    }
    function test_buyCollateral_small_market_price() public {
        collateralFSM.set_val(0.01 ether);
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        (uint256 colMedianPrice, bool colMedianValidity) = collateralMedian.getResultWithValidity();
        assertEq(colMedianPrice, 0);
        assertTrue(colMedianValidity);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 5 * WAD);
        Guy(ali).buyCollateral(id, 5 * WAD);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(950 ether));

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertTrue(canBidThisAmount);
        assertEq(adjustedBid, 5 * WAD);
        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 5 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
    }
    function test_buyCollateral_small_redemption_price() public {
        oracleRelayer.modifyParameters("redemptionPrice", 0.01E27);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 50 * WAD);
        Guy(ali).buyCollateral(id, 50 * WAD);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(950 ether));

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertTrue(canBidThisAmount);
        assertEq(adjustedBid, 50 * WAD);
        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 2631578947368421);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 1 ether - 2631578947368421);
    }
    function test_precision_loss_buy_all() public {
        oracleRelayer.modifyParameters("redemptionPrice", 2.015E27);
        collateralFSM.set_val(400 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 0.5 ether
                                                      , amountToRaise: 99999999999999999999999999999999999999999999999
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 100 * WAD);
        Guy(ali).buyCollateral(id, 100 * WAD);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 900000000000000000000000000000000000000000000001);

        (uint256 raisedAmount, uint256 soldAmount, uint256 amountToSell, uint256 amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertTrue(canBidThisAmount);
        assertEq(adjustedBid, 100 * WAD);
        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 100000000000000000000000000000000000000000000000);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 0.5 ether);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
    }
    function test_buyCollateral_insignificant_leftover_to_raise() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 51 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 50.99E18);
        (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 50E18);
        Guy(ali).buyCollateral(id, 50E18);

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertTrue(canBidThisAmount);
        assertEq(adjustedBid, 0.01E18 + 1);
        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 51 * RAD + RAY);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 268421052631578946);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 1 ether - 268421052631578946);
    }
    function test_buyCollateral_correctly_update_current_debt_being_auctioned() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 51000000000000000000000000000000000000000001234
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 1000E45);
        Guy(ali).buyCollateral(id, 50.99999999999999912E18);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 949000000000000000880000000000000000000000000000);
        Guy(ali).buyCollateral(id, 50E18);

        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 948999999999999999999999999999999999999999998766);

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 51000000000000000001000000000000000000000000000);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 268421052631578946);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 1 ether - 268421052631578946);
    }
    function test_buyCollateral_liquidation_starts_with_zero_on_auction() public {
        liquidationEngine = new DummyLiquidationEngine(51000000000000000000000000000000000000000001234);
        collateralAuctionHouse.modifyParameters("liquidationEngine", address(liquidationEngine));

        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 51000000000000000000000000000000000000000001234
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 51000000000000000000000000000000000000000001234);
        Guy(ali).buyCollateral(id, 50.99999999999999912E18);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 880000000000000000000000001234);
        Guy(ali).buyCollateral(id, 50E18);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 0);

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 51000000000000000001000000000000000000000000000);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 268421052631578946);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 1 ether - 268421052631578946);
    }
    function test_buyCollateral_small_market_price_insignificant_leftover_to_raise() public {
        collateralFSM.set_val(0.01 ether);
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        (uint256 colMedianPrice, bool colMedianValidity) = collateralMedian.getResultWithValidity();
        assertEq(colMedianPrice, 0);
        assertTrue(colMedianValidity);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 51 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 50.9E18);
        Guy(ali).buyCollateral(id, 50.9E18);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(949 ether));

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertTrue(canBidThisAmount);
        assertEq(adjustedBid, 50.9E18);
        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50.9E45);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
    }
    function test_big_discount_buy() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralAuctionHouse.modifyParameters("discount", 0.10E18);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        Guy(ali).buyCollateral(id, 50 * WAD);

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1000000000000000000);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
    }
    function test_small_discount_buy() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralAuctionHouse.modifyParameters("discount", 0.99E18);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        Guy(ali).buyCollateral(id, 50 * WAD);

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 252525252525252525);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 1 ether - 252525252525252525);
    }
    function test_collateral_median_and_collateral_fsm_equal() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 131578947368421052);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_collateral_median_higher_than_collateral_fsm_floor() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(181 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 145391102064553649);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 145391102064553649);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 145391102064553649);
    }
    function test_collateral_median_lower_than_collateral_fsm_ceiling() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(209 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 125912868295139763);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 125912868295139763);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 125912868295139763);
    }
    function test_collateral_median_higher_than_collateral_fsm_ceiling() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(500 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 125313283208020050);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 125313283208020050);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 125313283208020050);
    }
    function test_collateral_median_lower_than_collateral_fsm_floor() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(1 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 146198830409356725);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 146198830409356725);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 146198830409356725);
    }
    function test_collateral_median_lower_than_collateral_fsm_buy_all() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(1 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 50 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 292397660818713450);
    }
    function test_collateral_median_reverts() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        RevertableMedian revertMedian = new RevertableMedian();
        collateralFSM.set_price_source(address(revertMedian));
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 131578947368421052);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_system_coin_median_and_redemption_equal() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(1 ether);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 131578947368421052);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_system_coin_median_higher_than_redemption_floor() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(0.975E18);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 128289473684210526);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 128289473684210526);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 128289473684210526);
    }
    function test_system_coin_median_lower_than_redemption_ceiling() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(1.05E18);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 138157894736842105);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 138157894736842105);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 138157894736842105);
    }
    function test_system_coin_median_higher_than_redemption_ceiling() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(1.15E18);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 144736842105263157);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 144736842105263157);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 144736842105263157);
    }
    function test_system_coin_median_lower_than_redemption_floor() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(0.90E18);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 125000000000000000);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 125000000000000000);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 125000000000000000);
    }
    function test_system_coin_median_lower_than_redemption_buy_all() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(0.90E18);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 50 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 250000000000000000);
    }
    function test_system_coin_median_reverts() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        RevertableMedian revertMedian = new RevertableMedian();

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(revertMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 131578947368421052);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_system_coin_lower_collateral_median_higher() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        systemCoinMedian.set_val(0.90E18);

        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(220 ether);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 119047619047619047);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 119047619047619047);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 119047619047619047);
    }
    function test_system_coin_higher_collateral_median_lower() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        systemCoinMedian.set_val(1.10E18);

        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(180 ether);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 160818713450292397);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 160818713450292397);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 160818713450292397);
    }
    function test_system_coin_lower_collateral_median_lower() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        systemCoinMedian.set_val(0.90E18);

        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(180 ether);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 138888888888888888);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 138888888888888888);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 138888888888888888);
    }
    function test_system_coin_higher_collateral_median_higher() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        systemCoinMedian.set_val(1.10E18);

        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(210 ether);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 137844611528822055);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 137844611528822055);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 137844611528822055);
    }
    function test_min_system_coin_deviation_exceeds_lower_deviation() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(0.95E18);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("minSystemCoinMedianDeviation", 0.94E18);
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 131578947368421052);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_min_system_coin_deviation_exceeds_higher_deviation() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(1.05E18);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("minSystemCoinMedianDeviation", 0.89E18);
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 25 * RAD);
        assertEq(soldAmount, 131578947368421052);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_consecutive_small_bids() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        for (uint i = 0; i < 10; i++) {
          Guy(ali).buyCollateral(id, 5 * WAD);
        }

        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(950 ether));

        (uint256 raisedAmount, uint256 soldAmount, , , , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether - 736842105263157900);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 1 ether - 263157894736842100);
    }
    function test_settle_auction() public {
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        hevm.warp(now + collateralAuctionHouse.totalAuctionLength() + 1);
        collateralAuctionHouse.settleAuction(id);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(1000 ether));

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 1 ether);
        assertEq(amountToRaise, 50 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
    }
    function testFail_terminate_inexistent() public {
        collateralAuctionHouse.terminateAuctionPrematurely(1);
    }
    function test_terminateAuctionPrematurely() public {
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral(id, 25 * WAD);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(975 ether));
        collateralAuctionHouse.terminateAuctionPrematurely(1);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(950 ether));

        (uint raisedAmount, uint soldAmount, uint amountToSell, uint amountToRaise, , , ) = collateralAuctionHouse.bids(id);
        assertEq(raisedAmount, 0);
        assertEq(soldAmount, 0);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(this)), 999736842105263157895);
        assertEq(addition(999736842105263157895, 263157894736842105), 1000 ether);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 263157894736842105);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
    }
}

contract IncreasingDiscountCollateralAuctionHouseTest is DSTest {
    Hevm hevm;

    DummyLiquidationEngine liquidationEngine;
    SAFEEngine_ safeEngine;
    IncreasingDiscountCollateralAuctionHouse collateralAuctionHouse;
    OracleRelayer oracleRelayer;
    Feed    collateralFSM;
    Feed    collateralMedian;
    Feed    systemCoinMedian;

    address ali;
    address bob;
    address auctionIncomeRecipient;
    address safeAuctioned = address(0xacab);

    uint constant WAD = 10 ** 18;
    uint constant RAY = 10 ** 27;
    uint constant RAD = 10 ** 45;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine = new SAFEEngine_();

        safeEngine.initializeCollateralType("collateralType");
        safeEngine.set_collateral_type("collateralType");

        liquidationEngine = new DummyLiquidationEngine(rad(1000 ether));
        collateralAuctionHouse = new IncreasingDiscountCollateralAuctionHouse(address(safeEngine), address(liquidationEngine), "collateralType");

        oracleRelayer = new OracleRelayer(address(safeEngine));
        oracleRelayer.modifyParameters("redemptionPrice", 5 * RAY);
        collateralAuctionHouse.modifyParameters("oracleRelayer", address(oracleRelayer));

        collateralFSM = new Feed(bytes32(uint256(0)), true);
        collateralAuctionHouse.modifyParameters("collateralFSM", address(collateralFSM));

        collateralMedian = new Feed(bytes32(uint256(0)), true);
        systemCoinMedian = new Feed(bytes32(uint256(0)), true);

        collateralFSM.set_price_source(address(collateralMedian));

        ali = address(new Guy(EnglishCollateralAuctionHouse(address(0)), FixedDiscountCollateralAuctionHouse(address(0)), collateralAuctionHouse));
        bob = address(new Guy(EnglishCollateralAuctionHouse(address(0)), FixedDiscountCollateralAuctionHouse(address(0)), collateralAuctionHouse));
        auctionIncomeRecipient = address(new Gal());

        Guy(ali).approveSAFEModification("increasing", address(collateralAuctionHouse));
        Guy(bob).approveSAFEModification("increasing", address(collateralAuctionHouse));
        safeEngine.approveSAFEModification(address(collateralAuctionHouse));

        safeEngine.modifyCollateralBalance("collateralType", address(this), 1000 ether);
        safeEngine.mint(ali, 200 ether);
        safeEngine.mint(bob, 200 ether);
    }

    // --- Math ---
    function rad(uint wad) internal pure returns (uint z) {
        z = wad * 10 ** 27;
    }
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
        require(y > 0, "division-by-zero");
        z = multiply(x, RAY) / y;
    }
    function wdivide(uint x, uint y) internal pure returns (uint z) {
        require(y > 0, "division-by-zero");
        z = multiply(x, WAD) / y;
    }

    // General tests
    function test_modifyParameters() public {
        collateralAuctionHouse.modifyParameters("maxDiscount", 0.90E18);
        collateralAuctionHouse.modifyParameters("minDiscount", 0.91E18);
        collateralAuctionHouse.modifyParameters("minimumBid", 100 * WAD);
        collateralAuctionHouse.modifyParameters("perSecondDiscountUpdateRate", RAY - 100);
        collateralAuctionHouse.modifyParameters("maxDiscountUpdateRateTimeline", uint256(uint48(-1)) - now - 1);
        collateralAuctionHouse.modifyParameters("lowerCollateralMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperCollateralMedianDeviation", 0.90E18);
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        assertEq(collateralAuctionHouse.minDiscount(), 0.91E18);
        assertEq(collateralAuctionHouse.maxDiscount(), 0.90E18);
        assertEq(collateralAuctionHouse.lowerCollateralMedianDeviation(), 0.95E18);
        assertEq(collateralAuctionHouse.upperCollateralMedianDeviation(), 0.90E18);
        assertEq(collateralAuctionHouse.lowerSystemCoinMedianDeviation(), 0.95E18);
        assertEq(collateralAuctionHouse.upperSystemCoinMedianDeviation(), 0.90E18);
        assertEq(collateralAuctionHouse.perSecondDiscountUpdateRate(), RAY - 100);
        assertEq(collateralAuctionHouse.maxDiscountUpdateRateTimeline(), uint256(uint48(-1)) - now - 1);
        assertEq(collateralAuctionHouse.minimumBid(), 100 * WAD);
        assertEq(uint(collateralAuctionHouse.totalAuctionLength()), uint(uint48(-1)));
    }
    function testFail_set_partially_implemented_collateralFSM() public {
        PartiallyImplementedFeed partiallyImplementedCollateralFSM = new PartiallyImplementedFeed(bytes32(uint256(0)), true);
        collateralAuctionHouse.modifyParameters("collateralFSM", address(partiallyImplementedCollateralFSM));
    }
    function testFail_no_min_discount() public {
        collateralAuctionHouse.modifyParameters("minDiscount", 1 ether);
    }
    function testFail_max_discount_lower_than_min() public {
        collateralAuctionHouse.modifyParameters("maxDiscount", 1 ether - 1);
    }
    function test_getSystemCoinFloorDeviatedPrice() public {
        collateralAuctionHouse.modifyParameters("minSystemCoinMedianDeviation", 0.90E18);

        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 1E18);
        assertEq(collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice()), oracleRelayer.redemptionPrice());

        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        assertEq(collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice()), oracleRelayer.redemptionPrice());

        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.90E18);
        assertEq(collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice()), 4.5E27);

        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.89E18);
        assertEq(collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice()), 4.45E27);
    }
    function test_getSystemCoinCeilingDeviatedPrice() public {
        collateralAuctionHouse.modifyParameters("minSystemCoinMedianDeviation", 0.90E18);

        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 1E18);
        assertEq(collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice()), oracleRelayer.redemptionPrice());

        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.95E18);
        assertEq(collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice()), oracleRelayer.redemptionPrice());

        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
        assertEq(collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice()), 5.5E27);

        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.89E18);
        assertEq(collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice()), 5.55E27);
    }
    function test_startAuction() public {
        collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                            , amountToRaise: 50 * RAD
                                            , forgoneCollateralReceiver: safeAuctioned
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
                                            , forgoneCollateralReceiver: safeAuctioned
                                            , auctionIncomeRecipient: auctionIncomeRecipient
                                            , initialBid: 0
                                            });
        // can't buy collateral on non-existent
        collateralAuctionHouse.buyCollateral(1, 0);
    }
    function testFail_faulty_collateral_fsm_price() public {
        Feed faultyFeed = new Feed(bytes32(uint256(1)), false);
        collateralAuctionHouse.modifyParameters("collateralFSM", address(faultyFeed));
        collateralAuctionHouse.startAuction({ amountToSell: 100 ether
                                            , amountToRaise: 50 * RAD
                                            , forgoneCollateralReceiver: safeAuctioned
                                            , auctionIncomeRecipient: auctionIncomeRecipient
                                            , initialBid: 0
                                            });
        collateralAuctionHouse.buyCollateral(1, 5 * WAD);
    }

    // Tests with a setup that's similar to a fixed discount auction
    function test_buy_some_collateral() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 25 * WAD);
        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(975 ether));

        ( uint256 amountToSell,
          uint256 amountToRaise,
          uint256 currentDiscount,
          uint256 maxDiscount,
          uint256 perSecondDiscountUpdateRate,
          uint256 latestDiscountUpdateTime,
          uint48  discountIncreaseDeadline,
          address forgoneCollateralReceiver,
          address incomeRecipient
        ) = collateralAuctionHouse.bids(id);

        assertEq(amountToRaise, 25 * RAD);
        assertEq(amountToSell, 1 ether - 131578947368421052);
        assertEq(currentDiscount, collateralAuctionHouse.minDiscount());
        assertEq(maxDiscount, collateralAuctionHouse.maxDiscount());
        assertEq(perSecondDiscountUpdateRate, collateralAuctionHouse.perSecondDiscountUpdateRate());
        assertEq(latestDiscountUpdateTime, now);
        assertEq(discountIncreaseDeadline, now + collateralAuctionHouse.maxDiscountUpdateRateTimeline());
        assertEq(forgoneCollateralReceiver, address(safeAuctioned));
        assertEq(incomeRecipient, auctionIncomeRecipient);

        assertTrue(canBidThisAmount);
        assertEq(adjustedBid, 25 * WAD);
        assertEq(safeEngine.coinBalance(incomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_buy_all_collateral() public {
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        assertEq(collateralAuctionHouse.getDiscountedCollateralPrice(200 ether, 0, oracleRelayer.redemptionPrice(), 0.95E18), 95 ether);

        (uint collateralBought, uint collateralBoughtAdjustedBid) =
          collateralAuctionHouse.getCollateralBought(id, 50 * WAD);

        assertEq(collateralBought, 526315789473684210);
        assertEq(collateralBoughtAdjustedBid, 50 * WAD);

        (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 50 * WAD);
        Guy(ali).buyCollateral_increasingDiscount(id, 50 * WAD);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(950 ether));

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertTrue(canBidThisAmount);
        assertEq(adjustedBid, 50 * WAD);
        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 526315789473684210);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 1 ether - 526315789473684210);
    }
    function testFail_start_tiny_collateral_auction() public {
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 100
                                                      , amountToRaise: 50
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
    }
    function test_buyCollateral_small_market_price() public {
        collateralFSM.set_val(0.01 ether);
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        (uint256 colMedianPrice, bool colMedianValidity) = collateralMedian.getResultWithValidity();
        assertEq(colMedianPrice, 0);
        assertTrue(colMedianValidity);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 5 * WAD);
        Guy(ali).buyCollateral_increasingDiscount(id, 5 * WAD);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(950 ether));

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertTrue(canBidThisAmount);
        assertEq(adjustedBid, 5 * WAD);
        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 5 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
    }
    function test_big_discount_buy() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralAuctionHouse.modifyParameters("maxDiscount", 0.10E18);
        collateralAuctionHouse.modifyParameters("minDiscount", 0.10E18);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        Guy(ali).buyCollateral_increasingDiscount(id, 50 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1000000000000000000);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
    }
    function test_small_discount_buy() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralAuctionHouse.modifyParameters("minDiscount", 0.99E18);
        collateralAuctionHouse.modifyParameters("maxDiscount", 0.99E18);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });
        Guy(ali).buyCollateral_increasingDiscount(id, 50 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 252525252525252525);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 1 ether - 252525252525252525);
    }
    function test_collateral_median_and_collateral_fsm_equal() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 131578947368421052);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_collateral_median_higher_than_collateral_fsm_floor() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(181 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 145391102064553649);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 145391102064553649);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 145391102064553649);
    }
    function test_collateral_median_lower_than_collateral_fsm_ceiling() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(209 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 125912868295139763);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 125912868295139763);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 125912868295139763);
    }
    function test_collateral_median_higher_than_collateral_fsm_ceiling() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(500 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 125313283208020050);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 125313283208020050);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 125313283208020050);
    }
    function test_collateral_median_lower_than_collateral_fsm_floor() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(1 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 146198830409356725);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 146198830409356725);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 146198830409356725);
    }
    function test_collateral_median_lower_than_collateral_fsm_buy_all() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(1 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 50 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 292397660818713450);
    }
    function test_collateral_median_reverts() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        RevertableMedian revertMedian = new RevertableMedian();
        collateralFSM.set_price_source(address(revertMedian));
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 131578947368421052);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_system_coin_median_and_redemption_equal() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(1 ether);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 131578947368421052);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_system_coin_median_higher_than_redemption_floor() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(0.975E18);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 128289473684210526);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 128289473684210526);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 128289473684210526);
    }
    function test_system_coin_median_lower_than_redemption_ceiling() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(1.05E18);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 138157894736842105);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 138157894736842105);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 138157894736842105);
    }
    function test_system_coin_median_higher_than_redemption_ceiling() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(1.15E18);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 144736842105263157);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 144736842105263157);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 144736842105263157);
    }
    function test_system_coin_median_lower_than_redemption_floor() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(0.90E18);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 125000000000000000);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 125000000000000000);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 125000000000000000);
    }
    function test_system_coin_median_lower_than_redemption_buy_all() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(0.90E18);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 50 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 250000000000000000);
    }
    function test_system_coin_median_reverts() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        RevertableMedian revertMedian = new RevertableMedian();

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(revertMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 131578947368421052);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_system_coin_lower_collateral_median_higher() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        systemCoinMedian.set_val(0.90E18);

        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(220 ether);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 119047619047619047);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 119047619047619047);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 119047619047619047);
    }
    function test_system_coin_higher_collateral_median_lower() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        systemCoinMedian.set_val(1.10E18);

        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(180 ether);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 160818713450292397);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 160818713450292397);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 160818713450292397);
    }
    function test_system_coin_lower_collateral_median_lower() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        systemCoinMedian.set_val(0.90E18);

        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(180 ether);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 138888888888888888);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 138888888888888888);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 138888888888888888);
    }
    function test_system_coin_higher_collateral_median_higher() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        systemCoinMedian.set_val(1.10E18);

        collateralFSM.set_val(200 ether);
        collateralMedian.set_val(210 ether);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 137844611528822055);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 137844611528822055);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 137844611528822055);
    }
    function test_min_system_coin_deviation_exceeds_lower_deviation() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(0.95E18);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("minSystemCoinMedianDeviation", 0.94E18);
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 131578947368421052);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_min_system_coin_deviation_exceeds_higher_deviation() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        systemCoinMedian.set_val(1.05E18);

        collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
        collateralAuctionHouse.modifyParameters("minSystemCoinMedianDeviation", 0.89E18);
        collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
        collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);

        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether - 131578947368421052);
        assertEq(amountToRaise, 25 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
    }
    function test_consecutive_small_bids() public {
        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        for (uint i = 0; i < 10; i++) {
          Guy(ali).buyCollateral_increasingDiscount(id, 5 * WAD);
        }

        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(950 ether));

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether - 736842105263157900);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 1 ether - 263157894736842100);
    }
    function test_settle_auction() public {
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        hevm.warp(now + collateralAuctionHouse.totalAuctionLength() + 1);
        collateralAuctionHouse.settleAuction(id);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(1000 ether));

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 1 ether);
        assertEq(amountToRaise, 50 * RAD);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
    }
    function testFail_terminate_inexistent() public {
        collateralAuctionHouse.terminateAuctionPrematurely(1);
    }
    function test_terminateAuctionPrematurely() public {
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(975 ether));
        collateralAuctionHouse.terminateAuctionPrematurely(1);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(950 ether));

        ( uint256 amountToSell,
          uint256 amountToRaise,
          ,
          ,
          ,
          ,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(this)), 999736842105263157895);
        assertEq(addition(999736842105263157895, 263157894736842105), 1000 ether);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 263157894736842105);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
    }

    // Custom tests for the increasing discount implementation
    function test_small_discount_change_rate_bid_right_away() public {
        collateralAuctionHouse.modifyParameters("perSecondDiscountUpdateRate", 999998607628240588157433861); // -0.5% per hour
        collateralAuctionHouse.modifyParameters("maxDiscount", 0.93E18);

        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        Guy(ali).buyCollateral_increasingDiscount(id, 49 * WAD);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(951 ether));

        ( uint256 amountToSell,
          uint256 amountToRaise,
          uint256 currentDiscount,
          ,
          uint256 perSecondDiscountUpdateRate,
          uint256 latestDiscountUpdateTime,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 742105263157894737);
        assertEq(amountToRaise, RAY * WAD);
        assertEq(currentDiscount, collateralAuctionHouse.minDiscount());
        assertEq(perSecondDiscountUpdateRate, 999998607628240588157433861);
        assertEq(latestDiscountUpdateTime, now);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 49 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 742105263157894737);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether - 742105263157894737);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
    }
    function test_small_discount_change_rate_bid_after_half_rate_timeline() public {
        collateralAuctionHouse.modifyParameters("perSecondDiscountUpdateRate", 999998607628240588157433861); // -0.5% per hour
        collateralAuctionHouse.modifyParameters("maxDiscount", 0.93E18);

        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        hevm.warp(now + 30 minutes);
        Guy(ali).buyCollateral_increasingDiscount(id, 49 * WAD);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(951 ether));

        ( uint256 amountToSell,
          uint256 amountToRaise,
          uint256 currentDiscount,
          ,
          uint256 perSecondDiscountUpdateRate,
          uint256 latestDiscountUpdateTime,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 741458098434345369);
        assertEq(amountToRaise, RAY * WAD);
        assertEq(currentDiscount, 947622023804850158);
        assertEq(perSecondDiscountUpdateRate, 999998607628240588157433861);
        assertEq(latestDiscountUpdateTime, now);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 49 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 741458098434345369);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether - 741458098434345369);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
    }
    function test_small_discount_change_rate_bid_end_rate_timeline() public {
        collateralAuctionHouse.modifyParameters("perSecondDiscountUpdateRate", 999998607628240588157433861); // -0.5% per hour
        collateralAuctionHouse.modifyParameters("maxDiscount", 0.93E18);

        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        hevm.warp(now + 1 hours);
        Guy(ali).buyCollateral_increasingDiscount(id, 49 * WAD);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(951 ether));

        ( uint256 amountToSell,
          uint256 amountToRaise,
          uint256 currentDiscount,
          ,
          uint256 perSecondDiscountUpdateRate,
          uint256 latestDiscountUpdateTime,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 736559139784946237);
        assertEq(amountToRaise, RAY * WAD);
        assertEq(currentDiscount, 930000000000000000);
        assertEq(perSecondDiscountUpdateRate, 999998607628240588157433861);
        assertEq(latestDiscountUpdateTime, now);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 49 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 736559139784946237);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether - 736559139784946237);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
    }
    function test_small_discount_change_rate_bid_long_after_rate_timeline() public {
        collateralAuctionHouse.modifyParameters("perSecondDiscountUpdateRate", 999998607628240588157433861); // -0.5% per hour
        collateralAuctionHouse.modifyParameters("maxDiscount", 0.93E18);

        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        hevm.warp(now + 3650 days);
        Guy(ali).buyCollateral_increasingDiscount(id, 49 * WAD);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(951 ether));

        ( uint256 amountToSell,
          uint256 amountToRaise,
          uint256 currentDiscount,
          ,
          uint256 perSecondDiscountUpdateRate,
          uint256 latestDiscountUpdateTime,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 736559139784946237);
        assertEq(amountToRaise, RAY * WAD);
        assertEq(currentDiscount, 930000000000000000);
        assertEq(perSecondDiscountUpdateRate, 999998607628240588157433861);
        assertEq(latestDiscountUpdateTime, now);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 49 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 736559139784946237);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether - 736559139784946237);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
    }
    function test_bid_multi_times_at_different_timestamps() public {
        collateralAuctionHouse.modifyParameters("perSecondDiscountUpdateRate", 999998607628240588157433861); // -0.5% per hour
        collateralAuctionHouse.modifyParameters("maxDiscount", 0.93E18);

        oracleRelayer.modifyParameters("redemptionPrice", RAY);
        collateralFSM.set_val(200 ether);
        safeEngine.mint(ali, 200 * RAD - 200 ether);

        uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));

        uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
                                                      , amountToRaise: 50 * RAD
                                                      , forgoneCollateralReceiver: safeAuctioned
                                                      , auctionIncomeRecipient: auctionIncomeRecipient
                                                      , initialBid: 0
                                                      });

        for (uint i = 0; i < 10; i++) {
          hevm.warp(now + 1 minutes);
          Guy(ali).buyCollateral_increasingDiscount(id, 5 * WAD);
        }

        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(950 ether));

        ( uint256 amountToSell,
          uint256 amountToRaise,
          uint256 currentDiscount,
          ,
          uint256 perSecondDiscountUpdateRate,
          uint256 latestDiscountUpdateTime,
          ,
          ,
        ) = collateralAuctionHouse.bids(id);
        assertEq(amountToSell, 0);
        assertEq(amountToRaise, 0);
        assertEq(currentDiscount, 0);
        assertEq(perSecondDiscountUpdateRate, 0);
        assertEq(latestDiscountUpdateTime, 0);

        assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
        assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
        assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether - 736721153320545015);
        assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 736721153320545015);
    }
}
