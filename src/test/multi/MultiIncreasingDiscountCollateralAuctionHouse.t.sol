// pragma solidity 0.6.7;
//
// import "ds-test/test.sol";
// import {DSDelegateToken} from "ds-token/delegate.sol";
//
// import {MultiSAFEEngine} from "../../multi/MultiSAFEEngine.sol";
// import {MultiIncreasingDiscountCollateralAuctionHouse} from "../../multi/MultiIncreasingDiscountCollateralAuctionHouse.sol";
// import {MultiOracleRelayer} from "../../multi/MultiOracleRelayer.sol";
//
// abstract contract Hevm {
//     function warp(uint256) virtual public;
// }
//
// contract Guy {
//     address safeEngine;
//
//     MultiIncreasingDiscountCollateralAuctionHouse increasingDiscountCollateralAuctionHouse;
//
//     constructor(
//       address safeEngine_,
//       MultiIncreasingDiscountCollateralAuctionHouse increasingDiscountCollateralAuctionHouse_
//     ) public {
//         increasingDiscountCollateralAuctionHouse = increasingDiscountCollateralAuctionHouse_;
//         safeEngine = safeEngine_;
//     }
//     function approveSAFEModification(bytes32 coinName, address safe) public {
//         safeEngine = address(increasingDiscountCollateralAuctionHouse.safeEngine());
//         MultiSAFEEngine(safeEngine).approveSAFEModification(coinName, safe);
//     }
//     function buyCollateral_increasingDiscount(uint id, uint wad) public {
//         increasingDiscountCollateralAuctionHouse.buyCollateral(id, wad);
//     }
//     function try_buyCollateral_increasingDiscount(uint id, uint wad)
//         public returns (bool ok)
//     {
//         string memory sig = "buyCollateral(uint256,uint256)";
//         (ok,) = address(increasingDiscountCollateralAuctionHouse).call(abi.encodeWithSignature(sig, id, wad));
//     }
//     function try_increasingDiscount_terminateAuctionPrematurely(uint id)
//         public returns (bool ok)
//     {
//         string memory sig = "terminateAuctionPrematurely(uint256)";
//         (ok,) = address(increasingDiscountCollateralAuctionHouse).call(abi.encodeWithSignature(sig, id));
//     }
// }
//
// contract Gal {}
//
// contract MultiSAFEEngine_ is MultiSAFEEngine {
//     function mint(bytes32 coinName, address usr, uint wad) public {
//         coinBalance[coinName][usr] += wad;
//     }
//     function coin_balance(bytes32 coinName, address usr) public view returns (uint) {
//         return coinBalance[coinName][usr];
//     }
//     bytes32 collateralType;
//     function set_collateral_type(bytes32 collateralType_) public {
//         collateralType = collateralType_;
//     }
//     function token_collateral_balance(address usr) public view returns (uint) {
//         return tokenCollateral[collateralType][usr];
//     }
// }
//
// contract RevertableMedian {
//     function getResultWithValidity() external returns (bytes32, bool) {
//         revert();
//     }
// }
//
// contract Feed {
//     address public priceSource;
//     uint256 public priceFeedValue;
//     bool public hasValidValue;
//     constructor(bytes32 initPrice, bool initHas) public {
//         priceFeedValue = uint(initPrice);
//         hasValidValue = initHas;
//     }
//     function set_val(uint newPrice) external {
//         priceFeedValue = newPrice;
//     }
//     function set_price_source(address priceSource_) external {
//         priceSource = priceSource_;
//     }
//     function set_has(bool newHas) external {
//         hasValidValue = newHas;
//     }
//     function getResultWithValidity() external returns (uint256, bool) {
//         return (priceFeedValue, hasValidValue);
//     }
// }
//
// contract PartiallyImplementedFeed {
//     uint256 public priceFeedValue;
//     bool public hasValidValue;
//     constructor(bytes32 initPrice, bool initHas) public {
//         priceFeedValue = uint(initPrice);
//         hasValidValue = initHas;
//     }
//     function set_val(uint newPrice) external {
//         priceFeedValue = newPrice;
//     }
//     function set_has(bool newHas) external {
//         hasValidValue = newHas;
//     }
//     function getResultWithValidity() external returns (uint256, bool) {
//         return (priceFeedValue, hasValidValue);
//     }
// }
//
// contract DummyLiquidationEngine {
//     mapping(bytes32 => uint256) public currentOnAuctionSystemCoins;
//
//     constructor(bytes32 coinName, uint rad) public {
//         currentOnAuctionSystemCoins[coinName] = rad;
//     }
//
//     function subtract(uint x, uint y) internal pure returns (uint z) {
//         require((z = x - y) <= x);
//     }
//
//     function removeCoinsFromAuction(bytes32 coinName, bytes32 collateralType, uint rad) public {
//         currentOnAuctionSystemCoins[coinName] = subtract(currentOnAuctionSystemCoins[coinName], rad);
//     }
// }
//
// contract MultiIncreasingDiscountCollateralAuctionHouseTest is DSTest {
//     Hevm hevm;
//
//     DummyLiquidationEngine liquidationEngine;
//     MultiSAFEEngine_ safeEngine;
//     MultiIncreasingDiscountCollateralAuctionHouse collateralAuctionHouse;
//     MultiOracleRelayer oracleRelayer;
//     Feed    collateralFSM;
//     Feed    collateralMedian;
//     Feed    systemCoinMedian;
//
//     address ali;
//     address bob;
//     address auctionIncomeRecipient;
//     address safeAuctioned = address(0xacab);
//
//     bytes32 coinName = "MAI";
//
//     uint constant WAD = 10 ** 18;
//     uint constant RAY = 10 ** 27;
//     uint constant RAD = 10 ** 45;
//
//     function setUp() public {
//         hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
//         hevm.warp(604411200);
//
//         safeEngine = new MultiSAFEEngine_();
//
//         safeEngine.addCollateralJoin("collateralType", address(this));
//         safeEngine.initializeCoin(coinName, uint(-1));
//         safeEngine.initializeCollateralType(coinName, "collateralType");
//         safeEngine.set_collateral_type("collateralType");
//
//         liquidationEngine = new DummyLiquidationEngine(coinName, rad(1000 ether));
//
//         oracleRelayer = new MultiOracleRelayer(address(safeEngine));
//         oracleRelayer.initializeCoin(coinName, 5 * RAY, uint(-1), 1);
//
//         collateralAuctionHouse = new MultiIncreasingDiscountCollateralAuctionHouse(
//           address(safeEngine), address(liquidationEngine), coinName, "collateralType"
//         );
//         collateralAuctionHouse.modifyParameters("oracleRelayer", address(oracleRelayer));
//
//         collateralFSM = new Feed(bytes32(uint256(0)), true);
//         collateralAuctionHouse.modifyParameters("collateralFSM", address(collateralFSM));
//
//         collateralMedian = new Feed(bytes32(uint256(0)), true);
//         systemCoinMedian = new Feed(bytes32(uint256(0)), true);
//
//         collateralFSM.set_price_source(address(collateralMedian));
//
//         ali = address(new Guy(address(safeEngine), collateralAuctionHouse));
//         bob = address(new Guy(address(safeEngine), collateralAuctionHouse));
//         auctionIncomeRecipient = address(new Gal());
//
//         Guy(ali).approveSAFEModification(coinName, address(collateralAuctionHouse));
//         Guy(bob).approveSAFEModification(coinName, address(collateralAuctionHouse));
//         safeEngine.approveSAFEModification(coinName, address(collateralAuctionHouse));
//
//         safeEngine.modifyCollateralBalance("collateralType", address(this), 1000 ether);
//         safeEngine.mint(coinName, ali, 200 ether);
//         safeEngine.mint(coinName, bob, 200 ether);
//     }
//
//     // --- Math ---
//     function rad(uint wad) internal pure returns (uint z) {
//         z = wad * 10 ** 27;
//     }
//     function addition(uint x, uint y) internal pure returns (uint z) {
//         require((z = x + y) >= x);
//     }
//     function subtract(uint x, uint y) internal pure returns (uint z) {
//         require((z = x - y) <= x);
//     }
//     function multiply(uint x, uint y) internal pure returns (uint z) {
//         require(y == 0 || (z = x * y) / y == x);
//     }
//     function wmultiply(uint x, uint y) internal pure returns (uint z) {
//         z = multiply(x, y) / WAD;
//     }
//     function rdivide(uint x, uint y) internal pure returns (uint z) {
//         require(y > 0, "division-by-zero");
//         z = multiply(x, RAY) / y;
//     }
//     function wdivide(uint x, uint y) internal pure returns (uint z) {
//         require(y > 0, "division-by-zero");
//         z = multiply(x, WAD) / y;
//     }
//
//     // General tests
//     function test_modifyParameters() public {
//         collateralAuctionHouse.modifyParameters("maxDiscount", 0.90E18);
//         collateralAuctionHouse.modifyParameters("minDiscount", 0.91E18);
//         collateralAuctionHouse.modifyParameters("minimumBid", 100 * WAD);
//         collateralAuctionHouse.modifyParameters("perSecondDiscountUpdateRate", RAY - 100);
//         collateralAuctionHouse.modifyParameters("maxDiscountUpdateRateTimeline", uint256(uint48(-1)) - now - 1);
//         collateralAuctionHouse.modifyParameters("lowerCollateralMedianDeviation", 0.95E18);
//         collateralAuctionHouse.modifyParameters("upperCollateralMedianDeviation", 0.90E18);
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
//
//         assertEq(collateralAuctionHouse.minDiscount(), 0.91E18);
//         assertEq(collateralAuctionHouse.maxDiscount(), 0.90E18);
//         assertEq(collateralAuctionHouse.lowerCollateralMedianDeviation(), 0.95E18);
//         assertEq(collateralAuctionHouse.upperCollateralMedianDeviation(), 0.90E18);
//         assertEq(collateralAuctionHouse.lowerSystemCoinMedianDeviation(), 0.95E18);
//         assertEq(collateralAuctionHouse.upperSystemCoinMedianDeviation(), 0.90E18);
//         assertEq(collateralAuctionHouse.perSecondDiscountUpdateRate(), RAY - 100);
//         assertEq(collateralAuctionHouse.maxDiscountUpdateRateTimeline(), uint256(uint48(-1)) - now - 1);
//         assertEq(collateralAuctionHouse.minimumBid(), 100 * WAD);
//         assertEq(uint(collateralAuctionHouse.totalAuctionLength()), uint(uint48(-1)));
//     }
//     function testFail_set_partially_implemented_collateralFSM() public {
//         PartiallyImplementedFeed partiallyImplementedCollateralFSM = new PartiallyImplementedFeed(bytes32(uint256(0)), true);
//         collateralAuctionHouse.modifyParameters("collateralFSM", address(partiallyImplementedCollateralFSM));
//     }
//     function testFail_no_min_discount() public {
//         collateralAuctionHouse.modifyParameters("minDiscount", 1 ether);
//     }
//     function testFail_max_discount_lower_than_min() public {
//         collateralAuctionHouse.modifyParameters("maxDiscount", 1 ether - 1);
//     }
//     function test_getSystemCoinFloorDeviatedPrice() public {
//         collateralAuctionHouse.modifyParameters("minSystemCoinMedianDeviation", 0.90E18);
//
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 1E18);
//         assertEq(collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice(coinName)), oracleRelayer.redemptionPrice(coinName));
//
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
//         assertEq(collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice(coinName)), oracleRelayer.redemptionPrice(coinName));
//
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.90E18);
//         assertEq(collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice(coinName)), 4.5E27);
//
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.89E18);
//         assertEq(collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice(coinName)), 4.45E27);
//     }
//     function test_getSystemCoinCeilingDeviatedPrice() public {
//         collateralAuctionHouse.modifyParameters("minSystemCoinMedianDeviation", 0.90E18);
//
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 1E18);
//         assertEq(collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice(coinName)), oracleRelayer.redemptionPrice(coinName));
//
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.95E18);
//         assertEq(collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice(coinName)), oracleRelayer.redemptionPrice(coinName));
//
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
//         assertEq(collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice(coinName)), 5.5E27);
//
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.89E18);
//         assertEq(collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice(coinName)), 5.55E27);
//     }
//     function test_startAuction() public {
//         collateralAuctionHouse.startAuction({ amountToSell: 100 ether
//                                             , amountToRaise: 50 * RAD
//                                             , forgoneCollateralReceiver: safeAuctioned
//                                             , auctionIncomeRecipient: auctionIncomeRecipient
//                                             , initialBid: 0
//                                             });
//     }
//     function testFail_buyCollateral_inexistent_auction() public {
//         // can't buyCollateral on non-existent
//         collateralAuctionHouse.buyCollateral(42, 5 * WAD);
//     }
//     function testFail_buyCollateral_null_bid() public {
//         collateralAuctionHouse.startAuction({ amountToSell: 100 ether
//                                             , amountToRaise: 50 * RAD
//                                             , forgoneCollateralReceiver: safeAuctioned
//                                             , auctionIncomeRecipient: auctionIncomeRecipient
//                                             , initialBid: 0
//                                             });
//         // can't buy collateral on non-existent
//         collateralAuctionHouse.buyCollateral(1, 0);
//     }
//     function testFail_faulty_collateral_fsm_price() public {
//         Feed faultyFeed = new Feed(bytes32(uint256(1)), false);
//         collateralAuctionHouse.modifyParameters("collateralFSM", address(faultyFeed));
//         collateralAuctionHouse.startAuction({ amountToSell: 100 ether
//                                             , amountToRaise: 50 * RAD
//                                             , forgoneCollateralReceiver: safeAuctioned
//                                             , auctionIncomeRecipient: auctionIncomeRecipient
//                                             , initialBid: 0
//                                             });
//         collateralAuctionHouse.buyCollateral(1, 5 * WAD);
//     }
//
//     function test_buy_some_collateral() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 25 * WAD);
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//         assertEq(liquidationEngine.currentOnAuctionSystemCoins(coinName), rad(975 ether));
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           uint256 currentDiscount,
//           uint256 maxDiscount,
//           uint256 perSecondDiscountUpdateRate,
//           uint256 latestDiscountUpdateTime,
//           uint48  discountIncreaseDeadline,
//           address forgoneCollateralReceiver,
//           address incomeRecipient
//         ) = collateralAuctionHouse.bids(id);
//
//         assertEq(amountToRaise, 25 * RAD);
//         assertEq(amountToSell, 1 ether - 131578947368421052);
//         assertEq(currentDiscount, collateralAuctionHouse.minDiscount());
//         assertEq(maxDiscount, collateralAuctionHouse.maxDiscount());
//         assertEq(perSecondDiscountUpdateRate, collateralAuctionHouse.perSecondDiscountUpdateRate());
//         assertEq(latestDiscountUpdateTime, now);
//         assertEq(discountIncreaseDeadline, now + collateralAuctionHouse.maxDiscountUpdateRateTimeline());
//         assertEq(forgoneCollateralReceiver, address(safeAuctioned));
//         assertEq(incomeRecipient, auctionIncomeRecipient);
//
//         assertTrue(canBidThisAmount);
//         assertEq(adjustedBid, 25 * WAD);
//         assertEq(safeEngine.coinBalance(coinName, incomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
//     }
//     function test_buy_all_collateral() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", 2 * RAY);
//         collateralFSM.set_val(200 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         assertEq(collateralAuctionHouse.getDiscountedCollateralPrice(200 ether, 0, oracleRelayer.redemptionPrice(coinName), 0.95E18), 95 ether);
//
//         (uint collateralBought, uint collateralBoughtAdjustedBid) =
//           collateralAuctionHouse.getCollateralBought(id, 50 * WAD);
//
//         assertEq(collateralBought, 526315789473684210);
//         assertEq(collateralBoughtAdjustedBid, 50 * WAD);
//
//         (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 50 * WAD);
//         Guy(ali).buyCollateral_increasingDiscount(id, 50 * WAD);
//         assertEq(liquidationEngine.currentOnAuctionSystemCoins(coinName), rad(950 ether));
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 0);
//         assertEq(amountToRaise, 0);
//
//         assertTrue(canBidThisAmount);
//         assertEq(adjustedBid, 50 * WAD);
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 50 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 526315789473684210);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 1 ether - 526315789473684210);
//     }
//     function testFail_start_tiny_collateral_auction() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", 2 * RAY);
//         collateralFSM.set_val(200 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 100
//                                                       , amountToRaise: 50
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//     }
//     function test_buyCollateral_small_market_price() public {
//         collateralFSM.set_val(0.01 ether);
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", 2 * RAY);
//         (uint256 colMedianPrice, bool colMedianValidity) = collateralMedian.getResultWithValidity();
//         assertEq(colMedianPrice, 0);
//         assertTrue(colMedianValidity);
//
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 5 * WAD);
//         Guy(ali).buyCollateral_increasingDiscount(id, 5 * WAD);
//         assertEq(liquidationEngine.currentOnAuctionSystemCoins(coinName), rad(950 ether));
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 0);
//         assertEq(amountToRaise, 0);
//
//         assertTrue(canBidThisAmount);
//         assertEq(adjustedBid, 5 * WAD);
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 5 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
//     }
//     function test_big_discount_buy() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralAuctionHouse.modifyParameters("maxDiscount", 0.10E18);
//         collateralAuctionHouse.modifyParameters("minDiscount", 0.10E18);
//         collateralFSM.set_val(200 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//         Guy(ali).buyCollateral_increasingDiscount(id, 50 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 0);
//         assertEq(amountToRaise, 0);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 50 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1000000000000000000);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
//     }
//     function test_small_discount_buy() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralAuctionHouse.modifyParameters("minDiscount", 0.99E18);
//         collateralAuctionHouse.modifyParameters("maxDiscount", 0.99E18);
//         collateralFSM.set_val(200 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//         Guy(ali).buyCollateral_increasingDiscount(id, 50 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 0);
//         assertEq(amountToRaise, 0);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 50 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 252525252525252525);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 1 ether - 252525252525252525);
//     }
//     function test_collateral_median_and_collateral_fsm_equal() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         collateralMedian.set_val(200 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 131578947368421052);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
//     }
//     function test_collateral_median_higher_than_collateral_fsm_floor() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         collateralMedian.set_val(181 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 145391102064553649);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 145391102064553649);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 145391102064553649);
//     }
//     function test_collateral_median_lower_than_collateral_fsm_ceiling() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         collateralMedian.set_val(209 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 125912868295139763);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 125912868295139763);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 125912868295139763);
//     }
//     function test_collateral_median_higher_than_collateral_fsm_ceiling() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         collateralMedian.set_val(500 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 125313283208020050);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 125313283208020050);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 125313283208020050);
//     }
//     function test_collateral_median_lower_than_collateral_fsm_floor() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         collateralMedian.set_val(1 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 146198830409356725);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 146198830409356725);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 146198830409356725);
//     }
//     function test_collateral_median_lower_than_collateral_fsm_buy_all() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         collateralMedian.set_val(1 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 50 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 0);
//         assertEq(amountToRaise, 0);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 50 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 292397660818713450);
//     }
//     function test_collateral_median_reverts() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         RevertableMedian revertMedian = new RevertableMedian();
//         collateralFSM.set_price_source(address(revertMedian));
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 131578947368421052);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
//     }
//     function test_system_coin_median_and_redemption_equal() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         systemCoinMedian.set_val(1 ether);
//
//         collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
//
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 131578947368421052);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
//     }
//     function test_system_coin_median_higher_than_redemption_floor() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         systemCoinMedian.set_val(0.975E18);
//
//         collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
//
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 128289473684210526);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 128289473684210526);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 128289473684210526);
//     }
//     function test_system_coin_median_lower_than_redemption_ceiling() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         systemCoinMedian.set_val(1.05E18);
//
//         collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
//
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 138157894736842105);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 138157894736842105);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 138157894736842105);
//     }
//     function test_system_coin_median_higher_than_redemption_ceiling() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         systemCoinMedian.set_val(1.15E18);
//
//         collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
//
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 144736842105263157);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 144736842105263157);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 144736842105263157);
//     }
//     function test_system_coin_median_lower_than_redemption_floor() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         systemCoinMedian.set_val(0.90E18);
//
//         collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
//
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 125000000000000000);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 125000000000000000);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 125000000000000000);
//     }
//     function test_system_coin_median_lower_than_redemption_buy_all() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         systemCoinMedian.set_val(0.90E18);
//
//         collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
//
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 50 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 0);
//         assertEq(amountToRaise, 0);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 50 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 250000000000000000);
//     }
//     function test_system_coin_median_reverts() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         RevertableMedian revertMedian = new RevertableMedian();
//
//         collateralAuctionHouse.modifyParameters("systemCoinOracle", address(revertMedian));
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
//
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 131578947368421052);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
//     }
//     function test_system_coin_lower_collateral_median_higher() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         systemCoinMedian.set_val(0.90E18);
//
//         collateralFSM.set_val(200 ether);
//         collateralMedian.set_val(220 ether);
//
//         collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
//
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 119047619047619047);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 119047619047619047);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 119047619047619047);
//     }
//     function test_system_coin_higher_collateral_median_lower() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         systemCoinMedian.set_val(1.10E18);
//
//         collateralFSM.set_val(200 ether);
//         collateralMedian.set_val(180 ether);
//
//         collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
//
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 160818713450292397);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 160818713450292397);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 160818713450292397);
//     }
//     function test_system_coin_lower_collateral_median_lower() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         systemCoinMedian.set_val(0.90E18);
//
//         collateralFSM.set_val(200 ether);
//         collateralMedian.set_val(180 ether);
//
//         collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
//
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 138888888888888888);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 138888888888888888);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 138888888888888888);
//     }
//     function test_system_coin_higher_collateral_median_higher() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         systemCoinMedian.set_val(1.10E18);
//
//         collateralFSM.set_val(200 ether);
//         collateralMedian.set_val(210 ether);
//
//         collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
//
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 137844611528822055);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 137844611528822055);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 137844611528822055);
//     }
//     function test_min_system_coin_deviation_exceeds_lower_deviation() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         systemCoinMedian.set_val(0.95E18);
//
//         collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
//         collateralAuctionHouse.modifyParameters("minSystemCoinMedianDeviation", 0.94E18);
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
//
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 131578947368421052);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
//     }
//     function test_min_system_coin_deviation_exceeds_higher_deviation() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         systemCoinMedian.set_val(1.05E18);
//
//         collateralAuctionHouse.modifyParameters("systemCoinOracle", address(systemCoinMedian));
//         collateralAuctionHouse.modifyParameters("minSystemCoinMedianDeviation", 0.89E18);
//         collateralAuctionHouse.modifyParameters("lowerSystemCoinMedianDeviation", 0.95E18);
//         collateralAuctionHouse.modifyParameters("upperSystemCoinMedianDeviation", 0.90E18);
//
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether - 131578947368421052);
//         assertEq(amountToRaise, 25 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether - 131578947368421052);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 131578947368421052);
//     }
//     function test_consecutive_small_bids() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         for (uint i = 0; i < 10; i++) {
//           Guy(ali).buyCollateral_increasingDiscount(id, 5 * WAD);
//         }
//
//         assertEq(liquidationEngine.currentOnAuctionSystemCoins(coinName), rad(950 ether));
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 0);
//         assertEq(amountToRaise, 0);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 50 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether - 736842105263157900);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 1 ether - 263157894736842100);
//     }
//     function test_settle_auction() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", 2 * RAY);
//         collateralFSM.set_val(200 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         hevm.warp(now + collateralAuctionHouse.totalAuctionLength() + 1);
//         collateralAuctionHouse.settleAuction(id);
//         assertEq(liquidationEngine.currentOnAuctionSystemCoins(coinName), rad(1000 ether));
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 1 ether);
//         assertEq(amountToRaise, 50 * RAD);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 0);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 1 ether);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 0);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
//     }
//     function testFail_terminate_inexistent() public {
//         collateralAuctionHouse.terminateAuctionPrematurely(1);
//     }
//     function test_terminateAuctionPrematurely() public {
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", 2 * RAY);
//         collateralFSM.set_val(200 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
//         assertEq(liquidationEngine.currentOnAuctionSystemCoins(coinName), rad(975 ether));
//         collateralAuctionHouse.terminateAuctionPrematurely(1);
//         assertEq(liquidationEngine.currentOnAuctionSystemCoins(coinName), rad(950 ether));
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           ,
//           ,
//           ,
//           ,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 0);
//         assertEq(amountToRaise, 0);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 25 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(this)), 999736842105263157895);
//         assertEq(addition(999736842105263157895, 263157894736842105), 1000 ether);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 263157894736842105);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
//     }
//
//     // Custom tests for the increasing discount implementation
//     function test_small_discount_change_rate_bid_right_away() public {
//         collateralAuctionHouse.modifyParameters("perSecondDiscountUpdateRate", 999998607628240588157433861); // -0.5% per hour
//         collateralAuctionHouse.modifyParameters("maxDiscount", 0.93E18);
//
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         Guy(ali).buyCollateral_increasingDiscount(id, 49 * WAD);
//         assertEq(liquidationEngine.currentOnAuctionSystemCoins(coinName), rad(951 ether));
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           uint256 currentDiscount,
//           ,
//           uint256 perSecondDiscountUpdateRate,
//           uint256 latestDiscountUpdateTime,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 742105263157894737);
//         assertEq(amountToRaise, RAY * WAD);
//         assertEq(currentDiscount, collateralAuctionHouse.minDiscount());
//         assertEq(perSecondDiscountUpdateRate, 999998607628240588157433861);
//         assertEq(latestDiscountUpdateTime, now);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 49 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 742105263157894737);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether - 742105263157894737);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
//     }
//     function test_small_discount_change_rate_bid_after_half_rate_timeline() public {
//         collateralAuctionHouse.modifyParameters("perSecondDiscountUpdateRate", 999998607628240588157433861); // -0.5% per hour
//         collateralAuctionHouse.modifyParameters("maxDiscount", 0.93E18);
//
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         hevm.warp(now + 30 minutes);
//         Guy(ali).buyCollateral_increasingDiscount(id, 49 * WAD);
//         assertEq(liquidationEngine.currentOnAuctionSystemCoins(coinName), rad(951 ether));
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           uint256 currentDiscount,
//           ,
//           uint256 perSecondDiscountUpdateRate,
//           uint256 latestDiscountUpdateTime,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 741458098434345369);
//         assertEq(amountToRaise, RAY * WAD);
//         assertEq(currentDiscount, 947622023804850158);
//         assertEq(perSecondDiscountUpdateRate, 999998607628240588157433861);
//         assertEq(latestDiscountUpdateTime, now);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 49 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 741458098434345369);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether - 741458098434345369);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
//     }
//     function test_small_discount_change_rate_bid_end_rate_timeline() public {
//         collateralAuctionHouse.modifyParameters("perSecondDiscountUpdateRate", 999998607628240588157433861); // -0.5% per hour
//         collateralAuctionHouse.modifyParameters("maxDiscount", 0.93E18);
//
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         hevm.warp(now + 1 hours);
//         Guy(ali).buyCollateral_increasingDiscount(id, 49 * WAD);
//         assertEq(liquidationEngine.currentOnAuctionSystemCoins(coinName), rad(951 ether));
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           uint256 currentDiscount,
//           ,
//           uint256 perSecondDiscountUpdateRate,
//           uint256 latestDiscountUpdateTime,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 736559139784946237);
//         assertEq(amountToRaise, RAY * WAD);
//         assertEq(currentDiscount, 930000000000000000);
//         assertEq(perSecondDiscountUpdateRate, 999998607628240588157433861);
//         assertEq(latestDiscountUpdateTime, now);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 49 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 736559139784946237);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether - 736559139784946237);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
//     }
//     function test_small_discount_change_rate_bid_long_after_rate_timeline() public {
//         collateralAuctionHouse.modifyParameters("perSecondDiscountUpdateRate", 999998607628240588157433861); // -0.5% per hour
//         collateralAuctionHouse.modifyParameters("maxDiscount", 0.93E18);
//
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         hevm.warp(now + 3650 days);
//         Guy(ali).buyCollateral_increasingDiscount(id, 49 * WAD);
//         assertEq(liquidationEngine.currentOnAuctionSystemCoins(coinName), rad(951 ether));
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           uint256 currentDiscount,
//           ,
//           uint256 perSecondDiscountUpdateRate,
//           uint256 latestDiscountUpdateTime,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 736559139784946237);
//         assertEq(amountToRaise, RAY * WAD);
//         assertEq(currentDiscount, 930000000000000000);
//         assertEq(perSecondDiscountUpdateRate, 999998607628240588157433861);
//         assertEq(latestDiscountUpdateTime, now);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 49 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 736559139784946237);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether - 736559139784946237);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 0);
//     }
//     function test_bid_multi_times_at_different_timestamps() public {
//         collateralAuctionHouse.modifyParameters("perSecondDiscountUpdateRate", 999998607628240588157433861); // -0.5% per hour
//         collateralAuctionHouse.modifyParameters("maxDiscount", 0.93E18);
//
//         oracleRelayer.modifyParameters(coinName, "redemptionPrice", RAY);
//         collateralFSM.set_val(200 ether);
//         safeEngine.mint(coinName, ali, 200 * RAD - 200 ether);
//
//         uint collateralAmountPreBid = safeEngine.tokenCollateral("collateralType", address(ali));
//
//         uint id = collateralAuctionHouse.startAuction({ amountToSell: 1 ether
//                                                       , amountToRaise: 50 * RAD
//                                                       , forgoneCollateralReceiver: safeAuctioned
//                                                       , auctionIncomeRecipient: auctionIncomeRecipient
//                                                       , initialBid: 0
//                                                       });
//
//         for (uint i = 0; i < 10; i++) {
//           hevm.warp(now + 1 minutes);
//           Guy(ali).buyCollateral_increasingDiscount(id, 5 * WAD);
//         }
//
//         assertEq(liquidationEngine.currentOnAuctionSystemCoins(coinName), rad(950 ether));
//
//         ( uint256 amountToSell,
//           uint256 amountToRaise,
//           uint256 currentDiscount,
//           ,
//           uint256 perSecondDiscountUpdateRate,
//           uint256 latestDiscountUpdateTime,
//           ,
//           ,
//         ) = collateralAuctionHouse.bids(id);
//         assertEq(amountToSell, 0);
//         assertEq(amountToRaise, 0);
//         assertEq(currentDiscount, 0);
//         assertEq(perSecondDiscountUpdateRate, 0);
//         assertEq(latestDiscountUpdateTime, 0);
//
//         assertEq(safeEngine.coinBalance(coinName, auctionIncomeRecipient), 50 * RAD);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(collateralAuctionHouse)), 0);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(ali)) - collateralAmountPreBid, 1 ether - 736721153320545015);
//         assertEq(safeEngine.tokenCollateral("collateralType", address(safeAuctioned)), 736721153320545015);
//     }
// }
