// GlobalSettlement.t.sol

// Copyright (C) 2017  DappHub, LLC
// Copyright (C) 2018 Rain <rainbreak@riseup.net>
// Copyright (C) 2018 Lev Livnev <lev@liv.nev.org.uk>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity 0.6.7;

import "ds-test/test.sol";
import "ds-token/delegate.sol";

import {SAFEEngine} from '../SAFEEngine.sol';
import {LiquidationEngine} from '../LiquidationEngine.sol';
import {AccountingEngine} from '../AccountingEngine.sol';
import {CoinSavingsAccount} from '../CoinSavingsAccount.sol';
import {StabilityFeeTreasury}  from '../StabilityFeeTreasury.sol';
import {EnglishCollateralAuctionHouse, FixedDiscountCollateralAuctionHouse} from '../CollateralAuctionHouse.sol';
import {BurningSurplusAuctionHouse} from '../SurplusAuctionHouse.sol';
import {DebtAuctionHouse} from '../DebtAuctionHouse.sol';
import {SettlementSurplusAuctioneer} from "../SettlementSurplusAuctioneer.sol";
import {BasicCollateralJoin, CoinJoin} from '../BasicTokenAdapters.sol';
import {GlobalSettlement}  from '../GlobalSettlement.sol';
import {OracleRelayer} from '../OracleRelayer.sol';

