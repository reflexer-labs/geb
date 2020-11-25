pragma solidity 0.6.7;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";
import "ds-token/delegate.sol";

import {SAFEEngine} from '../SAFEEngine.sol';
import {LiquidationEngine} from '../LiquidationEngine.sol';
import {AccountingEngine} from '../AccountingEngine.sol';
import {TaxCollector} from '../TaxCollector.sol';
import '../BasicTokenAdapters.sol';
import {OracleRelayer} from '../OracleRelayer.sol';

import {EnglishCollateralAuctionHouse} from './CollateralAuctionHouse.t.sol';
import {DebtAuctionHouse} from './DebtAuctionHouse.t.sol';
import {PostSettlementSurplusAuctionHouse} from './SurplusAuctionHouse.t.sol';

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

contract TestSAFEEngine is SAFEEngine {
    uint256 constant RAY = 10 ** 27;

    constructor() public {}

    function mint(address usr, uint wad) public {
        coinBalance[usr] += wad * RAY;
        globalDebt += wad * RAY;
    }
    function balanceOf(address usr) public view returns (uint) {
        return uint(coinBalance[usr] / RAY);
    }
}

contract TestAccountingEngine is AccountingEngine {
    constructor(address safeEngine, address surplusAuctionHouse, address debtAuctionHouse)
        public AccountingEngine(safeEngine, surplusAuctionHouse, debtAuctionHouse) {}

    function totalDeficit() public view returns (uint) {
        return safeEngine.debtBalance(address(this));
    }
    function totalSurplus() public view returns (uint) {
        return safeEngine.coinBalance(address(this));
    }
    function preAuctionDebt() public view returns (uint) {
        return subtract(subtract(totalDeficit(), totalQueuedDebt), totalOnAuctionDebt);
    }
}

