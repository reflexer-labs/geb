// pragma solidity 0.6.7;
// pragma experimental ABIEncoderV2;
//
// import "ds-test/test.sol";
// import "ds-token/delegate.sol";
//
// import {MultiSAFEEngine} from '../../multi/MultiSAFEEngine.sol';
// import {MultiLiquidationEngine} from '../../multi/MultiLiquidationEngine.sol';
// import {MultiAccountingEngine} from '../../multi/MultiAccountingEngine.sol';
// import {MultiTaxCollector} from '../../multi/MultiTaxCollector.sol';
// import '../../shared/BasicTokenAdapters.sol';
//
// abstract contract Hevm {
//     function warp(uint256) virtual public;
// }
//
// contract Feed {
//     bytes32 public price;
//     bool public validPrice;
//     uint public lastUpdateTime;
//     constructor(uint256 price_, bool validPrice_) public {
//         price = bytes32(price_);
//         validPrice = validPrice_;
//         lastUpdateTime = now;
//     }
//     function updateCollateralPrice(uint256 price_) external {
//         price = bytes32(price_);
//         lastUpdateTime = now;
//     }
//     function getResultWithValidity() external view returns (bytes32, bool) {
//         return (price, validPrice);
//     }
// }
//
// contract TestMultiSAFEEngine is MultiSAFEEngine {
//     uint256 constant RAY = 10 ** 27;
//
//     constructor() public {}
//
//     function mint(bytes32 coinName, address usr, uint wad) public {
//         coinBalance[coinName][usr] += wad * RAY;
//         globalDebt[coinName] += wad * RAY;
//     }
//     function balanceOf(bytes32 coinName, address usr) public view returns (uint) {
//         return uint(coinBalance[coinName][usr] / RAY);
//     }
// }
//
// contract TestMultiAccountingEngine is MultiAccountingEngine {
//     constructor(address safeEngine)
//         public MultiAccountingEngine(safeEngine, address(0), 1, 1) {}
//
//     function totalDeficit(bytes32 coinName) public view returns (uint) {
//         return safeEngine.debtBalance(coinName, address(this));
//     }
//     function totalSurplus(bytes32 coinName) public view returns (uint) {
//         return safeEngine.coinBalance(coinName, address(this));
//     }
//     function preAuctionDebt(bytes32 coinName) public view returns (uint) {
//         return subtract(totalDeficit(coinName), totalQueuedDebt[coinName]);
//     }
// }
//
// // --- Saviours ---
// contract RevertableCanLiquidatePool {
//     function canLiquidate(bytes32,bytes32,uint256,uint256) external returns (bool) {
//         revert();
//     }
// }
// contract FaultyCanLiquidatePool {
//     function canLiquidate(bytes32,bytes32,uint256,uint256) external returns (bool) {
//         return false;
//     }
// }
// contract MissingFunctionLiquidatePool {
//     function random() public returns (bool, uint256, uint256) {
//         return (true, 1, 1);
//     }
// }
// contract RevertableLiquidatePool {
//     function canLiquidate(bytes32,bytes32,uint256,uint256) external returns (bool) {
//         return true;
//     }
//     function liquidateSAFE(bytes32,bytes32,uint256,uint256,address) external returns (bool) {
//         revert();
//     }
// }
// contract FaultyLiquidatePool {
//     function canLiquidate(bytes32,bytes32,uint256,uint256) external returns (bool) {
//         return true;
//     }
//     function liquidateSAFE(bytes32,bytes32,uint256,uint256,address) external returns (bool) {
//         return false;
//     }
// }
// contract MissingLiquidatePool {
//     function canLiquidate(bytes32,bytes32,uint256,uint256) external returns (bool) {
//         return true;
//     }
// }
// contract GenuineLiquidationPool {
//     address safeEngine;
//
//     constructor(address safeEngine_) public {
//         safeEngine = safeEngine_;
//     }
//
//     function canLiquidate(bytes32,bytes32,uint256,uint256) external returns (bool) {
//         return true;
//     }
//
//     function liquidateSAFE(
//       bytes32 coinName, bytes32 collateralType, uint256 debtAmount, uint256 collateralAmount, address accountingEngine
//     ) external returns (bool) {
//         MultiSAFEEngine(safeEngine).transferCollateral(coinName, collateralType, msg.sender, address(this), collateralAmount);
//         MultiSAFEEngine(safeEngine).transferInternalCoins(coinName, address(this), accountingEngine, debtAmount);
//         return true;
//     }
// }
//
// contract AuctionHouseMock {
//     function startAuction(
//       address forgoneCollateralReceiver,
//       address initialBidder,
//       uint256 amountToRaise,
//       uint256 collateralToSell,
//       uint256 initialBid
//     ) public returns (uint256) {
//         return 1;
//     }
// }
//
// contract MultiLiquidationPoolTest is DSTest {
//     Hevm hevm;
//
//     TestMultiSAFEEngine safeEngine;
//     TestMultiAccountingEngine accountingEngine;
//     MultiLiquidationEngine liquidationEngine;
//     DSDelegateToken gold;
//     MultiTaxCollector taxCollector;
//     AuctionHouseMock auctionHouse;
//
//     BasicCollateralJoin collateralA;
//
//     bytes32 coinName = "MAI";
//     address coreReceiver = address(0x123);
//     uint256 coreReceiverTaxCut = 10 ** 29 / 5;
//
//     address me;
//
//     function ray(uint wad) internal pure returns (uint) {
//         return wad * 10 ** 9;
//     }
//     function rad(uint wad) internal pure returns (uint) {
//         return wad * 10 ** 27;
//     }
//
//     function setUp() public {
//         hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
//         hevm.warp(604411200);
//
//         safeEngine = new TestMultiSAFEEngine();
//         safeEngine.initializeCoin(coinName, uint(-1));
//         safeEngine = safeEngine;
//
//         accountingEngine = new TestMultiAccountingEngine(address(safeEngine));
//         accountingEngine.initializeCoin(coinName, 1, 1);
//         safeEngine.addSystemComponent(address(accountingEngine));
//
//         auctionHouse = new AuctionHouseMock();
//
//         taxCollector = new MultiTaxCollector(address(safeEngine), coreReceiver, coreReceiverTaxCut);
//         taxCollector.initializeCoin(coinName);
//         taxCollector.initializeCollateralType(coinName, "gold");
//         taxCollector.modifyParameters("primaryTaxReceiver", address(accountingEngine));
//         safeEngine.addSystemComponent(address(taxCollector));
//
//         liquidationEngine = new MultiLiquidationEngine(address(safeEngine));
//         liquidationEngine.initializeCoin(coinName, uint(-1));
//         liquidationEngine.modifyParameters("accountingEngine", address(accountingEngine));
//         liquidationEngine.modifyParameters(coinName, "gold", "collateralAuctionHouse", address(auctionHouse));
//
//         safeEngine.addSystemComponent(address(liquidationEngine));
//         accountingEngine.addSystemComponent(address(liquidationEngine));
//
//         gold = new DSDelegateToken("GEM", "GEM");
//         gold.mint(1000 ether);
//
//         safeEngine.initializeCollateralType(coinName, "gold");
//         collateralA = new BasicCollateralJoin(address(safeEngine), "gold", address(gold));
//         safeEngine.addCollateralJoin("gold", address(collateralA));
//         gold.approve(address(collateralA));
//         collateralA.join(address(this), 1000 ether);
//
//         safeEngine.modifyParameters(coinName, "gold", "safetyPrice", ray(1 ether));
//         safeEngine.modifyParameters(coinName, "gold", "debtCeiling", rad(1000 ether));
//         safeEngine.modifyParameters(coinName, "globalDebtCeiling", rad(1000 ether));
//
//         liquidationEngine.modifyParameters(coinName, "gold", "liquidationPenalty", 1 ether);
//
//         gold.approve(address(safeEngine));
//
//         me = address(this);
//     }
//
//     function liquidateSAFE() internal {
//         uint256 MAX_LIQUIDATION_QUANTITY = uint256(-1) / 10 ** 27;
//         liquidationEngine.modifyParameters(coinName, "gold", "liquidationQuantity", MAX_LIQUIDATION_QUANTITY);
//         liquidationEngine.modifyParameters(coinName, "gold", "liquidationPenalty", 1.1 ether);
//
//         safeEngine.modifyParameters(coinName, "globalDebtCeiling", rad(300000 ether));
//         safeEngine.modifyParameters(coinName, "gold", "debtCeiling", rad(300000 ether));
//         safeEngine.modifyParameters(coinName, "gold", 'safetyPrice', ray(5 ether));
//         safeEngine.modifyParameters(coinName, "gold", 'liquidationPrice', ray(5 ether));
//         safeEngine.modifySAFECollateralization(coinName, "gold", me, me, me, 10 ether, 50 ether);
//
//         safeEngine.modifyParameters(coinName, "gold", 'safetyPrice', ray(2 ether));      // now unsafe
//         safeEngine.modifyParameters(coinName, "gold", 'liquidationPrice', ray(2 ether));
//
//         uint auction = liquidationEngine.liquidateSAFE(coinName, "gold", address(this));
//         assertEq(auction, 1);
//     }
//
//     function liquidateSAFEFail() internal {
//         uint256 MAX_LIQUIDATION_QUANTITY = uint256(-1) / 10 ** 27;
//         liquidationEngine.modifyParameters(coinName, "gold", "liquidationQuantity", MAX_LIQUIDATION_QUANTITY);
//         liquidationEngine.modifyParameters(coinName, "gold", "liquidationPenalty", 1.1 ether);
//
//         safeEngine.modifyParameters(coinName, "globalDebtCeiling", rad(300000 ether));
//         safeEngine.modifyParameters(coinName, "gold", "debtCeiling", rad(300000 ether));
//         safeEngine.modifyParameters(coinName, "gold", 'safetyPrice', ray(5 ether));
//         safeEngine.modifyParameters(coinName, "gold", 'liquidationPrice', ray(5 ether));
//         safeEngine.modifySAFECollateralization(coinName, "gold", me, me, me, 10 ether, 50 ether);
//
//         safeEngine.modifyParameters(coinName, "gold", 'safetyPrice', ray(2 ether));      // now unsafe
//         safeEngine.modifyParameters(coinName, "gold", 'liquidationPrice', ray(2 ether));
//
//         uint auction = liquidationEngine.liquidateSAFE(coinName, "gold", address(this));
//         assertEq(auction, 0);
//     }
//
//     function testFail_revertable_can_liquidate() public {
//         RevertableCanLiquidatePool pool = new RevertableCanLiquidatePool();
//         liquidationEngine.modifyParameters(coinName, "gold", "liquidationPool", address(pool));
//     }
//     function testFail_faulty_can_liquidate() public {
//         FaultyCanLiquidatePool pool = new FaultyCanLiquidatePool();
//         liquidationEngine.modifyParameters(coinName, "gold", "liquidationPool", address(pool));
//     }
//     function testFail_missing_function_can_liquidate() public {
//         MissingFunctionLiquidatePool pool = new MissingFunctionLiquidatePool();
//         liquidationEngine.modifyParameters(coinName, "gold", "liquidationPool", address(pool));
//     }
//     function test_revertable_liquidate_pool() public {
//         RevertableLiquidatePool pool = new RevertableLiquidatePool();
//         liquidationEngine.modifyParameters(coinName, "gold", "liquidationPool", address(pool));
//         liquidateSAFE();
//     }
//     function testFail_faulty_liquidate_pool() public {
//         FaultyLiquidatePool pool = new FaultyLiquidatePool();
//         liquidationEngine.modifyParameters(coinName, "gold", "liquidationPool", address(pool));
//         liquidateSAFE();
//     }
//     function testFail_missing_implementation_liquidate_pool() public {
//         MissingFunctionLiquidatePool pool = new MissingFunctionLiquidatePool();
//         liquidationEngine.modifyParameters(coinName, "gold", "liquidationPool", address(pool));
//         liquidateSAFE();
//     }
//     function test_genuine_liquidation_pool() public {
//         GenuineLiquidationPool pool = new GenuineLiquidationPool(address(safeEngine));
//         liquidationEngine.modifyParameters(coinName, "gold", "liquidationPool", address(pool));
//
//         assertEq(safeEngine.tokenCollateral("gold", address(pool)), 0);
//
//         safeEngine.createUnbackedDebt(coinName, address(0x1), address(pool), rad(1000 ether));
//         assertEq(safeEngine.coinBalance(coinName, address(pool)), rad(1000 ether));
//
//         liquidateSAFEFail();
//         assertEq(safeEngine.tokenCollateral("gold", address(pool)), 10 ether);
//         assertTrue(safeEngine.coinBalance(coinName, address(pool)) < rad(1000 ether) - rad(50 ether));
//     }
// }
