pragma solidity 0.6.7;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";
import "ds-token/delegate.sol";

import {MultiSAFEEngine} from '../../multi/MultiSAFEEngine.sol';
import {MultiLiquidationEngine} from '../../multi/MultiLiquidationEngine.sol';
import {MultiAccountingEngine} from '../../multi/MultiAccountingEngine.sol';
import {MultiTaxCollector} from '../../multi/MultiTaxCollector.sol';
import '../../shared/BasicTokenAdapters.sol';

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract Feed {
    bytes32 public price;
    bool public validPrice;
    uint public lastUpdateTime;
    constructor(uint256 price_, bool validPrice_) public {
        price = bytes32(price_);
        validPrice = validPrice_;
        lastUpdateTime = now;
    }
    function updateCollateralPrice(uint256 price_) external {
        price = bytes32(price_);
        lastUpdateTime = now;
    }
    function getResultWithValidity() external view returns (bytes32, bool) {
        return (price, validPrice);
    }
}

contract TestMultiSAFEEngine is MultiSAFEEngine {
    uint256 constant RAY = 10 ** 27;

    constructor() public {}

    function mint(bytes32 coinName, address usr, uint wad) public {
        coinBalance[coinName][usr] += wad * RAY;
        globalDebt[coinName] += wad * RAY;
    }
    function balanceOf(bytes32 coinName, address usr) public view returns (uint) {
        return uint(coinBalance[coinName][usr] / RAY);
    }
}

contract TestMultiAccountingEngine is MultiAccountingEngine {
    constructor(address safeEngine)
        public MultiAccountingEngine(safeEngine, address(0), 1, 1) {}

    function totalDeficit(bytes32 coinName) public view returns (uint) {
        return safeEngine.debtBalance(coinName, address(this));
    }
    function totalSurplus(bytes32 coinName) public view returns (uint) {
        return safeEngine.coinBalance(coinName, address(this));
    }
    function preAuctionDebt(bytes32 coinName) public view returns (uint) {
        return subtract(totalDeficit(coinName), totalQueuedDebt[coinName]);
    }
}

// --- Saviours ---
contract RevertableSaviour {
    address liquidationEngine;

    constructor(address liquidationEngine_) public {
        liquidationEngine = liquidationEngine_;
    }

    function saveSAFE(bytes32 coinName, address liquidator,bytes32,address) public returns (bool,uint256,uint256) {
        if (liquidator == liquidationEngine) {
          return (true, uint(-1), uint(-1));
        }
        else revert();
    }
}
contract MissingFunctionSaviour {
    function random() public returns (bool, uint256, uint256) {
        return (true, 1, 1);
    }
}
contract FaultyReturnableSaviour {
    function saveSAFE(bytes32,address,bytes32,address) public returns (bool,uint256) {
        return (true, 1);
    }
}
contract ReentrantSaviour {
    address liquidationEngine;

    constructor(address liquidationEngine_) public {
        liquidationEngine = liquidationEngine_;
    }

    function saveSAFE(bytes32 coinName,address liquidator,bytes32 collateralType,address safe) public returns (bool,uint256,uint256) {
        if (liquidator == liquidationEngine) {
          return (true, uint(-1), uint(-1));
        }
        else {
          MultiLiquidationEngine(msg.sender).liquidateSAFE(coinName, collateralType, safe);
          return (true, 1, 1);
        }
    }
}
contract GenuineSaviour {
    address safeEngine;
    address liquidationEngine;

    constructor(address safeEngine_, address liquidationEngine_) public {
        safeEngine = safeEngine_;
        liquidationEngine = liquidationEngine_;
    }

    function saveSAFE(bytes32 coinName, address liquidator, bytes32 collateralType, address safe) public returns (bool,uint256,uint256) {
        if (liquidator == liquidationEngine) {
          return (true, uint(-1), uint(-1));
        }
        else {
          MultiSAFEEngine(safeEngine).modifySAFECollateralization(coinName, collateralType, safe, address(this), safe, 10900 ether, 0);
          return (true, 10900 ether, 0);
        }
    }
}

contract AuctionHouseMock {
    function startAuction(
      address forgoneCollateralReceiver,
      address initialBidder,
      uint256 amountToRaise,
      uint256 collateralToSell,
      uint256 initialBid
    ) public returns (uint256) {
        return 1;
    }
}

