pragma solidity ^0.6.7;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";
import "ds-token/token.sol";

import {CDPEngine} from '../CDPEngine.sol';
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

contract TestCDPEngine is CDPEngine {
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
    constructor(address cdpEngine, address surplusAuctionHouse, address debtAuctionHouse)
        public AccountingEngine(cdpEngine, surplusAuctionHouse, debtAuctionHouse) {}

    function totalDeficit() public view returns (uint) {
        return cdpEngine.debtBalance(address(this));
    }
    function totalSurplus() public view returns (uint) {
        return cdpEngine.coinBalance(address(this));
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

    function saveCDP(address liquidator,bytes32,address) public returns (bool,uint256,uint256) {
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
    function saveCDP(address,bytes32,address) public returns (bool,uint256) {
        return (true, 1);
    }
}
contract ReentrantSaviour {
    address liquidationEngine;

    constructor(address liquidationEngine_) public {
        liquidationEngine = liquidationEngine_;
    }

    function saveCDP(address liquidator,bytes32 collateralType,address cdp) public returns (bool,uint256,uint256) {
        if (liquidator == liquidationEngine) {
          return (true, uint(-1), uint(-1));
        }
        else {
          LiquidationEngine(msg.sender).liquidateCDP(collateralType, cdp);
          return (true, 1, 1);
        }
    }
}
contract GenuineSaviour {
    address cdpEngine;
    address liquidationEngine;

    constructor(address cdpEngine_, address liquidationEngine_) public {
        cdpEngine = cdpEngine_;
        liquidationEngine = liquidationEngine_;
    }

    function saveCDP(address liquidator, bytes32 collateralType, address cdp) public returns (bool,uint256,uint256) {
        if (liquidator == liquidationEngine) {
          return (true, uint(-1), uint(-1));
        }
        else {
          CDPEngine(cdpEngine).modifyCDPCollateralization(collateralType, cdp, address(this), cdp, 10900 ether, 0);
          return (true, 10900 ether, 0);
        }
    }
}

contract SaveCDPTest is DSTest {
    Hevm hevm;

    TestCDPEngine cdpEngine;
    TestAccountingEngine accountingEngine;
    LiquidationEngine liquidationEngine;
    DSToken gold;
    TaxCollector taxCollector;

    BasicCollateralJoin collateralA;

    EnglishCollateralAuctionHouse collateralAuctionHouse;
    DebtAuctionHouse debtAuctionHouse;
    PostSettlementSurplusAuctionHouse surplusAuctionHouse;

    DSToken protocolToken;

    address me;

    function try_modifyCDPCollateralization(
      bytes32 collateralType, int lockedCollateral, int generatedDebt
    ) public returns (bool ok) {
        string memory sig = "modifyCDPCollateralization(bytes32,address,address,address,int256,int256)";
        address self = address(this);
        (ok,) = address(cdpEngine).call(
          abi.encodeWithSignature(sig, collateralType, self, self, self, lockedCollateral, generatedDebt)
        );
    }

    function try_liquidate(bytes32 collateralType, address cdp) public returns (bool ok) {
        string memory sig = "liquidateCDP(bytes32,address)";
        (ok,) = address(liquidationEngine).call(abi.encodeWithSignature(sig, collateralType, cdp));
    }

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }
    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }

    function tokenCollateral(bytes32 collateralType, address cdp) internal view returns (uint) {
        return cdpEngine.tokenCollateral(collateralType, cdp);
    }
    function lockedCollateral(bytes32 collateralType, address cdp) internal view returns (uint) {
        (uint lockedCollateral_, uint generatedDebt_) = cdpEngine.cdps(collateralType, cdp); generatedDebt_;
        return lockedCollateral_;
    }
    function generatedDebt(bytes32 collateralType, address cdp) internal view returns (uint) {
        (uint lockedCollateral_, uint generatedDebt_) = cdpEngine.cdps(collateralType, cdp); lockedCollateral_;
        return generatedDebt_;
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        protocolToken = new DSToken('GOV');
        protocolToken.mint(100 ether);

        cdpEngine = new TestCDPEngine();
        cdpEngine = cdpEngine;

        surplusAuctionHouse = new PostSettlementSurplusAuctionHouse(address(cdpEngine), address(protocolToken));
        debtAuctionHouse = new DebtAuctionHouse(address(cdpEngine), address(protocolToken));

        accountingEngine = new TestAccountingEngine(
          address(cdpEngine), address(surplusAuctionHouse), address(debtAuctionHouse)
        );
        surplusAuctionHouse.addAuthorization(address(accountingEngine));
        debtAuctionHouse.addAuthorization(address(accountingEngine));
        debtAuctionHouse.modifyParameters("accountingEngine", address(accountingEngine));
        cdpEngine.addAuthorization(address(accountingEngine));

        taxCollector = new TaxCollector(address(cdpEngine));
        taxCollector.initializeCollateralType("gold");
        taxCollector.modifyParameters("primaryTaxReceiver", address(accountingEngine));
        cdpEngine.addAuthorization(address(taxCollector));

        liquidationEngine = new LiquidationEngine(address(cdpEngine));
        liquidationEngine.modifyParameters("accountingEngine", address(accountingEngine));
        cdpEngine.addAuthorization(address(liquidationEngine));
        accountingEngine.addAuthorization(address(liquidationEngine));

        gold = new DSToken("GEM");
        gold.mint(1000 ether);

        cdpEngine.initializeCollateralType("gold");
        collateralA = new BasicCollateralJoin(address(cdpEngine), "gold", address(gold));
        cdpEngine.addAuthorization(address(collateralA));
        gold.approve(address(collateralA));
        collateralA.join(address(this), 1000 ether);

        cdpEngine.modifyParameters("gold", "safetyPrice", ray(1 ether));
        cdpEngine.modifyParameters("gold", "debtCeiling", rad(1000 ether));
        cdpEngine.modifyParameters("globalDebtCeiling", rad(1000 ether));
        collateralAuctionHouse = new EnglishCollateralAuctionHouse(address(cdpEngine), "gold");
        collateralAuctionHouse.modifyParameters("oracleRelayer", address(new OracleRelayer(address(cdpEngine))));
        collateralAuctionHouse.modifyParameters("orcl", address(new Feed(uint256(1), true)));
        collateralAuctionHouse.addAuthorization(address(liquidationEngine));
        liquidationEngine.modifyParameters("gold", "collateralAuctionHouse", address(collateralAuctionHouse));
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", ray(1 ether));

        cdpEngine.addAuthorization(address(collateralAuctionHouse));
        cdpEngine.addAuthorization(address(surplusAuctionHouse));
        cdpEngine.addAuthorization(address(debtAuctionHouse));

        cdpEngine.approveCDPModification(address(collateralAuctionHouse));
        cdpEngine.approveCDPModification(address(debtAuctionHouse));
        gold.approve(address(cdpEngine));
        protocolToken.approve(address(surplusAuctionHouse));

        me = address(this);
    }

    function liquidateCDP() internal {
        cdpEngine.modifyParameters("gold", 'safetyPrice', ray(10 ether));
        cdpEngine.modifyCDPCollateralization("gold", me, me, me, 40 ether, 100 ether);

        cdpEngine.modifyParameters("gold", 'safetyPrice', ray(1 ether));
        cdpEngine.modifyParameters("gold", 'liquidationPrice', ray(2 ether));  // now unsafe

        liquidationEngine.modifyParameters("gold", "collateralToSell", 50 ether);
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", ray(1.1 ether));

        uint auction = liquidationEngine.liquidateCDP("gold", address(this));
        assertEq(auction, 1);
    }
    function liquidateSavedCDP() internal {
        cdpEngine.modifyParameters("gold", 'safetyPrice', ray(10 ether));
        cdpEngine.modifyCDPCollateralization("gold", me, me, me, 10 ether, 100 ether);

        cdpEngine.modifyParameters("gold", 'liquidationPrice', ray(8 ether));  // now unsafe

        liquidationEngine.modifyParameters("gold", "collateralToSell", 50 ether);
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", ray(1.1 ether));

        uint auction = liquidationEngine.liquidateCDP("gold", address(this));
        assertEq(auction, 0);
    }

    function test_revertable_saviour() public {
        RevertableSaviour saviour = new RevertableSaviour(address(liquidationEngine));
        liquidationEngine.connectCDPSaviour(address(saviour));
        liquidationEngine.protectCDP("gold", me, address(saviour));
        assertTrue(liquidationEngine.chosenCDPSaviour("gold", me) == address(saviour));
        liquidateCDP();
    }
    function testFail_missing_function_saviour() public {
        MissingFunctionSaviour saviour = new MissingFunctionSaviour();
        liquidationEngine.connectCDPSaviour(address(saviour));
    }
    function testFail_faulty_returnable_function_saviour() public {
        FaultyReturnableSaviour saviour = new FaultyReturnableSaviour();
        liquidationEngine.connectCDPSaviour(address(saviour));
    }
    function test_liquidate_reentrant_saviour() public {
        ReentrantSaviour saviour = new ReentrantSaviour(address(liquidationEngine));
        liquidationEngine.connectCDPSaviour(address(saviour));
        liquidationEngine.protectCDP("gold", me, address(saviour));
        assertTrue(liquidationEngine.chosenCDPSaviour("gold", me) == address(saviour));
        liquidateCDP();
    }
    function test_liquidate_genuine_saviour() public {
        cdpEngine.modifyParameters("gold", "safetyPrice", ray(5 ether));

        GenuineSaviour saviour = new GenuineSaviour(address(cdpEngine), address(liquidationEngine));
        liquidationEngine.connectCDPSaviour(address(saviour));
        liquidationEngine.protectCDP("gold", me, address(saviour));
        cdpEngine.approveCDPModification(address(saviour));
        assertTrue(liquidationEngine.chosenCDPSaviour("gold", me) == address(saviour));

        gold.mint(10000 ether);
        collateralA.join(address(this), 10000 ether);
        cdpEngine.transferCollateral("gold", me, address(saviour), 10900 ether);

        liquidateSavedCDP();

        (uint256 lockedCollateral, ) = cdpEngine.cdps("gold", me);
        assertEq(lockedCollateral, 10910 ether);
    }
}