abstract contract Hevm {
    function warp(uint256) virtual public;
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
    GlobalSettlement public globalSettlement;

    constructor(SAFEEngine safeEngine_, GlobalSettlement globalSettlement_) public {
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
}

contract GlobalSettlementTest is DSTest {
    Hevm hevm;

    SAFEEngine safeEngine;
    GlobalSettlement globalSettlement;
    AccountingEngine accountingEngine;
    LiquidationEngine liquidationEngine;
    OracleRelayer oracleRelayer;
    CoinSavingsAccount coinSavingsAccount;
    StabilityFeeTreasury stabilityFeeTreasury;
    SettlementSurplusAuctioneer postSettlementSurplusDrain;

    DSDelegateToken protocolToken;
    DSDelegateToken systemCoin;
    CoinJoin systemCoinA;

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

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine = new SAFEEngine();
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

        coinSavingsAccount = new CoinSavingsAccount(address(safeEngine));

        oracleRelayer = new OracleRelayer(address(safeEngine));
        safeEngine.modifyParameters("globalDebtCeiling", rad(10000000 ether));
        safeEngine.addAuthorization(address(oracleRelayer));

        stabilityFeeTreasury = new StabilityFeeTreasury(address(safeEngine), address(accountingEngine), address(systemCoinA));

        globalSettlement = new GlobalSettlement();
        globalSettlement.modifyParameters("safeEngine", address(safeEngine));
        globalSettlement.modifyParameters("liquidationEngine", address(liquidationEngine));
        globalSettlement.modifyParameters("accountingEngine", address(accountingEngine));
        globalSettlement.modifyParameters("oracleRelayer", address(oracleRelayer));
        globalSettlement.modifyParameters("shutdownCooldown", 1 hours);
        safeEngine.addAuthorization(address(globalSettlement));
        accountingEngine.addAuthorization(address(globalSettlement));
        oracleRelayer.addAuthorization(address(globalSettlement));
        coinSavingsAccount.addAuthorization(address(globalSettlement));
        liquidationEngine.addAuthorization(address(globalSettlement));
        stabilityFeeTreasury.addAuthorization(address(globalSettlement));
        surplusAuctionHouseOne.addAuthorization(address(accountingEngine));
        debtAuctionHouse.addAuthorization(address(accountingEngine));
    }
    function test_shutdown_basic() public {
        assertEq(globalSettlement.contractEnabled(), 1);
        assertEq(safeEngine.contractEnabled(), 1);
        assertEq(liquidationEngine.contractEnabled(), 1);
        assertEq(oracleRelayer.contractEnabled(), 1);
        assertEq(accountingEngine.contractEnabled(), 1);
        assertEq(accountingEngine.debtAuctionHouse().contractEnabled(), 1);
        assertEq(accountingEngine.surplusAuctionHouse().contractEnabled(), 1);
        globalSettlement.shutdownSystem();
        assertEq(globalSettlement.contractEnabled(), 0);
        assertEq(safeEngine.contractEnabled(), 0);
        assertEq(liquidationEngine.contractEnabled(), 0);
        assertEq(accountingEngine.contractEnabled(), 0);
        assertEq(oracleRelayer.contractEnabled(), 0);
        assertEq(accountingEngine.debtAuctionHouse().contractEnabled(), 0);
        assertEq(accountingEngine.surplusAuctionHouse().contractEnabled(), 0);
    }
    function test_shutdown_savings_account_and_rate_setter_set() public {
        globalSettlement.modifyParameters("coinSavingsAccount", address(coinSavingsAccount));
        globalSettlement.modifyParameters("stabilityFeeTreasury", address(stabilityFeeTreasury));
        assertEq(globalSettlement.contractEnabled(), 1);
        assertEq(safeEngine.contractEnabled(), 1);
        assertEq(liquidationEngine.contractEnabled(), 1);
        assertEq(oracleRelayer.contractEnabled(), 1);
        assertEq(accountingEngine.contractEnabled(), 1);
        assertEq(accountingEngine.debtAuctionHouse().contractEnabled(), 1);
        assertEq(accountingEngine.surplusAuctionHouse().contractEnabled(), 1);
        assertEq(coinSavingsAccount.contractEnabled(), 1);
        assertEq(stabilityFeeTreasury.contractEnabled(), 1);
        globalSettlement.shutdownSystem();
        assertEq(globalSettlement.contractEnabled(), 0);
        assertEq(safeEngine.contractEnabled(), 0);
        assertEq(liquidationEngine.contractEnabled(), 0);
        assertEq(accountingEngine.contractEnabled(), 0);
        assertEq(oracleRelayer.contractEnabled(), 0);
        assertEq(accountingEngine.debtAuctionHouse().contractEnabled(), 0);
        assertEq(accountingEngine.surplusAuctionHouse().contractEnabled(), 0);
        assertEq(stabilityFeeTreasury.contractEnabled(), 0);
        assertEq(coinSavingsAccount.contractEnabled(), 0);
    }
    // -- Scenario where there is one over-collateralised SAFE
    // -- and there is no AccountingEngine deficit or surplus
    function test_shutdown_collateralised() public {
        CollateralType memory gold = init_collateral("gold", "gold");

        Usr ali = new Usr(safeEngine, globalSettlement);

        // make a SAFE:
        address safe1 = address(ali);
        gold.collateralA.join(safe1, 10 ether);
        ali.modifySAFECollateralization("gold", safe1, safe1, safe1, 10 ether, 15 ether);

        // global checks:
        assertEq(safeEngine.globalDebt(), rad(15 ether));
        assertEq(safeEngine.globalUnbackedDebt(), 0);

        // collateral price is 5
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(5 * WAD));
        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");
        globalSettlement.processSAFE("gold", safe1);

        // local checks:
        assertEq(globalSettlement.finalCoinPerCollateralPrice("gold"), ray(0.2 ether));
        assertEq(generatedDebt("gold", safe1), 0);
        assertEq(lockedCollateral("gold", safe1), 7 ether);
        assertEq(safeEngine.debtBalance(address(accountingEngine)), rad(15 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), rad(15 ether));
        assertEq(safeEngine.globalUnbackedDebt(), rad(15 ether));

        // SAFE closing
        ali.freeCollateral("gold");
        assertEq(lockedCollateral("gold", safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 7 ether);
        ali.exit(gold.collateralA, address(this), 7 ether);

        hevm.warp(now + 1 hours);
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);

        // coin redemption
        ali.approveSAFEModification(address(globalSettlement));
        ali.prepareCoinsForRedeeming(15 ether);
        accountingEngine.settleDebt(rad(15 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), 0);
        assertEq(safeEngine.globalUnbackedDebt(), 0);

        ali.redeemCollateral("gold", 15 ether);

        // local checks:
        assertEq(coinBalance(safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 3 ether);
        ali.exit(gold.collateralA, address(this), 3 ether);

        assertEq(tokenCollateral("gold", address(globalSettlement)), 0);
        assertEq(balanceOf("gold", address(gold.collateralA)), 0);
    }

    // -- Scenario where there is one over-collateralised and one
    // -- under-collateralised SAFE, and no AccountingEngine deficit or surplus
    function test_shutdown_undercollateralised() public {
        CollateralType memory gold = init_collateral("gold", "gold");

        Usr ali = new Usr(safeEngine, globalSettlement);
        Usr bob = new Usr(safeEngine, globalSettlement);

        // make a SAFE:
        address safe1 = address(ali);
        gold.collateralA.join(safe1, 10 ether);
        ali.modifySAFECollateralization("gold", safe1, safe1, safe1, 10 ether, 15 ether);

        // make a second SAFE:
        address safe2 = address(bob);
        gold.collateralA.join(safe2, 1 ether);
        bob.modifySAFECollateralization("gold", safe2, safe2, safe2, 1 ether, 3 ether);

        // global checks:
        assertEq(safeEngine.globalDebt(), rad(18 ether));
        assertEq(safeEngine.globalUnbackedDebt(), 0);

        // collateral price is 2
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(2 * WAD));
        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");
        globalSettlement.processSAFE("gold", safe1);  // over-collateralised
        globalSettlement.processSAFE("gold", safe2);  // under-collateralised

        // local checks
        assertEq(generatedDebt("gold", safe1), 0);
        assertEq(lockedCollateral("gold", safe1), 2.5 ether);
        assertEq(generatedDebt("gold", safe2), 0);
        assertEq(lockedCollateral("gold", safe2), 0);
        assertEq(safeEngine.debtBalance(address(accountingEngine)), rad(18 ether));

        // global checks
        assertEq(safeEngine.globalDebt(), rad(18 ether));
        assertEq(safeEngine.globalUnbackedDebt(), rad(18 ether));

        // SAFE closing
        ali.freeCollateral("gold");
        assertEq(lockedCollateral("gold", safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 2.5 ether);
        ali.exit(gold.collateralA, address(this), 2.5 ether);

        hevm.warp(now + 1 hours);
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);

        // first coin redemption
        ali.approveSAFEModification(address(globalSettlement));
        ali.prepareCoinsForRedeeming(15 ether);
        accountingEngine.settleDebt(rad(15 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), rad(3 ether));
        assertEq(safeEngine.globalUnbackedDebt(), rad(3 ether));

        ali.redeemCollateral("gold", 15 ether);

        // local checks:
        assertEq(coinBalance(safe1), 0);
        uint fix = globalSettlement.collateralCashPrice("gold");
        assertEq(tokenCollateral("gold", safe1), rmultiply(fix, 15 ether));
        ali.exit(gold.collateralA, address(this), uint(rmultiply(fix, 15 ether)));

        // second coin redemption
        bob.approveSAFEModification(address(globalSettlement));
        bob.prepareCoinsForRedeeming(3 ether);
        accountingEngine.settleDebt(rad(3 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), 0);
        assertEq(safeEngine.globalUnbackedDebt(), 0);

        bob.redeemCollateral("gold", 3 ether);

        // local checks:
        assertEq(coinBalance(safe2), 0);
        assertEq(tokenCollateral("gold", safe2), rmultiply(fix, 3 ether));
        bob.exit(gold.collateralA, address(this), uint(rmultiply(fix, 3 ether)));

        // some dust remains in GlobalSettlement because of rounding:
        assertEq(tokenCollateral("gold", address(globalSettlement)), 1);
        assertEq(balanceOf("gold", address(gold.collateralA)), 1);
    }

    // -- Scenario where there is one collateralised SAFE
    // -- undergoing auction at the time of shutdown
    function test_shutdown_fast_track_english_auction() public {
        CollateralType memory gold = init_collateral("gold", "gold");

        Usr ali = new Usr(safeEngine, globalSettlement);

        // make a SAFE:
        address safe1 = address(ali);
        gold.collateralA.join(safe1, 10 ether);
        ali.modifySAFECollateralization("gold", safe1, safe1, safe1, 10 ether, 15 ether);

        safeEngine.modifyParameters("gold", "safetyPrice", ray(1 ether));
        safeEngine.modifyParameters("gold", "liquidationPrice", ray(1 ether)); // now unsafe

        uint auction = liquidationEngine.liquidateSAFE("gold", safe1); // SAFE liquidated
        assertEq(safeEngine.globalUnbackedDebt(), rad(15 ether));     // now there is bad debt
        // get 1 coin from ali
        ali.transferInternalCoins(address(ali), address(this), rad(1 ether));
        safeEngine.approveSAFEModification(address(gold.englishCollateralAuctionHouse));
        gold.englishCollateralAuctionHouse.increaseBidSize(auction, 10 ether, rad(1 ether)); // bid 1 coin
        assertEq(coinBalance(safe1), 14 ether);

        // collateral price is 5
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(5 * WAD));
        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");

        globalSettlement.fastTrackAuction("gold", auction);
        assertEq(coinBalance(address(this)), 1 ether);       // bid refunded
        safeEngine.transferInternalCoins(address(this), safe1, rad(1 ether)); // return 1 coin to ali

        globalSettlement.processSAFE("gold", safe1);

        // local checks:
        assertEq(generatedDebt("gold", safe1), 0);
        assertEq(lockedCollateral("gold", safe1), 7 ether);
        assertEq(safeEngine.debtBalance(address(accountingEngine)), rad(30 ether));

        // balance the accountingEngine
        accountingEngine.settleDebt(minimum(safeEngine.coinBalance(address(accountingEngine)), safeEngine.debtBalance(address(accountingEngine))));
        // global checks:
        assertEq(safeEngine.globalDebt(), rad(15 ether));
        assertEq(safeEngine.globalUnbackedDebt(), rad(15 ether));

        // SAFE closing
        ali.freeCollateral("gold");
        assertEq(lockedCollateral("gold", safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 7 ether);
        ali.exit(gold.collateralA, address(this), 7 ether);

        hevm.warp(now + 1 hours);
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);

        // coin redemption
        ali.approveSAFEModification(address(globalSettlement));
        ali.prepareCoinsForRedeeming(15 ether);
        accountingEngine.settleDebt(rad(15 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), 0);
        assertEq(safeEngine.globalUnbackedDebt(), 0);

        ali.redeemCollateral("gold", 15 ether);

        // local checks:
        assertEq(coinBalance(safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 3 ether);
        ali.exit(gold.collateralA, address(this), 3 ether);

        assertEq(tokenCollateral("gold", address(globalSettlement)), 0);
        assertEq(balanceOf("gold", address(gold.collateralA)), 0);
    }

    function test_shutdown_fast_track_fixed_discount_auction() public {
        CollateralType memory gold = init_collateral("gold", "gold");
        // swap auction house in the liquidation engine
        liquidationEngine.modifyParameters("gold", "collateralAuctionHouse", address(gold.fixedDiscountCollateralAuctionHouse));

        Usr ali = new Usr(safeEngine, globalSettlement);

        // make a SAFE:
        address safe1 = address(ali);
        gold.collateralA.join(safe1, 10 ether);
        ali.modifySAFECollateralization("gold", safe1, safe1, safe1, 10 ether, 15 ether);

        safeEngine.modifyParameters("gold", "safetyPrice", ray(1 ether));
        safeEngine.modifyParameters("gold", "liquidationPrice", ray(1 ether)); // now unsafe

        uint auction = liquidationEngine.liquidateSAFE("gold", safe1); // SAFE liquidated
        assertEq(safeEngine.globalUnbackedDebt(), rad(15 ether));      // now there is bad debt
        // get 5 coins from ali
        ali.transferInternalCoins(address(ali), address(this), rad(5 ether));
        safeEngine.approveSAFEModification(address(gold.fixedDiscountCollateralAuctionHouse));
        gold.fixedDiscountCollateralAuctionHouse.buyCollateral(auction, 5 ether);

        assertEq(coinBalance(safe1), 10 ether);

        // collateral price is 5
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(5 * WAD));
        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");

        globalSettlement.fastTrackAuction("gold", auction);
        assertEq(coinBalance(address(this)), 0);       // bid refunded

        globalSettlement.processSAFE("gold", safe1);

        // local checks:
        assertEq(generatedDebt("gold", safe1), 0);
        assertEq(lockedCollateral("gold", safe1), 7973684210526315790);
        assertEq(safeEngine.debtBalance(address(accountingEngine)), rad(20 ether));

        // balance the accountingEngine
        accountingEngine.settleDebt(minimum(safeEngine.coinBalance(address(accountingEngine)), safeEngine.debtBalance(address(accountingEngine))));
        // global checks:
        assertEq(safeEngine.globalDebt(), rad(10 ether));
        assertEq(safeEngine.globalUnbackedDebt(), rad(10 ether));

        // SAFE closing
        ali.freeCollateral("gold");
        assertEq(lockedCollateral("gold", safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 7973684210526315790);
        ali.exit(gold.collateralA, address(this), 7973684210526315790);

        hevm.warp(now + 1 hours);
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);

        // coin redemption
        ali.approveSAFEModification(address(globalSettlement));
        ali.prepareCoinsForRedeeming(10 ether);
        accountingEngine.settleDebt(rad(10 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), 0);
        assertEq(safeEngine.globalUnbackedDebt(), 0);

        ali.redeemCollateral("gold", 10 ether);

        // local checks:
        assertEq(coinBalance(safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 2000000000000000000);
        ali.exit(gold.collateralA, address(this), 2000000000000000000);
        gold.collateralA.exit(address(this), 26315789473684210);

        assertEq(tokenCollateral("gold", address(globalSettlement)), 0);
        assertEq(balanceOf("gold", address(gold.collateralA)), 0);
    }

    // -- Scenario where there is one over-collateralised SAFE
    // -- and there is a deficit in the AccountingEngine
    function test_shutdown_collateralised_deficit() public {
        CollateralType memory gold = init_collateral("gold", "gold");

        Usr ali = new Usr(safeEngine, globalSettlement);

        // make a SAFE:
        address safe1 = address(ali);
        gold.collateralA.join(safe1, 10 ether);
        ali.modifySAFECollateralization("gold", safe1, safe1, safe1, 10 ether, 15 ether);

        // create 1 unbacked coin and give to ali
        safeEngine.createUnbackedDebt(address(accountingEngine), address(ali), rad(1 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), rad(16 ether));
        assertEq(safeEngine.globalUnbackedDebt(), rad(1 ether));

        // collateral price is 5
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(5 * WAD));
        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");
        globalSettlement.processSAFE("gold", safe1);

        // local checks:
        assertEq(generatedDebt("gold", safe1), 0);
        assertEq(lockedCollateral("gold", safe1), 7 ether);
        assertEq(safeEngine.debtBalance(address(accountingEngine)), rad(16 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), rad(16 ether));
        assertEq(safeEngine.globalUnbackedDebt(), rad(16 ether));

        // SAFE closing
        ali.freeCollateral("gold");
        assertEq(lockedCollateral("gold", safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 7 ether);
        ali.exit(gold.collateralA, address(this), 7 ether);

        hevm.warp(now + 1 hours);
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);

        // coin redemption
        ali.approveSAFEModification(address(globalSettlement));
        ali.prepareCoinsForRedeeming(16 ether);
        accountingEngine.settleDebt(rad(16 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), 0);
        assertEq(safeEngine.globalUnbackedDebt(), 0);

        ali.redeemCollateral("gold", 16 ether);

        // local checks:
        assertEq(coinBalance(safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 3 ether);
        ali.exit(gold.collateralA, address(this), 3 ether);

        assertEq(tokenCollateral("gold", address(globalSettlement)), 0);
        assertEq(balanceOf("gold", address(gold.collateralA)), 0);
    }

    function test_shutdown_process_safe_has_bug() public {
        CollateralType memory gold = init_collateral("gold", "gold");

        Usr ali = new Usr(safeEngine, globalSettlement);
        Usr bob = new Usr(safeEngine, globalSettlement);
        Usr charlie = new Usr(safeEngine, globalSettlement);

        // make a SAFE:
        address safe1 = address(ali);
        gold.collateralA.join(safe1, 10 ether);
        ali.modifySAFECollateralization("gold", safe1, safe1, safe1, 10 ether, 15 ether);

        // transfer coins
        ali.transferInternalCoins(address(ali), address(charlie), rad(2 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), rad(15 ether));
        assertEq(safeEngine.globalUnbackedDebt(), 0);

        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");

        // local checks:
        assertEq(globalSettlement.finalCoinPerCollateralPrice("gold"), ray(0.2 ether));
        assertEq(generatedDebt("gold", safe1), 15 ether);
        assertEq(lockedCollateral("gold", safe1), 10 ether);
        assertEq(safeEngine.debtBalance(address(accountingEngine)), 0);

        // global checks:
        assertEq(safeEngine.globalDebt(), rad(15 ether));
        assertEq(safeEngine.globalUnbackedDebt(), 0);

        // transfer the remaining surplus with transferPostSettlementSurplus and continue the settlement process
        hevm.warp(now + 1 hours);
        accountingEngine.transferPostSettlementSurplus();
        assertEq(globalSettlement.outstandingCoinSupply(), 0);
        globalSettlement.setOutstandingCoinSupply();

        // finish processing
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);

        // checks
        assertEq(safeEngine.tokenCollateral("gold", address(globalSettlement)), 0);
        assertEq(tokenCollateral("gold", address(ali)), 0);
        assertEq(tokenCollateral("gold", address(charlie)), 0);

        charlie.approveSAFEModification(address(globalSettlement));
        assertEq(safeEngine.coinBalance(address(charlie)), rad(2 ether));
    }

    function test_shutdown_overcollateralized_surplus_smaller_redemption() public {
        CollateralType memory gold = init_collateral("gold", "gold");

        Usr ali = new Usr(safeEngine, globalSettlement);
        Usr bob = new Usr(safeEngine, globalSettlement);
        Usr charlie = new Usr(safeEngine, globalSettlement);

        // make a SAFE:
        address safe1 = address(ali);
        gold.collateralA.join(safe1, 10 ether);
        ali.modifySAFECollateralization("gold", safe1, safe1, safe1, 10 ether, 15 ether);

        // create surplus and also transfer to charlie
        ali.transferInternalCoins(address(ali), address(accountingEngine), rad(2 ether));
        ali.transferInternalCoins(address(ali), address(charlie), rad(2 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), rad(15 ether));
        assertEq(safeEngine.globalUnbackedDebt(), 0);

        // collateral price is 5
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(5 * WAD));
        // redemption price is 0.5
        oracleRelayer.modifyParameters("redemptionPrice", ray(0.5 ether));

        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");
        globalSettlement.processSAFE("gold", safe1);

        // local checks:
        assertEq(globalSettlement.finalCoinPerCollateralPrice("gold"), ray(0.1 ether));
        assertEq(generatedDebt("gold", safe1), 0);
        assertEq(lockedCollateral("gold", safe1), 8.5 ether);
        assertEq(safeEngine.debtBalance(address(accountingEngine)), rad(15 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), rad(15 ether));
        assertEq(safeEngine.globalUnbackedDebt(), rad(15 ether));

        // SAFE closing
        ali.freeCollateral("gold");
        assertEq(lockedCollateral("gold", safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 8.5 ether);
        ali.exit(gold.collateralA, address(this), 8.5 ether);

        hevm.warp(now + 1 hours);
        accountingEngine.settleDebt(safeEngine.coinBalance(address(accountingEngine)));
        assertEq(globalSettlement.outstandingCoinSupply(), 0);
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);
        assertEq(safeEngine.tokenCollateral("gold", address(globalSettlement)), 1.5 ether);

        // coin redemption
        assertEq(tokenCollateral("gold", address(ali)), 0);
        assertEq(tokenCollateral("gold", address(charlie)), 0);

        ali.approveSAFEModification(address(globalSettlement));
        assertEq(safeEngine.coinBalance(address(ali)), rad(11 ether));
        ali.prepareCoinsForRedeeming(11 ether);

        charlie.approveSAFEModification(address(globalSettlement));
        assertEq(safeEngine.coinBalance(address(charlie)), rad(2 ether));
        charlie.prepareCoinsForRedeeming(2 ether);

        ali.redeemCollateral("gold", 11 ether);
        charlie.redeemCollateral("gold", 2 ether);

        assertEq(safeEngine.globalDebt(), rad(13 ether));
        assertEq(safeEngine.globalUnbackedDebt(), rad(13 ether));

        // local checks:
        assertEq(coinBalance(safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 1269230769230769230);
        ali.exit(gold.collateralA, address(this), tokenCollateral("gold", safe1));

        assertEq(tokenCollateral("gold", address(charlie)), 230769230769230769);
        charlie.exit(gold.collateralA, address(this), tokenCollateral("gold", address(charlie)));

        assertEq(tokenCollateral("gold", address(globalSettlement)), 1);
        assertEq(balanceOf("gold", address(gold.collateralA)), 1);

        assertEq(coinBalance(address(postSettlementSurplusDrain)), 0);
    }

    function test_shutdown_overcollateralized_surplus_bigger_redemption() public {
        CollateralType memory gold = init_collateral("gold", "gold");

        Usr ali = new Usr(safeEngine, globalSettlement);
        Usr bob = new Usr(safeEngine, globalSettlement);
        Usr charlie = new Usr(safeEngine, globalSettlement);

        // make a SAFE:
        address safe1 = address(ali);
        gold.collateralA.join(safe1, 10 ether);
        ali.modifySAFECollateralization("gold", safe1, safe1, safe1, 10 ether, 15 ether);

        // create surplus and also transfer to charlie
        ali.transferInternalCoins(address(ali), address(accountingEngine), rad(2 ether));
        ali.transferInternalCoins(address(ali), address(charlie), rad(2 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), rad(15 ether));
        assertEq(safeEngine.globalUnbackedDebt(), 0);

        // collateral price is 5
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(5 * WAD));
        // redemption price is 0.5
        oracleRelayer.modifyParameters("redemptionPrice", ray(2 ether));

        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");
        globalSettlement.processSAFE("gold", safe1);

        // local checks:
        assertEq(globalSettlement.finalCoinPerCollateralPrice("gold"), ray(0.4 ether));
        assertEq(generatedDebt("gold", safe1), 0);
        assertEq(lockedCollateral("gold", safe1), 4 ether);
        assertEq(safeEngine.debtBalance(address(accountingEngine)), rad(15 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), rad(15 ether));
        assertEq(safeEngine.globalUnbackedDebt(), rad(15 ether));

        // SAFE closing
        ali.freeCollateral("gold");
        assertEq(lockedCollateral("gold", safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 4 ether);
        ali.exit(gold.collateralA, address(this), 4 ether);

        hevm.warp(now + 1 hours);
        accountingEngine.settleDebt(safeEngine.coinBalance(address(accountingEngine)));
        assertEq(globalSettlement.outstandingCoinSupply(), 0);
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);
        assertEq(safeEngine.tokenCollateral("gold", address(globalSettlement)), 6 ether);

        // coin redemption
        assertEq(tokenCollateral("gold", address(ali)), 0);
        assertEq(tokenCollateral("gold", address(charlie)), 0);

        ali.approveSAFEModification(address(globalSettlement));
        assertEq(safeEngine.coinBalance(address(ali)), rad(11 ether));
        ali.prepareCoinsForRedeeming(11 ether);

        charlie.approveSAFEModification(address(globalSettlement));
        assertEq(safeEngine.coinBalance(address(charlie)), rad(2 ether));
        charlie.prepareCoinsForRedeeming(2 ether);

        ali.redeemCollateral("gold", 11 ether);
        charlie.redeemCollateral("gold", 2 ether);

        assertEq(safeEngine.globalDebt(), rad(13 ether));
        assertEq(safeEngine.globalUnbackedDebt(), rad(13 ether));

        // local checks:
        assertEq(coinBalance(safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 5076923076923076923);
        ali.exit(gold.collateralA, address(this), tokenCollateral("gold", safe1));

        assertEq(tokenCollateral("gold", address(charlie)), 923076923076923076);
        charlie.exit(gold.collateralA, address(this), tokenCollateral("gold", address(charlie)));

        assertEq(tokenCollateral("gold", address(globalSettlement)), 1);
        assertEq(balanceOf("gold", address(gold.collateralA)), 1);

        assertEq(coinBalance(address(postSettlementSurplusDrain)), 0);
    }

    // -- Scenario where there is one over-collateralised SAFE
    // -- and one under-collateralised SAFE and there is a
    // -- surplus in the AccountingEngine
    function test_shutdown_over_and_under_collateralised_surplus() public {
        CollateralType memory gold = init_collateral("gold", "gold");

        Usr ali = new Usr(safeEngine, globalSettlement);
        Usr bob = new Usr(safeEngine, globalSettlement);

        // make a SAFE:
        address safe1 = address(ali);
        gold.collateralA.join(safe1, 10 ether);
        ali.modifySAFECollateralization("gold", safe1, safe1, safe1, 10 ether, 15 ether);

        // alice gives one coin to the accountingEngine, creating surplus
        ali.transferInternalCoins(address(ali), address(accountingEngine), rad(1 ether));
        assertEq(safeEngine.coinBalance(address(accountingEngine)), rad(1 ether));

        // make a second SAFE:
        address safe2 = address(bob);
        gold.collateralA.join(safe2, 1 ether);
        bob.modifySAFECollateralization("gold", safe2, safe2, safe2, 1 ether, 3 ether);

        // global checks:
        assertEq(safeEngine.globalDebt(), rad(18 ether));
        assertEq(safeEngine.globalUnbackedDebt(), 0);

        // collateral price is 2
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(2 * WAD));
        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");
        globalSettlement.processSAFE("gold", safe1);  // over-collateralised
        globalSettlement.processSAFE("gold", safe2);  // under-collateralised

        // local checks
        assertEq(generatedDebt("gold", safe1), 0);
        assertEq(lockedCollateral("gold", safe1), 2.5 ether);
        assertEq(generatedDebt("gold", safe2), 0);
        assertEq(lockedCollateral("gold", safe2), 0);
        assertEq(safeEngine.debtBalance(address(accountingEngine)), rad(18 ether));

        // global checks
        assertEq(safeEngine.globalDebt(), rad(18 ether));
        assertEq(safeEngine.globalUnbackedDebt(), rad(18 ether));

        // SAFE closing
        ali.freeCollateral("gold");
        assertEq(lockedCollateral("gold", safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 2.5 ether);
        ali.exit(gold.collateralA, address(this), 2.5 ether);

        hevm.warp(now + 1 hours);
        // balance the accountingEngine using transferPostSettlementSurplus
        accountingEngine.transferPostSettlementSurplus();
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);

        // first coin redemption
        ali.approveSAFEModification(address(globalSettlement));
        ali.prepareCoinsForRedeeming(coinBalance(address(ali)));
        accountingEngine.settleDebt(rad(14 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), rad(3 ether));
        assertEq(safeEngine.globalUnbackedDebt(), rad(3 ether));

        ali.redeemCollateral("gold", 14 ether);

        // local checks:
        assertEq(coinBalance(safe1), 0);
        uint256 fix = globalSettlement.collateralCashPrice("gold");
        assertEq(tokenCollateral("gold", safe1), uint(rmultiply(fix, 14 ether)));
        ali.exit(gold.collateralA, address(this), uint(rmultiply(fix, 14 ether)));

        // second coin redemption
        bob.approveSAFEModification(address(globalSettlement));
        bob.prepareCoinsForRedeeming(3 ether);
        accountingEngine.settleDebt(rad(3 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(), 0);
        assertEq(safeEngine.globalUnbackedDebt(), 0);

        bob.redeemCollateral("gold", 3 ether);

        // local checks:
        assertEq(coinBalance(safe2), 0);
        assertEq(tokenCollateral("gold", safe2), rmultiply(fix, 3 ether));
        bob.exit(gold.collateralA, address(this), uint(rmultiply(fix, 3 ether)));

        // nothing left in the GlobalSettlement
        assertEq(tokenCollateral("gold", address(globalSettlement)), 0);
        assertEq(balanceOf("gold", address(gold.collateralA)), 0);

        assertEq(coinBalance(address(postSettlementSurplusDrain)), 0);
    }

    // -- Scenario where there is one over-collateralised and one
    // -- under-collateralised SAFE of different collateral types
    // -- and no AccountingEngine deficit or surplus
    function test_shutdown_net_undercollateralised_multiple_collateralTypes() public {
        CollateralType memory gold = init_collateral("gold", "gold");
        CollateralType memory coal = init_collateral("coal", "coal");

        Usr ali = new Usr(safeEngine, globalSettlement);
        Usr bob = new Usr(safeEngine, globalSettlement);

        // make a SAFE:
        address safe1 = address(ali);
        gold.collateralA.join(safe1, 10 ether);
        ali.modifySAFECollateralization("gold", safe1, safe1, safe1, 10 ether, 15 ether);

        // make a second SAFE:
        address safe2 = address(bob);
        coal.collateralA.join(safe2, 1 ether);
        safeEngine.modifyParameters("coal", "safetyPrice", ray(5 ether));
        bob.modifySAFECollateralization("coal", safe2, safe2, safe2, 1 ether, 5 ether);

        gold.oracleSecurityModule.updateCollateralPrice(bytes32(2 * WAD));
        // safe1 has 20 coin of lockedCollateral and 15 coin of tab
        coal.oracleSecurityModule.updateCollateralPrice(bytes32(2 * WAD));
        // safe2 has 2 coin of lockedCollateral and 5 coin of tab
        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");
        globalSettlement.freezeCollateralType("coal");
        globalSettlement.processSAFE("gold", safe1);  // over-collateralised
        globalSettlement.processSAFE("coal", safe2);  // under-collateralised

        hevm.warp(now + 1 hours);
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        globalSettlement.calculateCashPrice("coal");

        ali.approveSAFEModification(address(globalSettlement));
        bob.approveSAFEModification(address(globalSettlement));

        assertEq(safeEngine.globalDebt(),             rad(20 ether));
        assertEq(safeEngine.globalUnbackedDebt(),             rad(20 ether));
        assertEq(safeEngine.debtBalance(address(accountingEngine)),  rad(20 ether));

        assertEq(globalSettlement.collateralTotalDebt("gold"), 15 ether);
        assertEq(globalSettlement.collateralTotalDebt("coal"),  5 ether);

        assertEq(globalSettlement.collateralShortfall("gold"),  0.0 ether);
        assertEq(globalSettlement.collateralShortfall("coal"),  1.5 ether);

        // there are 7.5 gold and 1 coal
        // the gold is worth 15 coin and the coal is worth 2 coin
        // the total collateral pool is worth 17 coin
        // the total outstanding debt is 20 coin
        // each coin should get (15/2)/20 gold and (2/2)/20 coal
        assertEq(globalSettlement.collateralCashPrice("gold"), ray(0.375 ether));
        assertEq(globalSettlement.collateralCashPrice("coal"), ray(0.050 ether));

        assertEq(tokenCollateral("gold", address(ali)), 0 ether);
        ali.prepareCoinsForRedeeming(1 ether);
        ali.redeemCollateral("gold", 1 ether);
        assertEq(tokenCollateral("gold", address(ali)), 0.375 ether);

        bob.prepareCoinsForRedeeming(1 ether);
        bob.redeemCollateral("coal", 1 ether);
        assertEq(tokenCollateral("coal", address(bob)), 0.05 ether);

        ali.exit(gold.collateralA, address(ali), 0.375 ether);
        bob.exit(coal.collateralA, address(bob), 0.05  ether);
        ali.prepareCoinsForRedeeming(1 ether);
        ali.redeemCollateral("gold", 1 ether);
        ali.redeemCollateral("coal", 1 ether);
        assertEq(tokenCollateral("gold", address(ali)), 0.375 ether);
        assertEq(tokenCollateral("coal", address(ali)), 0.05 ether);

        ali.exit(gold.collateralA, address(ali), 0.375 ether);
        ali.exit(coal.collateralA, address(ali), 0.05  ether);

        ali.prepareCoinsForRedeeming(1 ether);
        ali.redeemCollateral("gold", 1 ether);
        assertEq(globalSettlement.coinsUsedToRedeem("gold", address(ali)), 3 ether);
        assertEq(globalSettlement.coinsUsedToRedeem("coal", address(ali)), 1 ether);
        ali.prepareCoinsForRedeeming(1 ether);
        ali.redeemCollateral("coal", 1 ether);
        assertEq(globalSettlement.coinsUsedToRedeem("gold", address(ali)), 3 ether);
        assertEq(globalSettlement.coinsUsedToRedeem("coal", address(ali)), 2 ether);
        assertEq(tokenCollateral("gold", address(ali)), 0.375 ether);
        assertEq(tokenCollateral("coal", address(ali)), 0.05 ether);
    }

    // -- Scenario where calculateCashPrice() used to overflow
   function test_calculateCashPrice_overflow() public {
       CollateralType memory gold = init_collateral("gold", "gold");

       Usr ali = new Usr(safeEngine, globalSettlement);

       // make a SAFE:
       address safe1 = address(ali);
       gold.collateral.mint(500000000 ether);
       gold.collateralA.join(safe1, 500000000 ether);
       ali.modifySAFECollateralization("gold", safe1, safe1, safe1, 500000000 ether, 10000000 ether);
       // ali's urn has 500_000_000 collateral, 10^7 debt (and 10^7 system coins since rate == RAY)

       // global checks:
       assertEq(safeEngine.globalDebt(), rad(10000000 ether));
       assertEq(safeEngine.globalUnbackedDebt(), 0);

       // collateral price is 5
       gold.oracleSecurityModule.updateCollateralPrice(bytes32(5 * WAD));
       globalSettlement.shutdownSystem();
       globalSettlement.freezeCollateralType("gold");
       globalSettlement.processSAFE("gold", safe1);

       // local checks:
       assertEq(generatedDebt("gold", safe1), 0);
       assertEq(lockedCollateral("gold", safe1), 498000000 ether);
       assertEq(safeEngine.debtBalance(address(accountingEngine)), rad(10000000 ether));

       // global checks:
       assertEq(safeEngine.globalDebt(), rad(10000000 ether));
       assertEq(safeEngine.globalUnbackedDebt(), rad(10000000 ether));

       // SAFE closing
       ali.freeCollateral("gold");
       assertEq(lockedCollateral("gold", safe1), 0);
       assertEq(tokenCollateral("gold", safe1), 498000000 ether);
       ali.exit(gold.collateralA, address(this), 498000000 ether);

       hevm.warp(now + 1 hours);
       globalSettlement.setOutstandingCoinSupply();
       globalSettlement.calculateCashPrice("gold");
   }
}