contract MultiSaveSAFETest is DSTest {
    Hevm hevm;

    TestMultiSAFEEngine safeEngine;
    TestMultiAccountingEngine accountingEngine;
    MultiLiquidationEngine liquidationEngine;
    DSDelegateToken gold;
    MultiTaxCollector taxCollector;
    AuctionHouseMock auctionHouse;

    BasicCollateralJoin collateralA;

    bytes32 coinName = "MAI";
    address coreReceiver = address(0x123);
    uint256 coreReceiverTaxCut = 10 ** 29 / 5;

    address me;

    function try_modifySAFECollateralization(
      bytes32 collateralType, int lockedCollateral, int generatedDebt
    ) public returns (bool ok) {
        string memory sig = "modifySAFECollateralization(bytes32,bytes32,address,address,address,int256,int256)";
        address self = address(this);
        (ok,) = address(safeEngine).call(
          abi.encodeWithSignature(sig, coinName, collateralType, self, self, self, lockedCollateral, generatedDebt)
        );
    }

    function try_liquidate(bytes32 collateralType, address safe) public returns (bool ok) {
        string memory sig = "liquidateSAFE(bytes32,bytes32,address)";
        (ok,) = address(liquidationEngine).call(abi.encodeWithSignature(sig, coinName, collateralType, safe));
    }

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }
    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }

    function tokenCollateral(bytes32 collateralType, address safe) internal view returns (uint) {
        return safeEngine.tokenCollateral(collateralType, safe);
    }
    function lockedCollateral(bytes32 collateralType, address safe) internal view returns (uint) {
        (uint lockedCollateral_, uint generatedDebt_) = safeEngine.safes(coinName, collateralType, safe); generatedDebt_;
        return lockedCollateral_;
    }
    function generatedDebt(bytes32 collateralType, address safe) internal view returns (uint) {
        (uint lockedCollateral_, uint generatedDebt_) = safeEngine.safes(coinName, collateralType, safe); lockedCollateral_;
        return generatedDebt_;
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine = new TestMultiSAFEEngine();
        safeEngine.initializeCoin(coinName, uint(-1));
        safeEngine = safeEngine;

        accountingEngine = new TestMultiAccountingEngine(address(safeEngine));
        accountingEngine.initializeCoin(coinName, 1, 1);
        safeEngine.addSystemComponent(address(accountingEngine));

        auctionHouse = new AuctionHouseMock();

        taxCollector = new MultiTaxCollector(address(safeEngine), coreReceiver, coreReceiverTaxCut);
        taxCollector.initializeCoin(coinName);
        taxCollector.initializeCollateralType(coinName, "gold");
        taxCollector.modifyParameters("primaryTaxReceiver", address(accountingEngine));
        safeEngine.addSystemComponent(address(taxCollector));

        liquidationEngine = new MultiLiquidationEngine(address(safeEngine));
        liquidationEngine.initializeCoin(coinName, uint(-1));
        liquidationEngine.modifyParameters("accountingEngine", address(accountingEngine));
        liquidationEngine.modifyParameters(coinName, "gold", "collateralAuctionHouse", address(auctionHouse));

        safeEngine.addSystemComponent(address(liquidationEngine));
        accountingEngine.addSystemComponent(address(liquidationEngine));

        gold = new DSDelegateToken("GEM", "GEM");
        gold.mint(1000 ether);

        safeEngine.initializeCollateralType(coinName, "gold");
        collateralA = new BasicCollateralJoin(address(safeEngine), "gold", address(gold));
        safeEngine.addCollateralJoin("gold", address(collateralA));
        gold.approve(address(collateralA));
        collateralA.join(address(this), 1000 ether);

        safeEngine.modifyParameters(coinName, "gold", "safetyPrice", ray(1 ether));
        safeEngine.modifyParameters(coinName, "gold", "debtCeiling", rad(1000 ether));
        safeEngine.modifyParameters(coinName, "globalDebtCeiling", rad(1000 ether));

        liquidationEngine.modifyParameters(coinName, "gold", "liquidationPenalty", 1 ether);

        gold.approve(address(safeEngine));

        me = address(this);
    }

    function liquidateSAFE() internal {
        uint256 MAX_LIQUIDATION_QUANTITY = uint256(-1) / 10 ** 27;
        liquidationEngine.modifyParameters(coinName, "gold", "liquidationQuantity", MAX_LIQUIDATION_QUANTITY);
        liquidationEngine.modifyParameters(coinName, "gold", "liquidationPenalty", 1.1 ether);

        safeEngine.modifyParameters(coinName, "globalDebtCeiling", rad(300000 ether));
        safeEngine.modifyParameters(coinName, "gold", "debtCeiling", rad(300000 ether));
        safeEngine.modifyParameters(coinName, "gold", 'safetyPrice', ray(5 ether));
        safeEngine.modifyParameters(coinName, "gold", 'liquidationPrice', ray(5 ether));
        safeEngine.modifySAFECollateralization(coinName, "gold", me, me, me, 10 ether, 50 ether);

        safeEngine.modifyParameters(coinName, "gold", 'safetyPrice', ray(2 ether));      // now unsafe
        safeEngine.modifyParameters(coinName, "gold", 'liquidationPrice', ray(2 ether));

        uint auction = liquidationEngine.liquidateSAFE(coinName, "gold", address(this));
        assertEq(auction, 1);
    }
    function liquidateSavedSAFE() internal {
        uint256 MAX_LIQUIDATION_QUANTITY = uint256(-1) / 10 ** 27;
        liquidationEngine.modifyParameters(coinName, "gold", "liquidationQuantity", MAX_LIQUIDATION_QUANTITY);
        liquidationEngine.modifyParameters(coinName, "gold", "liquidationPenalty", 1.1 ether);

        safeEngine.modifyParameters(coinName, "globalDebtCeiling", rad(300000 ether));
        safeEngine.modifyParameters(coinName, "gold", "debtCeiling", rad(300000 ether));
        safeEngine.modifyParameters(coinName, "gold", 'safetyPrice', ray(5 ether));
        safeEngine.modifyParameters(coinName, "gold", 'liquidationPrice', ray(5 ether));
        safeEngine.modifySAFECollateralization(coinName, "gold", me, me, me, 10 ether, 50 ether);

        safeEngine.modifyParameters(coinName, "gold", 'safetyPrice', ray(2 ether));      // now unsafe
        safeEngine.modifyParameters(coinName, "gold", 'liquidationPrice', ray(2 ether));

        uint auction = liquidationEngine.liquidateSAFE(coinName, "gold", address(this));
        assertEq(auction, 0);
    }

    function test_revertable_saviour() public {
        RevertableSaviour saviour = new RevertableSaviour(address(liquidationEngine));
        liquidationEngine.connectSAFESaviour(coinName, address(saviour));
        liquidationEngine.protectSAFE(coinName, "gold", me, address(saviour));
        assertTrue(liquidationEngine.chosenSAFESaviour(coinName, "gold", me) == address(saviour));
        liquidateSAFE();
    }
    function testFail_missing_function_saviour() public {
        MissingFunctionSaviour saviour = new MissingFunctionSaviour();
        liquidationEngine.connectSAFESaviour(coinName, address(saviour));
    }
    function testFail_faulty_returnable_function_saviour() public {
        FaultyReturnableSaviour saviour = new FaultyReturnableSaviour();
        liquidationEngine.connectSAFESaviour(coinName, address(saviour));
    }
    function test_liquidate_reentrant_saviour() public {
        ReentrantSaviour saviour = new ReentrantSaviour(address(liquidationEngine));
        liquidationEngine.connectSAFESaviour(coinName, address(saviour));
        liquidationEngine.protectSAFE(coinName, "gold", me, address(saviour));
        assertTrue(liquidationEngine.chosenSAFESaviour(coinName, "gold", me) == address(saviour));
        liquidateSAFE();
    }
    function test_liquidate_genuine_saviour() public {
        GenuineSaviour saviour = new GenuineSaviour(address(safeEngine), address(liquidationEngine));
        liquidationEngine.connectSAFESaviour(coinName, address(saviour));
        liquidationEngine.protectSAFE(coinName, "gold", me, address(saviour));
        safeEngine.approveSAFEModification(coinName, address(saviour));
        assertTrue(liquidationEngine.chosenSAFESaviour(coinName, "gold", me) == address(saviour));

        gold.mint(10000 ether);
        collateralA.join(address(this), 10000 ether);
        safeEngine.transferCollateral(coinName, "gold", me, address(saviour), 10900 ether);

        liquidateSavedSAFE();

        (uint256 lockedCollateral, ) = safeEngine.safes(coinName, "gold", me);
        assertEq(lockedCollateral, 10910 ether);

        assertEq(liquidationEngine.currentOnAuctionSystemCoins(coinName), 0);
    }
}
