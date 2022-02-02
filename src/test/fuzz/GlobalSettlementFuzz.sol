pragma solidity ^0.6.7;

import {GlobalSettlementMock} from "./GlobalSettlementMock.sol";
import "./DelegateTOkenMock.sol";
import "../../../lib/ds-token/lib/ds-test/src/test.sol";

import {SAFEEngine} from  "../../single/SAFEEngine.sol";
import {SettlementSurplusAuctioneer} from "../../single/SettlementSurplusAuctioneer.sol";
import {LiquidationEngine} from '../../single/LiquidationEngine.sol';
import {AccountingEngine} from '../../single/AccountingEngine.sol';
import {StabilityFeeTreasury} from '../../single/StabilityFeeTreasury.sol';
import {EnglishCollateralAuctionHouse, FixedDiscountCollateralAuctionHouse} from '../../single/CollateralAuctionHouse.sol';
import {BurningSurplusAuctionHouse} from '../../single/SurplusAuctionHouse.sol';
import {DebtAuctionHouse} from '../../single/DebtAuctionHouse.sol';
import {SettlementSurplusAuctioneer} from "../../single/SettlementSurplusAuctioneer.sol";
import {BasicCollateralJoin, CoinJoin} from '../../shared/BasicTokenAdapters.sol';
import {GlobalSettlement}  from '../../single/GlobalSettlement.sol';
import {OracleRelayer, OracleLike} from '../../single/OracleRelayer.sol';


abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract SAFEEngineMock is SAFEEngine {
    constructor() public {}

    function setCoinBalance(address usr, uint rad) public {
        coinBalance[usr] += rad;
        globalDebt += rad;
    }

    function setDebt(address usr, uint rad) public {
        debtBalance[usr] = rad;
    }
}

contract DSThing is DSAuth, DSNote, DSMath {
    function S(string memory s) internal pure returns (bytes4) {
        return bytes4(keccak256(abi.encodePacked(s)));
    }
}

contract DummyFSM is DSThing {
    address public priceSource;
    bool validPrice;
    uint price;
    function getResultWithValidity() public view returns (uint256, bool) {
        return (price,validPrice);
    }
    function read() public view returns (uint256) {
        uint price_; bool validPrice_;
        (price_, validPrice_) = getResultWithValidity();
        require(validPrice_, "not-valid");
        return uint(price_);
    }
    function updateCollateralPrice(bytes32 newPrice) public note auth {
        price = uint(newPrice);
        validPrice = true;
    }
    function restart() public note auth {  // unset the value
        validPrice = false;
    }
}

contract Usr {
    SAFEEngine public safeEngine;
    GlobalSettlementMock public globalSettlement;

    constructor(SAFEEngine safeEngine_, GlobalSettlementMock globalSettlement_) public {
        safeEngine  = safeEngine_;
        globalSettlement  = globalSettlement_;
    }
    function modifySAFECollateralization(
      bytes32 collateralType,
      address safe,
      address collateralSrc,
      address debtDst,
      int deltaCollateral,
      int deltaDebt
    ) public {
        safeEngine.modifySAFECollateralization(
          collateralType, safe, collateralSrc, debtDst, deltaCollateral, deltaDebt
        );
    }
    function transferInternalCoins(address src, address dst, uint256 rad) public {
        safeEngine.transferInternalCoins(src, dst, rad);
    }
    function approveSAFEModification(address usr) public {
        safeEngine.approveSAFEModification(usr);
    }
    function exit(BasicCollateralJoin collateralA, address usr, uint wad) public {
        collateralA.exit(usr, wad);
    }
    function freeCollateral(bytes32 collateralType) public {
        globalSettlement.freeCollateral(collateralType);
    }
    function prepareCoinsForRedeeming(uint256 rad) public {
        globalSettlement.prepareCoinsForRedeeming(rad);
    }
    function redeemCollateral(bytes32 collateralType, uint wad) public {
        globalSettlement.redeemCollateral(collateralType, wad);
    }
}

contract Feed {
    address public priceSource;
    bool    validPrice;
    bytes32 price;
    constructor(bytes32 initPrice, bool initValid) public {
        price = initPrice;
        validPrice = initValid;
    }
    function getResultWithValidity() public view returns (bytes32, bool) {
        return (price,validPrice);
    }

    function read() public view returns (bytes32) {
        require(validPrice);
        return price;
    }
}

