// GlobalSettlement.t.sol

// Copyright (C) 2017  DappHub, LLC
// Copyright (C) 2018 Rain <rainbreak@riseup.net>
// Copyright (C) 2018 Lev Livnev <lev@liv.nev.org.uk>
//
// This program is freeCollateral software: you can redistribute it and/or modify
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

pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";

import {CDPEngine} from '../CDPEngine.sol';
import {LiquidationEngine} from '../LiquidationEngine.sol';
import {AccountingEngine} from '../AccountingEngine.sol';
import {CoinSavingsAccount} from '../CoinSavingsAccount.sol';
import {StabilityFeeTreasury}  from '../StabilityFeeTreasury.sol';
import {EnglishCollateralAuctionHouse} from '../CollateralAuctionHouse.sol';
import {PreSettlementSurplusAuctionHouse} from '../SurplusAuctionHouse.sol';
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

contract DummyOSM is DSThing {
    bool    validPrice;
    bytes32 price;
    function getResultWithValidity() public view returns (bytes32, bool) {
        return (price,validPrice);
    }
    function read() public view returns (bytes32) {
        bytes32 price_; bool validPrice_;
        (price_, validPrice_) = getResultWithValidity();
        require(validPrice_, "not-valid");
        return price_;
    }
    function updateCollateralPrice(bytes32 newPrice) public note auth {
        price = newPrice;
        validPrice = true;
    }
    function restart() public note auth {  // unset the value
        validPrice = false;
    }
}

contract DexLike {
    uint256 amountToOffer;

    constructor(
      uint256 amountToOffer_
    ) public {
      amountToOffer = amountToOffer_;
    }

    function tkntkn(address systemCoin, address protocolToken, uint amountToSell) external returns (uint) {
        DSToken(systemCoin).transferFrom(msg.sender, address(this), amountToSell);
        DSToken(protocolToken).transfer(msg.sender, amountToOffer);
        return amountToOffer;
    }
}