// --- Saviours ---
contract RevertableSaviour {
    address liquidationEngine;

    constructor(address liquidationEngine_) public {
        liquidationEngine = liquidationEngine_;
    }

    function saveSAFE(address liquidator,bytes32,address) public returns (bool,uint256,uint256) {
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
    function saveSAFE(address,bytes32,address) public returns (bool,uint256) {
        return (true, 1);
    }
}
contract ReentrantSaviour {
    address liquidationEngine;

    constructor(address liquidationEngine_) public {
        liquidationEngine = liquidationEngine_;
    }

    function saveSAFE(address liquidator,bytes32 collateralType,address safe) public returns (bool,uint256,uint256) {
        if (liquidator == liquidationEngine) {
          return (true, uint(-1), uint(-1));
        }
        else {
          LiquidationEngine(msg.sender).liquidateSAFE(collateralType, safe);
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

    function saveSAFE(address liquidator, bytes32 collateralType, address safe) public returns (bool,uint256,uint256) {
        if (liquidator == liquidationEngine) {
          return (true, uint(-1), uint(-1));
        }
        else {
          SAFEEngine(safeEngine).modifySAFECollateralization(collateralType, safe, address(this), safe, 10900 ether, 0);
          return (true, 10900 ether, 0);
        }
    }
}

contract SaveSAFETest is DSTest {
    Hevm hevm;

    TestSAFEEngine safeEngine;
    TestAccountingEngine accountingEngine;
    LiquidationEngine liquidationEngine;
    DSDelegateToken gold;
    TaxCollector taxCollector;

    BasicCollateralJoin collateralA;

    EnglishCollateralAuctionHouse collateralAuctionHouse;
    DebtAuctionHouse debtAuctionHouse;
    PostSettlementSurplusAuctionHouse surplusAuctionHouse;

    DSDelegateToken protocolToken;

    address me;

    function try_modifySAFECollateralization(
      bytes32 collateralType, int lockedCollateral, int generatedDebt
    ) public returns (bool ok) {
        string memory sig = "modifySAFECollateralization(bytes32,address,address,address,int256,int256)";
        address self = address(this);
        (ok,) = address(safeEngine).call(
          abi.encodeWithSignature(sig, collateralType, self, self, self, lockedCollateral, generatedDebt)
        );
    }

    function try_liquidate(bytes32 collateralType, address safe) public returns (bool ok) {
        string memory sig = "liquidateSAFE(bytes32,address)";
        (ok,) = address(liquidationEngine).call(abi.encodeWithSignature(sig, collateralType, safe));
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
        (uint lockedCollateral_, uint generatedDebt_) = safeEngine.safes(collateralType, safe); generatedDebt_;
        return lockedCollateral_;
    }
    function generatedDebt(bytes32 collateralType, address safe) internal view returns (uint) {
        (uint lockedCollateral_, uint generatedDebt_) = safeEngine.safes(collateralType, safe); lockedCollateral_;
        return generatedDebt_;
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        protocolToken = new DSDelegateToken('GOV', 'GOV');
        protocolToken.mint(100 ether);

        safeEngine = new TestSAFEEngine();
        safeEngine = safeEngine;

        surplusAuctionHouse = new PostSettlementSurplusAuctionHouse(address(safeEngine), address(protocolToken));
        debtAuctionHouse = new DebtAuctionHouse(address(safeEngine), address(protocolToken));

        accountingEngine = new TestAccountingEngine(
          address(safeEngine), address(surplusAuctionHouse), address(debtAuctionHouse)
        );
        surplusAuctionHouse.addAuthorization(address(accountingEngine));
        debtAuctionHouse.addAuthorization(address(accountingEngine));
        debtAuctionHouse.modifyParameters("accountingEngine", address(accountingEngine));
        safeEngine.addAuthorization(address(accountingEngine));

        taxCollector = new TaxCollector(address(safeEngine));
        taxCollector.initializeCollateralType("gold");
        taxCollector.modifyParameters("primaryTaxReceiver", address(accountingEngine));
        safeEngine.addAuthorization(address(taxCollector));

        liquidationEngine = new LiquidationEngine(address(safeEngine));
        liquidationEngine.modifyParameters("accountingEngine", address(accountingEngine));
        safeEngine.addAuthorization(address(liquidationEngine));
        accountingEngine.addAuthorization(address(liquidationEngine));

        gold = new DSDelegateToken("GEM", "GEM");
        gold.mint(1000 ether);

        safeEngine.initializeCollateralType("gold");
        collateralA = new BasicCollateralJoin(address(safeEngine), "gold", address(gold));
        safeEngine.addAuthorization(address(collateralA));
        gold.approve(address(collateralA));
        collateralA.join(address(this), 1000 ether);

        safeEngine.modifyParameters("gold", "safetyPrice", ray(1 ether));
        safeEngine.modifyParameters("gold", "debtCeiling", rad(1000 ether));
        safeEngine.modifyParameters("globalDebtCeiling", rad(1000 ether));

        collateralAuctionHouse = new EnglishCollateralAuctionHouse(address(safeEngine), address(liquidationEngine), "gold");
        collateralAuctionHouse.addAuthorization(address(liquidationEngine));

        liquidationEngine.addAuthorization(address(collateralAuctionHouse));
        liquidationEngine.modifyParameters("gold", "collateralAuctionHouse", address(collateralAuctionHouse));
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1 ether);

        safeEngine.addAuthorization(address(collateralAuctionHouse));
        safeEngine.addAuthorization(address(surplusAuctionHouse));
        safeEngine.addAuthorization(address(debtAuctionHouse));

        safeEngine.approveSAFEModification(address(collateralAuctionHouse));
        safeEngine.approveSAFEModification(address(debtAuctionHouse));
        gold.approve(address(safeEngine));
        protocolToken.approve(address(surplusAuctionHouse));

        me = address(this);
    }

    function liquidateSAFE() internal {
        uint256 MAX_LIQUIDATION_QUANTITY = uint256(-1) / 10 ** 27;
        liquidationEngine.modifyParameters("gold", "liquidationQuantity", MAX_LIQUIDATION_QUANTITY);
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1.1 ether);

        safeEngine.modifyParameters("globalDebtCeiling", rad(300000 ether));
        safeEngine.modifyParameters("gold", "debtCeiling", rad(300000 ether));
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(5 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(5 ether));
        safeEngine.modifySAFECollateralization("gold", me, me, me, 10 ether, 50 ether);

        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2 ether));      // now unsafe
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2 ether));

        uint auction = liquidationEngine.liquidateSAFE("gold", address(this));
        assertEq(auction, 1);
    }
    function liquidateSavedSAFE() internal {
        uint256 MAX_LIQUIDATION_QUANTITY = uint256(-1) / 10 ** 27;
        liquidationEngine.modifyParameters("gold", "liquidationQuantity", MAX_LIQUIDATION_QUANTITY);
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1.1 ether);

        safeEngine.modifyParameters("globalDebtCeiling", rad(300000 ether));
        safeEngine.modifyParameters("gold", "debtCeiling", rad(300000 ether));
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(5 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(5 ether));
        safeEngine.modifySAFECollateralization("gold", me, me, me, 10 ether, 50 ether);

        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2 ether));      // now unsafe
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2 ether));

        uint auction = liquidationEngine.liquidateSAFE("gold", address(this));
        assertEq(auction, 0);
    }

    function test_revertable_saviour() public {
        RevertableSaviour saviour = new RevertableSaviour(address(liquidationEngine));
        liquidationEngine.connectSAFESaviour(address(saviour));
        liquidationEngine.protectSAFE("gold", me, address(saviour));
        assertTrue(liquidationEngine.chosenSAFESaviour("gold", me) == address(saviour));
        liquidateSAFE();
    }
    function testFail_missing_function_saviour() public {
        MissingFunctionSaviour saviour = new MissingFunctionSaviour();
        liquidationEngine.connectSAFESaviour(address(saviour));
    }
    function testFail_faulty_returnable_function_saviour() public {
        FaultyReturnableSaviour saviour = new FaultyReturnableSaviour();
        liquidationEngine.connectSAFESaviour(address(saviour));
    }
    function test_liquidate_reentrant_saviour() public {
        ReentrantSaviour saviour = new ReentrantSaviour(address(liquidationEngine));
        liquidationEngine.connectSAFESaviour(address(saviour));
        liquidationEngine.protectSAFE("gold", me, address(saviour));
        assertTrue(liquidationEngine.chosenSAFESaviour("gold", me) == address(saviour));
        liquidateSAFE();
    }
    function test_liquidate_genuine_saviour() public {
        GenuineSaviour saviour = new GenuineSaviour(address(safeEngine), address(liquidationEngine));
        liquidationEngine.connectSAFESaviour(address(saviour));
        liquidationEngine.protectSAFE("gold", me, address(saviour));
        safeEngine.approveSAFEModification(address(saviour));
        assertTrue(liquidationEngine.chosenSAFESaviour("gold", me) == address(saviour));

        gold.mint(10000 ether);
        collateralA.join(address(this), 10000 ether);
        safeEngine.transferCollateral("gold", me, address(saviour), 10900 ether);

        liquidateSavedSAFE();

        (uint256 lockedCollateral, ) = safeEngine.safes("gold", me);
        assertEq(lockedCollateral, 10910 ether);

        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 0);
    }
}