// @notice Fuzzing state changes
contract FuzzGlobalSettlement is DSTest {
    Hevm hevm= Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    SAFEEngineMock safeEngine;
    GlobalSettlementMock globalSettlement;
    AccountingEngine accountingEngine;
    LiquidationEngine liquidationEngine;
    OracleRelayer oracleRelayer;
    StabilityFeeTreasury stabilityFeeTreasury;
    SettlementSurplusAuctioneer postSettlementSurplusDrain;

    DSDelegateToken protocolToken;
    DSDelegateToken systemCoin;
    CoinJoin systemCoinA;
    CollateralType gold;

    struct CollateralType {
        DummyFSM oracleSecurityModule;
        DSDelegateToken collateral;
        BasicCollateralJoin collateralA;
        EnglishCollateralAuctionHouse englishCollateralAuctionHouse;
        FixedDiscountCollateralAuctionHouse fixedDiscountCollateralAuctionHouse;
    }

    mapping (bytes32 => CollateralType) collateralTypes;

    BurningSurplusAuctionHouse surplusAuctionHouseOne;
    DebtAuctionHouse debtAuctionHouse;

    uint constant WAD = 10 ** 18;
    uint constant RAY = 10 ** 27;

    constructor() public {
        safeEngine = new SAFEEngineMock();
        protocolToken = new DSDelegateToken('GOV', 'GOV');
        systemCoin = new DSDelegateToken("Coin", "Coin");
        systemCoinA = new CoinJoin(address(safeEngine), address(systemCoin));

        surplusAuctionHouseOne = new BurningSurplusAuctionHouse(address(safeEngine), address(protocolToken));

        safeEngine.approveSAFEModification(address(surplusAuctionHouseOne));

        protocolToken.approve(address(surplusAuctionHouseOne));

        debtAuctionHouse = new DebtAuctionHouse(address(safeEngine), address(protocolToken));

        safeEngine.addAuthorization(address(systemCoinA));
        systemCoin.mint(address(this), 50 ether);
        systemCoin.setOwner(address(systemCoinA));

        protocolToken.mint(200 ether);
        protocolToken.setOwner(address(debtAuctionHouse));

        accountingEngine = new AccountingEngine(address(safeEngine), address(surplusAuctionHouseOne), address(debtAuctionHouse));
        postSettlementSurplusDrain = new SettlementSurplusAuctioneer(address(accountingEngine), address(0));
        surplusAuctionHouseOne.addAuthorization(address(postSettlementSurplusDrain));

        accountingEngine.modifyParameters("postSettlementSurplusDrain", address(postSettlementSurplusDrain));
        safeEngine.addAuthorization(address(accountingEngine));

        surplusAuctionHouseOne.addAuthorization(address(accountingEngine));

        debtAuctionHouse.addAuthorization(address(accountingEngine));
        debtAuctionHouse.modifyParameters("accountingEngine", address(accountingEngine));

        liquidationEngine = new LiquidationEngine(address(safeEngine));
        liquidationEngine.modifyParameters("accountingEngine", address(accountingEngine));
        safeEngine.addAuthorization(address(liquidationEngine));
        accountingEngine.addAuthorization(address(liquidationEngine));

        oracleRelayer = new OracleRelayer(address(safeEngine));
        safeEngine.modifyParameters("globalDebtCeiling", rad(uint(-1)));
        safeEngine.addAuthorization(address(oracleRelayer));

        stabilityFeeTreasury = new StabilityFeeTreasury(address(safeEngine), address(accountingEngine), address(systemCoinA));

        globalSettlement = new GlobalSettlementMock();
        globalSettlement.modifyParameters("safeEngine", address(safeEngine));
        globalSettlement.modifyParameters("liquidationEngine", address(liquidationEngine));
        globalSettlement.modifyParameters("accountingEngine", address(accountingEngine));
        globalSettlement.modifyParameters("oracleRelayer", address(oracleRelayer));
        globalSettlement.modifyParameters("shutdownCooldown", 1 hours);
        globalSettlement.modifyParameters("stabilityFeeTreasury", address(stabilityFeeTreasury));
        safeEngine.addAuthorization(address(globalSettlement));
        accountingEngine.addAuthorization(address(globalSettlement));
        oracleRelayer.addAuthorization(address(globalSettlement));
        liquidationEngine.addAuthorization(address(globalSettlement));
        stabilityFeeTreasury.addAuthorization(address(globalSettlement));
        surplusAuctionHouseOne.addAuthorization(address(accountingEngine));
        debtAuctionHouse.addAuthorization(address(accountingEngine));

        gold = init_collateral("gold", "gold");
    }

    function setUp() public {} // dapp tools requirement


    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }
    function rad(uint wad) internal pure returns (uint) {
        return wad * RAY;
    }
    function rmultiply(uint x, uint y) internal pure returns (uint z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / RAY;
    }
    function rmultiply(int x, uint y) internal pure returns (int z) {
        z = x * int(y);
        require(y == 0 || z / int(y) == x);
        z = z / int(RAY);
    }
    function wdivide(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0);
        z = multiply(x, WAD) / y;
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function minimum(uint x, uint y) internal pure returns (uint z) {
        (x >= y) ? z = y : z = x;
    }
    function coinBalance(address safe) internal view returns (uint) {
        return uint(safeEngine.coinBalance(safe) / RAY);
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
    function debtAmount(bytes32 collateralType) internal view returns (uint) {
        (uint debtAmount_, uint accumulatedRate_, uint safetyPrice_, uint debtCeiling_, uint debtFloor_, uint liquidationPrice_)
          = safeEngine.collateralTypes(collateralType);
        accumulatedRate_; safetyPrice_; debtCeiling_; debtFloor_; liquidationPrice_;
        return debtAmount_;
    }
    function balanceOf(bytes32 collateralType, address usr) internal view returns (uint) {
        return collateralTypes[collateralType].collateral.balanceOf(usr);
    }

    function init_collateral(string memory name, bytes32 encodedName) internal returns (CollateralType memory) {
        DSDelegateToken newCollateral = new DSDelegateToken(name, name);
        newCollateral.mint(20 ether);

        DummyFSM oracleFSM = new DummyFSM();
        oracleRelayer.modifyParameters(encodedName, "orcl", address(oracleFSM));
        oracleRelayer.modifyParameters(encodedName, "safetyCRatio", ray(1.5 ether));
        oracleRelayer.modifyParameters(encodedName, "liquidationCRatio", ray(1.5 ether));

        // initial collateral price of 5
        oracleFSM.updateCollateralPrice(bytes32(5 * WAD));

        safeEngine.initializeCollateralType(encodedName);
        BasicCollateralJoin collateralA = new BasicCollateralJoin(address(safeEngine), encodedName, address(newCollateral));

        safeEngine.modifyParameters(encodedName, "safetyPrice", ray(3 ether));
        safeEngine.modifyParameters(encodedName, "liquidationPrice", ray(3 ether));
        safeEngine.modifyParameters(encodedName, "debtCeiling", rad(10000000 ether)); // 10M

        newCollateral.approve(address(collateralA));
        newCollateral.approve(address(safeEngine));

        safeEngine.addAuthorization(address(collateralA));

        EnglishCollateralAuctionHouse englishCollateralAuctionHouse =
          new EnglishCollateralAuctionHouse(address(safeEngine), address(liquidationEngine), encodedName);
        safeEngine.approveSAFEModification(address(englishCollateralAuctionHouse));
        englishCollateralAuctionHouse.addAuthorization(address(globalSettlement));
        englishCollateralAuctionHouse.addAuthorization(address(liquidationEngine));

        FixedDiscountCollateralAuctionHouse fixedDiscountCollateralAuctionHouse =
          new FixedDiscountCollateralAuctionHouse(address(safeEngine), address(liquidationEngine), encodedName);
        fixedDiscountCollateralAuctionHouse.modifyParameters("oracleRelayer", address(oracleRelayer));
        fixedDiscountCollateralAuctionHouse.modifyParameters("collateralFSM", address(new Feed(bytes32(uint256(200 ether)), true)));
        safeEngine.approveSAFEModification(address(fixedDiscountCollateralAuctionHouse));
        fixedDiscountCollateralAuctionHouse.addAuthorization(address(globalSettlement));
        fixedDiscountCollateralAuctionHouse.addAuthorization(address(liquidationEngine));

        // Start with English auction house
        liquidationEngine.addAuthorization(address(englishCollateralAuctionHouse));
        liquidationEngine.addAuthorization(address(fixedDiscountCollateralAuctionHouse));

        liquidationEngine.modifyParameters(encodedName, "collateralAuctionHouse", address(englishCollateralAuctionHouse));
        liquidationEngine.modifyParameters(encodedName, "liquidationPenalty", 1 ether);
        liquidationEngine.modifyParameters(encodedName, "liquidationQuantity", uint(-1) / ray(1 ether));

        collateralTypes[encodedName].oracleSecurityModule = oracleFSM;
        collateralTypes[encodedName].collateral = newCollateral;
        collateralTypes[encodedName].collateralA = collateralA;
        collateralTypes[encodedName].englishCollateralAuctionHouse = englishCollateralAuctionHouse;
        collateralTypes[encodedName].fixedDiscountCollateralAuctionHouse = fixedDiscountCollateralAuctionHouse;

        return collateralTypes[encodedName];
    }

    // test with dapp tools
    function test_fuzz_setup3() public {

        // make a SAFE:
        address safe1 = createSafe(10 ether, 15 ether);

        // collateral price is 5
        updateCollateralPrice(5 * WAD);
        shutdownSystem();
        freezeCollateralType("gold");
        processSAFE("gold", safe1);

        // SAFE closing
        freeCollateral(safe1, "gold");
        exit(safe1, gold.collateralA, address(this), 7 ether);

        hevm.warp(now + 1 hours);
        setOutstandingCoinSupply();
        calculateCashPrice("gold");

        // coin redemption
        prepareCoinsForRedeeming(safe1, 15 ether);
        settleDebt(rad(15 ether));

        redeemCollateral(safe1, "gold", 15 ether);
    }

    // actions
    // fuzz safe creation
    function createSafe(int col, int coin) public returns (address) {
        Usr ali = new Usr(safeEngine, globalSettlement);

        // make a SAFE:
        address safe = address(ali);
        gold.collateralA.join(safe, 10 ether);
        ali.modifySAFECollateralization("gold", safe, safe, safe, col, coin);
        ali.approveSAFEModification(address(globalSettlement));
        return safe;
    }

    function updateCollateralPrice(uint wad) public {
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(wad));
    }

    function shutdownSystem() public {
        globalSettlement.shutdownSystem();

        // these assertions will only be tested if the call above succeeds
        assert(globalSettlement.contractEnabled() == 0);
        assert(globalSettlement.shutdownTime() == now);
        assert(safeEngine.contractEnabled() == 0);
        assert(liquidationEngine.contractEnabled() == 0);
        assert(stabilityFeeTreasury.contractEnabled() == 0);
        assert(accountingEngine.contractEnabled() == 0);
        assert(oracleRelayer.contractEnabled() == 0);
    }

    function freezeCollateralType(bytes32 col) public {
        globalSettlement.freezeCollateralType(col);

        (OracleLike orcl,,) = oracleRelayer.collateralTypes(col);
        assert(globalSettlement.finalCoinPerCollateralPrice(col) == wdivide(oracleRelayer.redemptionPrice(), uint256(Feed(address(orcl)).read())));
    }

    function processSAFE(bytes32 col, address safe) public {
        globalSettlement.processSAFE(col, safe);

        assert(generatedDebt(col, safe) == 0);
    }

    function freeCollateral(address safe, bytes32 col) public {
        Usr(safe).freeCollateral(col);

        assert(lockedCollateral(col, safe) == 0);
    }

    function exit(address safe, BasicCollateralJoin join, address dst, uint wad) public {
        Usr(safe).exit(join, dst, wad);
    }

    function setOutstandingCoinSupply() public {
        globalSettlement.setOutstandingCoinSupply();

        assert(globalSettlement.outstandingCoinSupply() == safeEngine.globalDebt());
    }

    function calculateCashPrice(bytes32 col) public {
        globalSettlement.calculateCashPrice(col);
    }

    function prepareCoinsForRedeeming(address safe, uint wad) public {
        uint coinBag = globalSettlement.coinBag(safe);
        Usr(safe).prepareCoinsForRedeeming(wad);

        assert(globalSettlement.coinBag(safe) == coinBag + wad);
    }

    function redeemCollateral(address safe, bytes32 col, uint wad) public {
        Usr(safe).redeemCollateral(col, wad);

        assert(tokenCollateral(col, safe) != 0);
    }

    function settleDebt(uint rad) public {
        uint prevDebtBalance = safeEngine.debtBalance(address(accountingEngine));
        uint prevCoinBalance = safeEngine.coinBalance(address(accountingEngine));

        accountingEngine.settleDebt(rad);

        assert(safeEngine.debtBalance(address(accountingEngine)) == prevDebtBalance - rad);
        assert(safeEngine.coinBalance(address(accountingEngine)) == prevCoinBalance - rad);
    }

    function test_fuzz_debug3() public {
        createSafe(1,1);
        shutdownSystem();
        hevm.warp(now + 3600);
        setOutstandingCoinSupply();
        calculateCashPrice("gold");
    }
}