contract Usr {
    CDPEngine public cdpEngine;
    GlobalSettlement public globalSettlement;

    constructor(CDPEngine cdpEngine_, GlobalSettlement globalSettlement_) public {
        cdpEngine  = cdpEngine_;
        globalSettlement  = globalSettlement_;
    }
    function modifyCDPCollateralization(
      bytes32 collateralType,
      address cdp,
      address collateralSrc,
      address debtDst,
      int deltaCollateral,
      int deltaDebt
    ) public {
        cdpEngine.modifyCDPCollateralization(
          collateralType, cdp, collateralSrc, debtDst, deltaCollateral, deltaDebt
        );
    }
    function transferInternalCoins(address src, address dst, uint256 rad) public {
        cdpEngine.transferInternalCoins(src, dst, rad);
    }
    function approveCDPModification(address usr) public {
        cdpEngine.approveCDPModification(usr);
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
contract MockRateSetter {
    uint public contractEnabled = 1;

    function addAuthorization(address addr) public {}

    function disableContract() public {
        contractEnabled = 0;
    }
}

contract Feed {
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

    CDPEngine cdpEngine;
    GlobalSettlement globalSettlement;
    AccountingEngine accountingEngine;
    LiquidationEngine liquidationEngine;
    OracleRelayer oracleRelayer;
    CoinSavingsAccount coinSavingsAccount;
    StabilityFeeTreasury stabilityFeeTreasury;
    SettlementSurplusAuctioneer postSettlementSurplusDrain;
    MockRateSetter rateSetter;

    DexLike dex;
    DSToken protocolToken;
    DSToken systemCoin;
    CoinJoin systemCoinA;

    struct CollateralType {
        DummyOSM oracleSecurityModule;
        DSToken collateral;
        BasicCollateralJoin collateralA;
        EnglishCollateralAuctionHouse collateralAuctionHouse;
    }

    mapping (bytes32 => CollateralType) collateralTypes;

    PreSettlementSurplusAuctionHouse surplusAuctionHouseOne;
    DebtAuctionHouse debtAuctionHouse;

    uint constant WAD = 10 ** 18;
    uint constant RAY = 10 ** 27;

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }
    function rad(uint wad) internal pure returns (uint) {
        return wad * RAY;
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / RAY;
    }
    function rmul(int x, uint y) internal pure returns (int z) {
        z = x * int(y);
        require(y == 0 || z / int(y) == x);
        z = z / int(RAY);
    }
    function min(uint x, uint y) internal pure returns (uint z) {
        (x >= y) ? z = y : z = x;
    }
    function coinBalance(address cdp) internal view returns (uint) {
        return uint(cdpEngine.coinBalance(cdp) / RAY);
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
    function debtAmount(bytes32 collateralType) internal view returns (uint) {
        (uint debtAmount_, uint accumulatedRates_, uint safetyPrice_, uint debtCeiling_, uint debtFloor_, uint liquidationPrice_)
          = cdpEngine.collateralTypes(collateralType);
        accumulatedRates_; safetyPrice_; debtCeiling_; debtFloor_; liquidationPrice_;
        return debtAmount_;
    }
    function balanceOf(bytes32 collateralType, address usr) internal view returns (uint) {
        return collateralTypes[collateralType].collateral.balanceOf(usr);
    }

    function init_collateral(bytes32 name) internal returns (CollateralType memory) {
        DSToken newCollateral = new DSToken(name);
        newCollateral.mint(20 ether);

        DummyOSM oracleOSM = new DummyOSM();
        oracleRelayer.modifyParameters(name, "orcl", address(oracleOSM));
        oracleRelayer.modifyParameters(name, "safetyCRatio", ray(1.5 ether));
        oracleRelayer.modifyParameters(name, "liquidationCRatio", ray(1.5 ether));

        // initial collateral price of 5
        oracleOSM.updateCollateralPrice(bytes32(5 * WAD));

        cdpEngine.initializeCollateralType(name);
        BasicCollateralJoin collateralA = new BasicCollateralJoin(address(cdpEngine), name, address(newCollateral));

        cdpEngine.modifyParameters(name, "safetyPrice", ray(3 ether));
        cdpEngine.modifyParameters(name, "debtCeiling", rad(1000 ether));

        newCollateral.approve(address(collateralA));
        newCollateral.approve(address(cdpEngine));

        cdpEngine.addAuthorization(address(collateralA));

        EnglishCollateralAuctionHouse collateralAuctionHouse = new EnglishCollateralAuctionHouse(address(cdpEngine), name);
        collateralAuctionHouse.modifyParameters("oracleRelayer", address(oracleRelayer));
        // bidToMarketPriceRatio is zero so feed price is irrelevant
        collateralAuctionHouse.modifyParameters("orcl", address(new Feed(bytes32(uint256(200 ether)), true)));
        cdpEngine.approveCDPModification(address(collateralAuctionHouse));
        collateralAuctionHouse.addAuthorization(address(globalSettlement));
        collateralAuctionHouse.addAuthorization(address(liquidationEngine));
        liquidationEngine.modifyParameters(name, "collateralAuctionHouse", address(collateralAuctionHouse));
        liquidationEngine.modifyParameters(name, "liquidationPenalty", ray(1 ether));
        liquidationEngine.modifyParameters(name, "collateralToSell", rad(15 ether));

        collateralTypes[name].oracleSecurityModule = oracleOSM;
        collateralTypes[name].collateral = newCollateral;
        collateralTypes[name].collateralA = collateralA;
        collateralTypes[name].collateralAuctionHouse = collateralAuctionHouse;

        return collateralTypes[name];
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        cdpEngine = new CDPEngine();
        protocolToken = new DSToken('GOV');
        systemCoin = new DSToken("Coin");
        dex = new DexLike(1 ether);
        systemCoinA = new CoinJoin(address(cdpEngine), address(systemCoin));

        surplusAuctionHouseOne = new PreSettlementSurplusAuctionHouse(address(cdpEngine), address(protocolToken));

        cdpEngine.approveCDPModification(address(surplusAuctionHouseOne));

        protocolToken.approve(address(surplusAuctionHouseOne));

        debtAuctionHouse = new DebtAuctionHouse(address(cdpEngine), address(protocolToken));

        cdpEngine.addAuthorization(address(systemCoinA));
        systemCoin.mint(address(this), 50 ether);
        systemCoin.setOwner(address(systemCoinA));

        protocolToken.mint(200 ether);
        protocolToken.push(address(dex), 200 ether);
        protocolToken.setOwner(address(debtAuctionHouse));

        accountingEngine = new AccountingEngine(address(cdpEngine), address(surplusAuctionHouseOne), address(debtAuctionHouse));
        postSettlementSurplusDrain = new SettlementSurplusAuctioneer(address(accountingEngine), address(0));
        surplusAuctionHouseOne.addAuthorization(address(postSettlementSurplusDrain));

        accountingEngine.modifyParameters("postSettlementSurplusDrain", address(postSettlementSurplusDrain));
        cdpEngine.addAuthorization(address(accountingEngine));

        surplusAuctionHouseOne.addAuthorization(address(accountingEngine));

        debtAuctionHouse.addAuthorization(address(accountingEngine));
        debtAuctionHouse.modifyParameters("accountingEngine", address(accountingEngine));

        liquidationEngine = new LiquidationEngine(address(cdpEngine));
        liquidationEngine.modifyParameters("accountingEngine", address(accountingEngine));
        cdpEngine.addAuthorization(address(liquidationEngine));
        accountingEngine.addAuthorization(address(liquidationEngine));

        coinSavingsAccount = new CoinSavingsAccount(address(cdpEngine));

        oracleRelayer = new OracleRelayer(address(cdpEngine));
        cdpEngine.modifyParameters("globalDebtCeiling", rad(1000 ether));
        cdpEngine.addAuthorization(address(oracleRelayer));

        stabilityFeeTreasury = new StabilityFeeTreasury(address(cdpEngine), address(accountingEngine), address(systemCoinA));

        rateSetter = new MockRateSetter();

        globalSettlement = new GlobalSettlement();
        globalSettlement.modifyParameters("cdpEngine", address(cdpEngine));
        globalSettlement.modifyParameters("liquidationEngine", address(liquidationEngine));
        globalSettlement.modifyParameters("accountingEngine", address(accountingEngine));
        globalSettlement.modifyParameters("oracleRelayer", address(oracleRelayer));
        globalSettlement.modifyParameters("shutdownCooldown", 1 hours);
        cdpEngine.addAuthorization(address(globalSettlement));
        accountingEngine.addAuthorization(address(globalSettlement));
        oracleRelayer.addAuthorization(address(globalSettlement));
        rateSetter.addAuthorization(address(globalSettlement));
        coinSavingsAccount.addAuthorization(address(globalSettlement));
        liquidationEngine.addAuthorization(address(globalSettlement));
        stabilityFeeTreasury.addAuthorization(address(globalSettlement));
        surplusAuctionHouseOne.addAuthorization(address(accountingEngine));
        debtAuctionHouse.addAuthorization(address(accountingEngine));
    }
    function test_shutdown_basic() public {
        assertEq(globalSettlement.contractEnabled(), 1);
        assertEq(cdpEngine.contractEnabled(), 1);
        assertEq(liquidationEngine.contractEnabled(), 1);
        assertEq(oracleRelayer.contractEnabled(), 1);
        assertEq(accountingEngine.contractEnabled(), 1);
        assertEq(accountingEngine.debtAuctionHouse().contractEnabled(), 1);
        assertEq(accountingEngine.surplusAuctionHouse().contractEnabled(), 1);
        globalSettlement.shutdownSystem();
        assertEq(globalSettlement.contractEnabled(), 0);
        assertEq(cdpEngine.contractEnabled(), 0);
        assertEq(liquidationEngine.contractEnabled(), 0);
        assertEq(accountingEngine.contractEnabled(), 0);
        assertEq(oracleRelayer.contractEnabled(), 0);
        assertEq(accountingEngine.debtAuctionHouse().contractEnabled(), 0);
        assertEq(accountingEngine.surplusAuctionHouse().contractEnabled(), 0);
    }
    function test_shutdown_savings_account_and_rate_setter_set_v2() public {
        globalSettlement.modifyParameters("coinSavingsAccount", address(coinSavingsAccount));
        globalSettlement.modifyParameters("rateSetter", address(rateSetter));
        globalSettlement.modifyParameters("stabilityFeeTreasury", address(stabilityFeeTreasury));
        assertEq(globalSettlement.contractEnabled(), 1);
        assertEq(cdpEngine.contractEnabled(), 1);
        assertEq(liquidationEngine.contractEnabled(), 1);
        assertEq(oracleRelayer.contractEnabled(), 1);
        assertEq(accountingEngine.contractEnabled(), 1);
        assertEq(accountingEngine.debtAuctionHouse().contractEnabled(), 1);
        assertEq(accountingEngine.surplusAuctionHouse().contractEnabled(), 1);
        assertEq(coinSavingsAccount.contractEnabled(), 1);
        assertEq(stabilityFeeTreasury.contractEnabled(), 1);
        assertEq(rateSetter.contractEnabled(), 1);
        globalSettlement.shutdownSystem();
        assertEq(globalSettlement.contractEnabled(), 0);
        assertEq(cdpEngine.contractEnabled(), 0);
        assertEq(liquidationEngine.contractEnabled(), 0);
        assertEq(accountingEngine.contractEnabled(), 0);
        assertEq(oracleRelayer.contractEnabled(), 0);
        assertEq(accountingEngine.debtAuctionHouse().contractEnabled(), 0);
        assertEq(accountingEngine.surplusAuctionHouse().contractEnabled(), 0);
        assertEq(stabilityFeeTreasury.contractEnabled(), 0);
        assertEq(coinSavingsAccount.contractEnabled(), 0);
        assertEq(rateSetter.contractEnabled(), 0);
    }
    // -- Scenario where there is one over-collateralised CDP
    // -- and there is no AccountingEngine deficit or surplus
    function test_shutdown_collateralised() public {
        CollateralType memory gold = init_collateral("gold");

        Usr ali = new Usr(cdpEngine, globalSettlement);

        // make a CDP:
        address cdp1 = address(ali);
        gold.collateralA.join(cdp1, 10 ether);
        ali.modifyCDPCollateralization("gold", cdp1, cdp1, cdp1, 10 ether, 15 ether);

        // global checks:
        assertEq(cdpEngine.globalDebt(), rad(15 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), 0);

        // collateral price is 5
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(5 * WAD));
        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");
        globalSettlement.processCDP("gold", cdp1);

        // local checks:
        assertEq(globalSettlement.finalCoinPerCollateralPrice("gold"), ray(0.2 ether));
        assertEq(generatedDebt("gold", cdp1), 0);
        assertEq(lockedCollateral("gold", cdp1), 7 ether);
        assertEq(cdpEngine.debtBalance(address(accountingEngine)), rad(15 ether));

        // global checks:
        assertEq(cdpEngine.globalDebt(), rad(15 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), rad(15 ether));

        // CDP closing
        ali.freeCollateral("gold");
        assertEq(lockedCollateral("gold", cdp1), 0);
        assertEq(tokenCollateral("gold", cdp1), 7 ether);
        ali.exit(gold.collateralA, address(this), 7 ether);

        hevm.warp(now + 1 hours);
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);

        // coin redemption
        ali.approveCDPModification(address(globalSettlement));
        ali.prepareCoinsForRedeeming(15 ether);
        accountingEngine.settleDebt(rad(15 ether));

        // global checks:
        assertEq(cdpEngine.globalDebt(), 0);
        assertEq(cdpEngine.globalUnbackedDebt(), 0);

        ali.redeemCollateral("gold", 15 ether);

        // local checks:
        assertEq(coinBalance(cdp1), 0);
        assertEq(tokenCollateral("gold", cdp1), 3 ether);
        ali.exit(gold.collateralA, address(this), 3 ether);

        assertEq(tokenCollateral("gold", address(globalSettlement)), 0);
        assertEq(balanceOf("gold", address(gold.collateralA)), 0);
    }

    // -- Scenario where there is one over-collateralised and one
    // -- under-collateralised CDP, and no AccountingEngine deficit or surplus
    function test_shutdown_undercollateralised() public {
        CollateralType memory gold = init_collateral("gold");

        Usr ali = new Usr(cdpEngine, globalSettlement);
        Usr bob = new Usr(cdpEngine, globalSettlement);

        // make a CDP:
        address cdp1 = address(ali);
        gold.collateralA.join(cdp1, 10 ether);
        ali.modifyCDPCollateralization("gold", cdp1, cdp1, cdp1, 10 ether, 15 ether);

        // make a second CDP:
        address cdp2 = address(bob);
        gold.collateralA.join(cdp2, 1 ether);
        bob.modifyCDPCollateralization("gold", cdp2, cdp2, cdp2, 1 ether, 3 ether);

        // global checks:
        assertEq(cdpEngine.globalDebt(), rad(18 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), 0);

        // collateral price is 2
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(2 * WAD));
        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");
        globalSettlement.processCDP("gold", cdp1);  // over-collateralised
        globalSettlement.processCDP("gold", cdp2);  // under-collateralised

        // local checks
        assertEq(generatedDebt("gold", cdp1), 0);
        assertEq(lockedCollateral("gold", cdp1), 2.5 ether);
        assertEq(generatedDebt("gold", cdp2), 0);
        assertEq(lockedCollateral("gold", cdp2), 0);
        assertEq(cdpEngine.debtBalance(address(accountingEngine)), rad(18 ether));

        // global checks
        assertEq(cdpEngine.globalDebt(), rad(18 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), rad(18 ether));

        // CDP closing
        ali.freeCollateral("gold");
        assertEq(lockedCollateral("gold", cdp1), 0);
        assertEq(tokenCollateral("gold", cdp1), 2.5 ether);
        ali.exit(gold.collateralA, address(this), 2.5 ether);

        hevm.warp(now + 1 hours);
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);

        // first coin redemption
        ali.approveCDPModification(address(globalSettlement));
        ali.prepareCoinsForRedeeming(15 ether);
        accountingEngine.settleDebt(rad(15 ether));

        // global checks:
        assertEq(cdpEngine.globalDebt(), rad(3 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), rad(3 ether));

        ali.redeemCollateral("gold", 15 ether);

        // local checks:
        assertEq(coinBalance(cdp1), 0);
        uint fix = globalSettlement.collateralCashPrice("gold");
        assertEq(tokenCollateral("gold", cdp1), rmul(fix, 15 ether));
        ali.exit(gold.collateralA, address(this), uint(rmul(fix, 15 ether)));

        // second coin redemption
        bob.approveCDPModification(address(globalSettlement));
        bob.prepareCoinsForRedeeming(3 ether);
        accountingEngine.settleDebt(rad(3 ether));

        // global checks:
        assertEq(cdpEngine.globalDebt(), 0);
        assertEq(cdpEngine.globalUnbackedDebt(), 0);

        bob.redeemCollateral("gold", 3 ether);

        // local checks:
        assertEq(coinBalance(cdp2), 0);
        assertEq(tokenCollateral("gold", cdp2), rmul(fix, 3 ether));
        bob.exit(gold.collateralA, address(this), uint(rmul(fix, 3 ether)));

        // some dust remains in GlobalSettlement because of rounding:
        assertEq(tokenCollateral("gold", address(globalSettlement)), 1);
        assertEq(balanceOf("gold", address(gold.collateralA)), 1);
    }

    // -- Scenario where there is one collateralised CDP
    // -- undergoing auction at the time of shutdown
    function test_shutdown_fast_track_auction() public {
        CollateralType memory gold = init_collateral("gold");

        Usr ali = new Usr(cdpEngine, globalSettlement);

        // make a CDP:
        address cdp1 = address(ali);
        gold.collateralA.join(cdp1, 10 ether);
        ali.modifyCDPCollateralization("gold", cdp1, cdp1, cdp1, 10 ether, 15 ether);

        cdpEngine.modifyParameters("gold", "safetyPrice", ray(1 ether));
        cdpEngine.modifyParameters("gold", "liquidationPrice", ray(1 ether)); // now unsafe

        uint auction = liquidationEngine.liquidateCDP("gold", cdp1); // CDP liquidated
        assertEq(cdpEngine.globalUnbackedDebt(), rad(15 ether));     // now there is sin
        // get 1 coin from ali
        ali.transferInternalCoins(address(ali), address(this), rad(1 ether));
        cdpEngine.approveCDPModification(address(gold.collateralAuctionHouse));
        gold.collateralAuctionHouse.increaseBidSize(auction, 10 ether, rad(1 ether)); // bid 1 coin
        assertEq(coinBalance(cdp1), 14 ether);

        // collateral price is 5
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(5 * WAD));
        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");

        globalSettlement.fastTrackAuction("gold", auction);
        assertEq(coinBalance(address(this)), 1 ether);       // bid refunded
        cdpEngine.transferInternalCoins(address(this), cdp1, rad(1 ether)); // return 1 coin to ali

        globalSettlement.processCDP("gold", cdp1);

        // local checks:
        assertEq(generatedDebt("gold", cdp1), 0);
        assertEq(lockedCollateral("gold", cdp1), 7 ether);
        assertEq(cdpEngine.debtBalance(address(accountingEngine)), rad(30 ether));

        // balance the accountingEngine
        accountingEngine.settleDebt(min(cdpEngine.coinBalance(address(accountingEngine)), cdpEngine.debtBalance(address(accountingEngine))));
        // global checks:
        assertEq(cdpEngine.globalDebt(), rad(15 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), rad(15 ether));

        // CDP closing
        ali.freeCollateral("gold");
        assertEq(lockedCollateral("gold", cdp1), 0);
        assertEq(tokenCollateral("gold", cdp1), 7 ether);
        ali.exit(gold.collateralA, address(this), 7 ether);

        hevm.warp(now + 1 hours);
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);

        // coin redemption
        ali.approveCDPModification(address(globalSettlement));
        ali.prepareCoinsForRedeeming(15 ether);
        accountingEngine.settleDebt(rad(15 ether));

        // global checks:
        assertEq(cdpEngine.globalDebt(), 0);
        assertEq(cdpEngine.globalUnbackedDebt(), 0);

        ali.redeemCollateral("gold", 15 ether);

        // local checks:
        assertEq(coinBalance(cdp1), 0);
        assertEq(tokenCollateral("gold", cdp1), 3 ether);
        ali.exit(gold.collateralA, address(this), 3 ether);

        assertEq(tokenCollateral("gold", address(globalSettlement)), 0);
        assertEq(balanceOf("gold", address(gold.collateralA)), 0);
    }

    // -- Scenario where there is one over-collateralised CDP
    // -- and there is a deficit in the AccountingEngine
    function test_shutdown_collateralised_deficit() public {
        CollateralType memory gold = init_collateral("gold");

        Usr ali = new Usr(cdpEngine, globalSettlement);

        // make a CDP:
        address cdp1 = address(ali);
        gold.collateralA.join(cdp1, 10 ether);
        ali.modifyCDPCollateralization("gold", cdp1, cdp1, cdp1, 10 ether, 15 ether);

        // create 1 unbacked coin and give to ali
        cdpEngine.createUnbackedDebt(address(accountingEngine), address(ali), rad(1 ether));

        // global checks:
        assertEq(cdpEngine.globalDebt(), rad(16 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), rad(1 ether));

        // collateral price is 5
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(5 * WAD));
        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");
        globalSettlement.processCDP("gold", cdp1);

        // local checks:
        assertEq(generatedDebt("gold", cdp1), 0);
        assertEq(lockedCollateral("gold", cdp1), 7 ether);
        assertEq(cdpEngine.debtBalance(address(accountingEngine)), rad(16 ether));

        // global checks:
        assertEq(cdpEngine.globalDebt(), rad(16 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), rad(16 ether));

        // CDP closing
        ali.freeCollateral("gold");
        assertEq(lockedCollateral("gold", cdp1), 0);
        assertEq(tokenCollateral("gold", cdp1), 7 ether);
        ali.exit(gold.collateralA, address(this), 7 ether);

        hevm.warp(now + 1 hours);
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);

        // coin redemption
        ali.approveCDPModification(address(globalSettlement));
        ali.prepareCoinsForRedeeming(16 ether);
        accountingEngine.settleDebt(rad(16 ether));

        // global checks:
        assertEq(cdpEngine.globalDebt(), 0);
        assertEq(cdpEngine.globalUnbackedDebt(), 0);

        ali.redeemCollateral("gold", 16 ether);

        // local checks:
        assertEq(coinBalance(cdp1), 0);
        assertEq(tokenCollateral("gold", cdp1), 3 ether);
        ali.exit(gold.collateralA, address(this), 3 ether);

        assertEq(tokenCollateral("gold", address(globalSettlement)), 0);
        assertEq(balanceOf("gold", address(gold.collateralA)), 0);
    }

    function test_shutdown_overcollateralized_surplus_smaller_redemption() public {
        CollateralType memory gold = init_collateral("gold");

        Usr ali = new Usr(cdpEngine, globalSettlement);
        Usr bob = new Usr(cdpEngine, globalSettlement);
        Usr charlie = new Usr(cdpEngine, globalSettlement);

        // make a CDP:
        address cdp1 = address(ali);
        gold.collateralA.join(cdp1, 10 ether);
        ali.modifyCDPCollateralization("gold", cdp1, cdp1, cdp1, 10 ether, 15 ether);

        // create surplus and also transfer to charlie
        ali.transferInternalCoins(address(ali), address(accountingEngine), rad(2 ether));
        ali.transferInternalCoins(address(ali), address(charlie), rad(2 ether));

        // global checks:
        assertEq(cdpEngine.globalDebt(), rad(15 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), 0);

        // collateral price is 5
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(5 * WAD));
        // redemption price is 0.5
        oracleRelayer.modifyParameters("redemptionPrice", ray(0.5 ether));

        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");
        globalSettlement.processCDP("gold", cdp1);

        // local checks:
        assertEq(globalSettlement.finalCoinPerCollateralPrice("gold"), ray(0.1 ether));
        assertEq(generatedDebt("gold", cdp1), 0);
        assertEq(lockedCollateral("gold", cdp1), 8.5 ether);
        assertEq(cdpEngine.debtBalance(address(accountingEngine)), rad(15 ether));

        // global checks:
        assertEq(cdpEngine.globalDebt(), rad(15 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), rad(15 ether));

        // CDP closing
        ali.freeCollateral("gold");
        assertEq(lockedCollateral("gold", cdp1), 0);
        assertEq(tokenCollateral("gold", cdp1), 8.5 ether);
        ali.exit(gold.collateralA, address(this), 8.5 ether);

        hevm.warp(now + 1 hours);
        accountingEngine.settleDebt(cdpEngine.coinBalance(address(accountingEngine)));
        assertEq(globalSettlement.outstandingCoinSupply(), 0);
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);
        assertEq(cdpEngine.tokenCollateral("gold", address(globalSettlement)), 1.5 ether);

        // coin redemption
        assertEq(tokenCollateral("gold", address(ali)), 0);
        assertEq(tokenCollateral("gold", address(charlie)), 0);

        ali.approveCDPModification(address(globalSettlement));
        assertEq(cdpEngine.coinBalance(address(ali)), rad(11 ether));
        ali.prepareCoinsForRedeeming(11 ether);

        charlie.approveCDPModification(address(globalSettlement));
        assertEq(cdpEngine.coinBalance(address(charlie)), rad(2 ether));
        charlie.prepareCoinsForRedeeming(2 ether);

        ali.redeemCollateral("gold", 11 ether);
        charlie.redeemCollateral("gold", 2 ether);

        assertEq(cdpEngine.globalDebt(), rad(15 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), rad(15 ether));

        // local checks:
        assertEq(coinBalance(cdp1), 0);
        assertEq(tokenCollateral("gold", cdp1), 1100000000000000000);
        ali.exit(gold.collateralA, address(this), tokenCollateral("gold", cdp1));

        assertEq(tokenCollateral("gold", address(charlie)), 200000000000000000);
        charlie.exit(gold.collateralA, address(this), tokenCollateral("gold", address(charlie)));

        assertEq(tokenCollateral("gold", address(globalSettlement)), 0.2 ether);
        assertEq(balanceOf("gold", address(gold.collateralA)), 0.2 ether);

        assertEq(coinBalance(address(postSettlementSurplusDrain)), 2 ether);
    }

    function test_shutdown_overcollateralized_surplus_bigger_redemption() public {
        CollateralType memory gold = init_collateral("gold");

        Usr ali = new Usr(cdpEngine, globalSettlement);
        Usr bob = new Usr(cdpEngine, globalSettlement);
        Usr charlie = new Usr(cdpEngine, globalSettlement);

        // make a CDP:
        address cdp1 = address(ali);
        gold.collateralA.join(cdp1, 10 ether);
        ali.modifyCDPCollateralization("gold", cdp1, cdp1, cdp1, 10 ether, 15 ether);

        // create surplus and also transfer to charlie
        ali.transferInternalCoins(address(ali), address(accountingEngine), rad(2 ether));
        ali.transferInternalCoins(address(ali), address(charlie), rad(2 ether));

        // global checks:
        assertEq(cdpEngine.globalDebt(), rad(15 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), 0);

        // collateral price is 5
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(5 * WAD));
        // redemption price is 0.5
        oracleRelayer.modifyParameters("redemptionPrice", ray(2 ether));

        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");
        globalSettlement.processCDP("gold", cdp1);

        // local checks:
        assertEq(globalSettlement.finalCoinPerCollateralPrice("gold"), ray(0.4 ether));
        assertEq(generatedDebt("gold", cdp1), 0);
        assertEq(lockedCollateral("gold", cdp1), 4 ether);
        assertEq(cdpEngine.debtBalance(address(accountingEngine)), rad(15 ether));

        // global checks:
        assertEq(cdpEngine.globalDebt(), rad(15 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), rad(15 ether));

        // CDP closing
        ali.freeCollateral("gold");
        assertEq(lockedCollateral("gold", cdp1), 0);
        assertEq(tokenCollateral("gold", cdp1), 4 ether);
        ali.exit(gold.collateralA, address(this), 4 ether);

        hevm.warp(now + 1 hours);
        accountingEngine.settleDebt(cdpEngine.coinBalance(address(accountingEngine)));
        assertEq(globalSettlement.outstandingCoinSupply(), 0);
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);
        assertEq(cdpEngine.tokenCollateral("gold", address(globalSettlement)), 6 ether);

        // coin redemption
        assertEq(tokenCollateral("gold", address(ali)), 0);
        assertEq(tokenCollateral("gold", address(charlie)), 0);

        ali.approveCDPModification(address(globalSettlement));
        assertEq(cdpEngine.coinBalance(address(ali)), rad(11 ether));
        ali.prepareCoinsForRedeeming(11 ether);

        charlie.approveCDPModification(address(globalSettlement));
        assertEq(cdpEngine.coinBalance(address(charlie)), rad(2 ether));
        charlie.prepareCoinsForRedeeming(2 ether);

        ali.redeemCollateral("gold", 11 ether);
        charlie.redeemCollateral("gold", 2 ether);

        assertEq(cdpEngine.globalDebt(), rad(15 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), rad(15 ether));

        // local checks:
        assertEq(coinBalance(cdp1), 0);
        assertEq(tokenCollateral("gold", cdp1), 4400000000000000000);
        ali.exit(gold.collateralA, address(this), tokenCollateral("gold", cdp1));

        assertEq(tokenCollateral("gold", address(charlie)), 800000000000000000);
        charlie.exit(gold.collateralA, address(this), tokenCollateral("gold", address(charlie)));

        assertEq(tokenCollateral("gold", address(globalSettlement)), 0.8 ether);
        assertEq(balanceOf("gold", address(gold.collateralA)), 0.8 ether);

        assertEq(coinBalance(address(postSettlementSurplusDrain)), 2 ether);
    }

    // -- Scenario where there is one over-collateralised CDP
    // -- and one under-collateralised CDP and there is a
    // -- surplus in the AccountingEngine
    function test_shutdown_over_and_under_collateralised_surplus() public {
        CollateralType memory gold = init_collateral("gold");

        Usr ali = new Usr(cdpEngine, globalSettlement);
        Usr bob = new Usr(cdpEngine, globalSettlement);

        // make a CDP:
        address cdp1 = address(ali);
        gold.collateralA.join(cdp1, 10 ether);
        ali.modifyCDPCollateralization("gold", cdp1, cdp1, cdp1, 10 ether, 15 ether);

        // alive gives one coin to the accountingEngine, creating surplus
        ali.transferInternalCoins(address(ali), address(accountingEngine), rad(1 ether));
        assertEq(cdpEngine.coinBalance(address(accountingEngine)), rad(1 ether));

        // make a second CDP:
        address cdp2 = address(bob);
        gold.collateralA.join(cdp2, 1 ether);
        bob.modifyCDPCollateralization("gold", cdp2, cdp2, cdp2, 1 ether, 3 ether);

        // global checks:
        assertEq(cdpEngine.globalDebt(), rad(18 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), 0);

        // collateral price is 2
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(2 * WAD));
        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");
        globalSettlement.processCDP("gold", cdp1);  // over-collateralised
        globalSettlement.processCDP("gold", cdp2);  // under-collateralised

        // local checks
        assertEq(generatedDebt("gold", cdp1), 0);
        assertEq(lockedCollateral("gold", cdp1), 2.5 ether);
        assertEq(generatedDebt("gold", cdp2), 0);
        assertEq(lockedCollateral("gold", cdp2), 0);
        assertEq(cdpEngine.debtBalance(address(accountingEngine)), rad(18 ether));

        // global checks
        assertEq(cdpEngine.globalDebt(), rad(18 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), rad(18 ether));

        // CDP closing
        ali.freeCollateral("gold");
        assertEq(lockedCollateral("gold", cdp1), 0);
        assertEq(tokenCollateral("gold", cdp1), 2.5 ether);
        ali.exit(gold.collateralA, address(this), 2.5 ether);

        hevm.warp(now + 1 hours);
        // balance the accountingEngine
        // accountingEngine.settleDebt(rad(1 ether));
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        assertTrue(globalSettlement.collateralCashPrice("gold") != 0);

        // first coin redemption
        ali.approveCDPModification(address(globalSettlement));
        ali.prepareCoinsForRedeeming(coinBalance(address(ali)));
        accountingEngine.settleDebt(rad(14 ether));

        // global checks:
        assertEq(cdpEngine.globalDebt(), rad(4 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), rad(4 ether));

        ali.redeemCollateral("gold", 14 ether);

        // local checks:
        assertEq(coinBalance(cdp1), 0);
        uint256 fix = globalSettlement.collateralCashPrice("gold");
        assertEq(tokenCollateral("gold", cdp1), uint(rmul(fix, 14 ether)));
        ali.exit(gold.collateralA, address(this), uint(rmul(fix, 14 ether)));

        // second coin redemption
        bob.approveCDPModification(address(globalSettlement));
        bob.prepareCoinsForRedeeming(3 ether);
        accountingEngine.settleDebt(rad(3 ether));

        // global checks:
        assertEq(cdpEngine.globalDebt(), rad(1 ether));
        assertEq(cdpEngine.globalUnbackedDebt(), rad(1 ether));

        bob.redeemCollateral("gold", 3 ether);

        // local checks:
        assertEq(coinBalance(cdp2), 0);
        assertEq(tokenCollateral("gold", cdp2), rmul(fix, 3 ether));
        bob.exit(gold.collateralA, address(this), uint(rmul(fix, 3 ether)));

        // nothing left in the GlobalSettlement
        assertEq(tokenCollateral("gold", address(globalSettlement)), 472222222222222223);
        assertEq(balanceOf("gold", address(gold.collateralA)), 472222222222222223);

        assertEq(coinBalance(address(postSettlementSurplusDrain)), 1 ether);
    }

    // -- Scenario where there is one over-collateralised and one
    // -- under-collateralised CDP of different collateral types
    // -- and no AccountingEngine deficit or surplus
    function test_shutdown_net_undercollateralised_multiple_collateralTypes() public {
        CollateralType memory gold = init_collateral("gold");
        CollateralType memory coal = init_collateral("coal");

        Usr ali = new Usr(cdpEngine, globalSettlement);
        Usr bob = new Usr(cdpEngine, globalSettlement);

        // make a CDP:
        address cdp1 = address(ali);
        gold.collateralA.join(cdp1, 10 ether);
        ali.modifyCDPCollateralization("gold", cdp1, cdp1, cdp1, 10 ether, 15 ether);

        // make a second CDP:
        address cdp2 = address(bob);
        coal.collateralA.join(cdp2, 1 ether);
        cdpEngine.modifyParameters("coal", "safetyPrice", ray(5 ether));
        bob.modifyCDPCollateralization("coal", cdp2, cdp2, cdp2, 1 ether, 5 ether);

        gold.oracleSecurityModule.updateCollateralPrice(bytes32(2 * WAD));
        // cdp1 has 20 coin of lockedCollateral and 15 coin of tab
        coal.oracleSecurityModule.updateCollateralPrice(bytes32(2 * WAD));
        // cdp2 has 2 coin of lockedCollateral and 5 coin of tab
        globalSettlement.shutdownSystem();
        globalSettlement.freezeCollateralType("gold");
        globalSettlement.freezeCollateralType("coal");
        globalSettlement.processCDP("gold", cdp1);  // over-collateralised
        globalSettlement.processCDP("coal", cdp2);  // under-collateralised

        hevm.warp(now + 1 hours);
        globalSettlement.setOutstandingCoinSupply();
        globalSettlement.calculateCashPrice("gold");
        globalSettlement.calculateCashPrice("coal");

        ali.approveCDPModification(address(globalSettlement));
        bob.approveCDPModification(address(globalSettlement));

        assertEq(cdpEngine.globalDebt(),             rad(20 ether));
        assertEq(cdpEngine.globalUnbackedDebt(),             rad(20 ether));
        assertEq(cdpEngine.debtBalance(address(accountingEngine)),  rad(20 ether));

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
}
