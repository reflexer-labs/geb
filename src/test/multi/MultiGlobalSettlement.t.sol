// MultiGlobalSettlement.t.sol

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

import {MultiSAFEEngine} from '../../multi/MultiSAFEEngine.sol';
import {MultiLiquidationEngine} from '../../multi/MultiLiquidationEngine.sol';
import {MultiAccountingEngine} from '../../multi/MultiAccountingEngine.sol';
import {MultiEnglishCollateralAuctionHouse} from '../../multi/MultiEnglishCollateralAuctionHouse.sol';
import {MultiIncreasingDiscountCollateralAuctionHouse} from '../../multi/MultiIncreasingDiscountCollateralAuctionHouse.sol';
import {BurningMultiSurplusAuctionHouse} from '../../multi/MultiSurplusAuctionHouse.sol';
import {MultiDebtAuctionHouse} from '../../multi/MultiDebtAuctionHouse.sol';
import {BasicCollateralJoin, MultiCoinJoin} from '../../shared/BasicTokenAdapters.sol';
import {MultiGlobalSettlement, OracleLike}  from '../../multi/MultiGlobalSettlement.sol';
import {MultiOracleRelayer} from '../../multi/MultiOracleRelayer.sol';

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
    MultiSAFEEngine public safeEngine;
    MultiGlobalSettlement public globalSettlement;

    constructor(MultiSAFEEngine safeEngine_, MultiGlobalSettlement globalSettlement_) public {
        safeEngine  = safeEngine_;
        globalSettlement  = globalSettlement_;
    }
    function modifySAFECollateralization(
      bytes32 coinName,
      bytes32 collateralType,
      address safe,
      address collateralSrc,
      address debtDst,
      int deltaCollateral,
      int deltaDebt
    ) public {
        safeEngine.modifySAFECollateralization(
          coinName, collateralType, safe, collateralSrc, debtDst, deltaCollateral, deltaDebt
        );
    }
    function transferInternalCoins(bytes32 coinName, address src, address dst, uint256 rad) public {
        safeEngine.transferInternalCoins(coinName, src, dst, rad);
    }
    function approveSAFEModification(bytes32 coinName, address usr) public {
        safeEngine.approveSAFEModification(coinName, usr);
    }
    function exit(BasicCollateralJoin collateralA, address usr, uint wad) public {
        collateralA.exit(usr, wad);
    }
    function freeCollateral(bytes32 coinName, bytes32 collateralType) public {
        globalSettlement.freeCollateral(coinName, collateralType);
    }
    function prepareCoinsForRedeeming(bytes32 coinName, uint256 rad) public {
        globalSettlement.prepareCoinsForRedeeming(coinName, rad);
    }
    function redeemCollateral(bytes32 coinName, bytes32 collateralType, uint wad) public {
        globalSettlement.redeemCollateral(coinName, collateralType, wad);
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

contract MultiGlobalSettlementTest is DSTest {
    Hevm hevm;

    MultiSAFEEngine safeEngine;
    MultiGlobalSettlement globalSettlement;
    MultiAccountingEngine accountingEngine;
    MultiLiquidationEngine liquidationEngine;
    MultiOracleRelayer oracleRelayer;

    DSDelegateToken protocolToken;
    DSDelegateToken systemCoin;
    MultiCoinJoin systemCoinA;

    bytes32 firstCoinName = "MAI";

    struct CollateralType {
        DummyFSM oracleSecurityModule;
        DSDelegateToken collateral;
        BasicCollateralJoin collateralA;
        MultiEnglishCollateralAuctionHouse englishCollateralAuctionHouse;
        MultiIncreasingDiscountCollateralAuctionHouse increasingDiscountCollateralAuctionHouse;
    }

    mapping (bytes32 => mapping(bytes32 => CollateralType)) collateralTypes;

    BurningMultiSurplusAuctionHouse surplusAuctionHouseOne;
    MultiDebtAuctionHouse debtAuctionHouse;

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
    function coinBalance(bytes32 coinName, address safe) internal view returns (uint) {
        return uint(safeEngine.coinBalance(coinName, safe) / RAY);
    }
    function tokenCollateral(bytes32 collateralType, address safe) internal view returns (uint) {
        return safeEngine.tokenCollateral(collateralType, safe);
    }
    function lockedCollateral(bytes32 coinName, bytes32 collateralType, address safe) internal view returns (uint) {
        (uint lockedCollateral_, uint generatedDebt_) = safeEngine.safes(coinName, collateralType, safe); generatedDebt_;
        return lockedCollateral_;
    }
    function generatedDebt(bytes32 coinName, bytes32 collateralType, address safe) internal view returns (uint) {
        (uint lockedCollateral_, uint generatedDebt_) = safeEngine.safes(coinName, collateralType, safe); lockedCollateral_;
        return generatedDebt_;
    }
    function debtAmount(bytes32 coinName, bytes32 collateralType) internal view returns (uint) {
        (uint debtAmount_, uint accumulatedRate_, uint safetyPrice_, uint debtCeiling_, uint debtFloor_, uint liquidationPrice_)
          = safeEngine.collateralTypes(coinName, collateralType);
        accumulatedRate_; safetyPrice_; debtCeiling_; debtFloor_; liquidationPrice_;
        return debtAmount_;
    }
    function balanceOf(bytes32 coinName, bytes32 collateralType, address usr) internal view returns (uint) {
        return collateralTypes[coinName][collateralType].collateral.balanceOf(usr);
    }

    function init_collateral(bytes32 coinName, string memory name, bytes32 encodedName) internal returns (CollateralType memory) {
        DSDelegateToken newCollateral = new DSDelegateToken(name, name);
        newCollateral.mint(20 ether);

        DummyFSM oracleFSM = new DummyFSM();
        oracleRelayer.modifyParameters(coinName, encodedName, "orcl", address(oracleFSM));
        oracleRelayer.modifyParameters(coinName, encodedName, "safetyCRatio", ray(1.5 ether));
        oracleRelayer.modifyParameters(coinName, encodedName, "liquidationCRatio", ray(1.5 ether));

        // initial collateral price of 5
        oracleFSM.updateCollateralPrice(bytes32(5 * WAD));

        safeEngine.initializeCollateralType(coinName, encodedName);
        BasicCollateralJoin collateralA = new BasicCollateralJoin(address(safeEngine), encodedName, address(newCollateral));

        safeEngine.modifyParameters(coinName, encodedName, "safetyPrice", ray(3 ether));
        safeEngine.modifyParameters(coinName, encodedName, "liquidationPrice", ray(3 ether));
        safeEngine.modifyParameters(coinName, encodedName, "debtCeiling", rad(10000000 ether)); // 10M

        newCollateral.approve(address(collateralA));
        newCollateral.approve(address(safeEngine));

        safeEngine.addCollateralJoin(encodedName, address(collateralA));

        MultiEnglishCollateralAuctionHouse englishCollateralAuctionHouse =
          new MultiEnglishCollateralAuctionHouse(coinName, address(safeEngine), address(liquidationEngine), encodedName);
        safeEngine.approveSAFEModification(coinName, address(englishCollateralAuctionHouse));
        englishCollateralAuctionHouse.addAuthorization(address(globalSettlement));
        englishCollateralAuctionHouse.addAuthorization(address(liquidationEngine));

        MultiIncreasingDiscountCollateralAuctionHouse increasingDiscountCollateralAuctionHouse =
          new MultiIncreasingDiscountCollateralAuctionHouse(address(safeEngine), address(liquidationEngine), coinName, encodedName);
        increasingDiscountCollateralAuctionHouse.modifyParameters("oracleRelayer", address(oracleRelayer));
        increasingDiscountCollateralAuctionHouse.modifyParameters("collateralFSM", address(new Feed(bytes32(uint256(200 ether)), true)));
        safeEngine.approveSAFEModification(coinName, address(increasingDiscountCollateralAuctionHouse));
        increasingDiscountCollateralAuctionHouse.addAuthorization(address(globalSettlement));
        increasingDiscountCollateralAuctionHouse.addAuthorization(address(liquidationEngine));

        // Start with English auction house
        liquidationEngine.addAuthorization(coinName, address(englishCollateralAuctionHouse));
        liquidationEngine.addAuthorization(coinName, address(increasingDiscountCollateralAuctionHouse));

        liquidationEngine.modifyParameters(coinName, encodedName, "collateralAuctionHouse", address(englishCollateralAuctionHouse));
        liquidationEngine.modifyParameters(coinName, encodedName, "liquidationPenalty", 1 ether);
        liquidationEngine.modifyParameters(coinName, encodedName, "liquidationQuantity", uint(-1) / ray(1 ether));

        collateralTypes[firstCoinName][encodedName].oracleSecurityModule = oracleFSM;
        collateralTypes[firstCoinName][encodedName].collateral = newCollateral;
        collateralTypes[firstCoinName][encodedName].collateralA = collateralA;
        collateralTypes[firstCoinName][encodedName].englishCollateralAuctionHouse = englishCollateralAuctionHouse;
        collateralTypes[firstCoinName][encodedName].increasingDiscountCollateralAuctionHouse = increasingDiscountCollateralAuctionHouse;

        return collateralTypes[firstCoinName][encodedName];
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine = new MultiSAFEEngine();
        safeEngine.initializeCoin(firstCoinName, uint(-1));

        protocolToken = new DSDelegateToken('GOV', 'GOV');
        systemCoin = new DSDelegateToken("Coin", "Coin");
        systemCoinA = new MultiCoinJoin(firstCoinName, address(safeEngine), address(systemCoin));

        surplusAuctionHouseOne = new BurningMultiSurplusAuctionHouse(firstCoinName, address(safeEngine), address(protocolToken));
        safeEngine.approveSAFEModification(firstCoinName, address(surplusAuctionHouseOne));
        protocolToken.approve(address(surplusAuctionHouseOne));
        debtAuctionHouse = new MultiDebtAuctionHouse(firstCoinName, address(safeEngine), address(protocolToken), address(accountingEngine));

        safeEngine.addAuthorization(firstCoinName, address(systemCoinA));
        systemCoin.mint(address(this), 50 ether);
        systemCoin.setOwner(address(systemCoinA));

        protocolToken.mint(200 ether);
        protocolToken.setOwner(address(debtAuctionHouse));

        accountingEngine = new MultiAccountingEngine(address(safeEngine), address(0x1), 1, 1);
        accountingEngine.initializeCoin(firstCoinName, 1, 1);
        safeEngine.addSystemComponent(address(accountingEngine));

        liquidationEngine = new MultiLiquidationEngine(address(safeEngine));
        liquidationEngine.modifyParameters("accountingEngine", address(accountingEngine));
        liquidationEngine.initializeCoin(firstCoinName, uint(-1));

        safeEngine.addSystemComponent(address(liquidationEngine));
        accountingEngine.addSystemComponent(address(liquidationEngine));

        oracleRelayer = new MultiOracleRelayer(address(safeEngine));
        oracleRelayer.initializeCoin(firstCoinName, 10 ** 27, uint(-1), 1);

        safeEngine.modifyParameters(firstCoinName, "globalDebtCeiling", rad(10000000 ether));
        safeEngine.addSystemComponent(address(oracleRelayer));

        globalSettlement = new MultiGlobalSettlement(1 hours);

        globalSettlement.modifyParameters("safeEngine", address(safeEngine));
        globalSettlement.modifyParameters("liquidationEngine", address(liquidationEngine));
        globalSettlement.modifyParameters("accountingEngine", address(accountingEngine));
        globalSettlement.modifyParameters("oracleRelayer", address(oracleRelayer));

        globalSettlement.initializeCoin(firstCoinName);
        globalSettlement.addTrigger(firstCoinName, address(this));

        safeEngine.addSystemComponent(address(globalSettlement));
        accountingEngine.addSystemComponent(address(globalSettlement));
        oracleRelayer.addSystemComponent(address(globalSettlement));
        liquidationEngine.addSystemComponent(address(globalSettlement));
    }
    function test_shutdown_basic() public {
        assertEq(globalSettlement.coinEnabled(firstCoinName), 1);
        assertEq(safeEngine.coinEnabled(firstCoinName), 1);
        assertEq(liquidationEngine.coinEnabled(firstCoinName), 1);
        assertEq(oracleRelayer.coinEnabled(firstCoinName), 1);
        assertEq(accountingEngine.coinEnabled(firstCoinName), 1);

        globalSettlement.shutdownCoin(firstCoinName);
        assertEq(globalSettlement.coinEnabled(firstCoinName), 0);
        assertEq(safeEngine.coinEnabled(firstCoinName), 0);
        assertEq(liquidationEngine.coinEnabled(firstCoinName), 0);
        assertEq(accountingEngine.coinEnabled(firstCoinName), 0);
        assertEq(oracleRelayer.coinEnabled(firstCoinName), 0);
    }
    // -- Scenario where there is one over-collateralised SAFE
    // -- and there is no MultiAccountingEngine deficit or surplus
    function test_shutdown_collateralised() public {
        CollateralType memory gold = init_collateral(firstCoinName, "gold", "gold");

        Usr ali = new Usr(safeEngine, globalSettlement);

        // make a SAFE:
        address safe1 = address(ali);
        gold.collateralA.join(safe1, 10 ether);
        ali.modifySAFECollateralization(firstCoinName, "gold", safe1, safe1, safe1, 10 ether, 15 ether);

        // global checks:
        assertEq(safeEngine.globalDebt(firstCoinName), rad(15 ether));
        assertEq(safeEngine.globalUnbackedDebt(firstCoinName), 0);

        // collateral price is 5
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(5 * WAD));
        globalSettlement.shutdownCoin(firstCoinName);
        globalSettlement.freezeCollateralType(firstCoinName, "gold");
        globalSettlement.processSAFE(firstCoinName, "gold", safe1);

        // local checks:
        assertEq(globalSettlement.finalCoinPerCollateralPrice(firstCoinName, "gold"), ray(0.2 ether));
        assertEq(generatedDebt(firstCoinName, "gold", safe1), 0);
        assertEq(lockedCollateral(firstCoinName, "gold", safe1), 7 ether);
        assertEq(safeEngine.debtBalance(firstCoinName, address(accountingEngine)), rad(15 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(firstCoinName), rad(15 ether));
        assertEq(safeEngine.globalUnbackedDebt(firstCoinName), rad(15 ether));

        // SAFE closing
        ali.freeCollateral(firstCoinName, "gold");
        assertEq(lockedCollateral(firstCoinName, "gold", safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 7 ether);
        ali.exit(gold.collateralA, address(this), 7 ether);

        hevm.warp(now + 1 hours);
        globalSettlement.setOutstandingCoinSupply(firstCoinName);
        globalSettlement.calculateCashPrice(firstCoinName, "gold");
        assertTrue(globalSettlement.collateralCashPrice(firstCoinName, "gold") != 0);

        // coin redemption
        ali.approveSAFEModification(firstCoinName, address(globalSettlement));
        ali.prepareCoinsForRedeeming(firstCoinName, 15 ether);
        accountingEngine.settleDebt(firstCoinName, rad(15 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(firstCoinName), 0);
        assertEq(safeEngine.globalUnbackedDebt(firstCoinName), 0);

        ali.redeemCollateral(firstCoinName, "gold", 15 ether);

        // local checks:
        assertEq(coinBalance(firstCoinName, safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 3 ether);
        ali.exit(gold.collateralA, address(this), 3 ether);

        assertEq(tokenCollateral("gold", address(globalSettlement)), 0);
        assertEq(balanceOf(firstCoinName, "gold", address(gold.collateralA)), 0);
    }

    // -- Scenario where there is one over-collateralised and one
    // -- under-collateralised SAFE, and no MultiAccountingEngine deficit or surplus
    function test_shutdown_undercollateralised() public {
        CollateralType memory gold = init_collateral(firstCoinName, "gold", "gold");

        Usr ali = new Usr(safeEngine, globalSettlement);
        Usr bob = new Usr(safeEngine, globalSettlement);

        // make a SAFE:
        address safe1 = address(ali);
        gold.collateralA.join(safe1, 10 ether);
        ali.modifySAFECollateralization(firstCoinName, "gold", safe1, safe1, safe1, 10 ether, 15 ether);

        // make a second SAFE:
        address safe2 = address(bob);
        gold.collateralA.join(safe2, 1 ether);
        bob.modifySAFECollateralization(firstCoinName, "gold", safe2, safe2, safe2, 1 ether, 3 ether);

        // global checks:
        assertEq(safeEngine.globalDebt(firstCoinName), rad(18 ether));
        assertEq(safeEngine.globalUnbackedDebt(firstCoinName), 0);

        // collateral price is 2
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(2 * WAD));
        globalSettlement.shutdownCoin(firstCoinName);
        globalSettlement.freezeCollateralType(firstCoinName, "gold");
        globalSettlement.processSAFE(firstCoinName, "gold", safe1);  // over-collateralised
        globalSettlement.processSAFE(firstCoinName, "gold", safe2);  // under-collateralised

        // local checks
        assertEq(generatedDebt(firstCoinName, "gold", safe1), 0);
        assertEq(lockedCollateral(firstCoinName, "gold", safe1), 2.5 ether);
        assertEq(generatedDebt(firstCoinName, "gold", safe2), 0);
        assertEq(lockedCollateral(firstCoinName, "gold", safe2), 0);
        assertEq(safeEngine.debtBalance(firstCoinName, address(accountingEngine)), rad(18 ether));

        // global checks
        assertEq(safeEngine.globalDebt(firstCoinName), rad(18 ether));
        assertEq(safeEngine.globalUnbackedDebt(firstCoinName), rad(18 ether));

        // SAFE closing
        ali.freeCollateral(firstCoinName, "gold");
        assertEq(lockedCollateral(firstCoinName, "gold", safe1), 0);
        assertEq(tokenCollateral(firstCoinName, "gold", safe1), 2.5 ether);
        ali.exit(gold.collateralA, address(this), 2.5 ether);

        hevm.warp(now + 1 hours);
        globalSettlement.setOutstandingCoinSupply(firstCoinName);
        globalSettlement.calculateCashPrice(firstCoinName, "gold");
        assertTrue(globalSettlement.collateralCashPrice(firstCoinName, "gold") != 0);

        // first coin redemption
        ali.approveSAFEModification(address(globalSettlement));
        ali.prepareCoinsForRedeeming(firstCoinName, 15 ether);
        accountingEngine.settleDebt(firstCoinName, rad(15 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(firstCoinName), rad(3 ether));
        assertEq(safeEngine.globalUnbackedDebt(firstCoinName), rad(3 ether));

        ali.redeemCollateral(firstCoinName, "gold", 15 ether);

        // local checks:
        assertEq(coinBalance(firstCoinName, safe1), 0);
        uint fix = globalSettlement.collateralCashPrice(firstCoinName, "gold");
        assertEq(tokenCollateral(firstCoinName, "gold", safe1), rmultiply(fix, 15 ether));
        ali.exit(gold.collateralA, address(this), uint(rmultiply(fix, 15 ether)));

        // second coin redemption
        bob.approveSAFEModification(address(globalSettlement));
        bob.prepareCoinsForRedeeming(firstCoinName, 3 ether);
        accountingEngine.settleDebt(firstCoinName, rad(3 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(firstCoinName), 0);
        assertEq(safeEngine.globalUnbackedDebt(firstCoinName), 0);

        bob.redeemCollateral(firstCoinName, "gold", 3 ether);

        // local checks:
        assertEq(coinBalance(firstCoinName, safe2), 0);
        assertEq(tokenCollateral(firstCoinName, "gold", safe2), rmultiply(fix, 3 ether));
        bob.exit(gold.collateralA, address(this), uint(rmultiply(fix, 3 ether)));

        // some dust remains in MultiGlobalSettlement because of rounding:
        assertEq(tokenCollateral(firstCoinName, "gold", address(globalSettlement)), 1);
        assertEq(balanceOf(firstCoinName, "gold", address(gold.collateralA)), 1);
    }

    // -- Scenario where there is one collateralised SAFE
    // -- undergoing auction at the time of shutdown
    function test_shutdown_fast_track_english_auction() public {
        CollateralType memory gold = init_collateral(firstCoinName, "gold", "gold");

        Usr ali = new Usr(safeEngine, globalSettlement);

        // make a SAFE:
        address safe1 = address(ali);
        gold.collateralA.join(safe1, 10 ether);
        ali.modifySAFECollateralization(firstCoinName, "gold", safe1, safe1, safe1, 10 ether, 15 ether);

        safeEngine.modifyParameters(firstCoinName, "gold", "safetyPrice", ray(1 ether));
        safeEngine.modifyParameters(firstCoinName, "gold", "liquidationPrice", ray(1 ether)); // now unsafe

        uint auction = liquidationEngine.liquidateSAFE(firstCoinName, "gold", safe1); // SAFE liquidated
        assertEq(safeEngine.globalUnbackedDebt(firstCoinName), rad(15 ether));     // now there is bad debt
        // get 1 coin from ali
        ali.transferInternalCoins(firstCoinName, address(ali), address(this), rad(1 ether));
        safeEngine.approveSAFEModification(firstCoinName, address(gold.englishCollateralAuctionHouse));
        gold.englishCollateralAuctionHouse.increaseBidSize(auction, 10 ether, rad(1 ether)); // bid 1 coin
        assertEq(coinBalance(firstCoinName, safe1), 14 ether);

        // collateral price is 5
        gold.oracleSecurityModule.updateCollateralPrice(bytes32(5 * WAD));
        globalSettlement.shutdownCoin(firstCoinName);
        globalSettlement.freezeCollateralType(firstCoinName, "gold");

        globalSettlement.fastTrackAuction(firstCoinName, "gold", auction);
        assertEq(coinBalance(firstCoinName, address(this)), 1 ether);       // bid refunded
        safeEngine.transferInternalCoins(firstCoinName, address(this), safe1, rad(1 ether)); // return 1 coin to ali

        globalSettlement.processSAFE(firstCoinName, "gold", safe1);

        // local checks:
        assertEq(generatedDebt(firstCoinName, "gold", safe1), 0);
        assertEq(lockedCollateral(firstCoinName, "gold", safe1), 7 ether);
        assertEq(safeEngine.debtBalance(firstCoinName, address(accountingEngine)), rad(30 ether));

        // balance the accountingEngine
        accountingEngine.settleDebt(firstCoinName, minimum(safeEngine.coinBalance(firstCoinName, address(accountingEngine)), safeEngine.debtBalance(firstCoinName, address(accountingEngine))));
        // global checks:
        assertEq(safeEngine.globalDebt(firstCoinName), rad(15 ether));
        assertEq(safeEngine.globalUnbackedDebt(firstCoinName), rad(15 ether));

        // SAFE closing
        ali.freeCollateral(firstCoinName, "gold");
        assertEq(lockedCollateral(firstCoinName, "gold", safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 7 ether);
        ali.exit(gold.collateralA, address(this), 7 ether);

        hevm.warp(now + 1 hours);
        globalSettlement.setOutstandingCoinSupply(firstCoinName);
        globalSettlement.calculateCashPrice(firstCoinName, "gold");
        assertTrue(globalSettlement.collateralCashPrice(firstCoinName, "gold") != 0);

        // coin redemption
        ali.approveSAFEModification(firstCoinName, address(globalSettlement));
        ali.prepareCoinsForRedeeming(firstCoinName, 15 ether);
        accountingEngine.settleDebt(firstCoinName, rad(15 ether));

        // global checks:
        assertEq(safeEngine.globalDebt(firstCoinName), 0);
        assertEq(safeEngine.globalUnbackedDebt(firstCoinName), 0);

        ali.redeemCollateral(firstCoinName, "gold", 15 ether);

        // local checks:
        assertEq(coinBalance(firstCoinName, safe1), 0);
        assertEq(tokenCollateral("gold", safe1), 3 ether);
        ali.exit(gold.collateralA, address(this), 3 ether);

        assertEq(tokenCollateral("gold", address(globalSettlement)), 0);
        assertEq(balanceOf(firstCoinName, "gold", address(gold.collateralA)), 0);
    }

    /* function test_shutdown_fast_track_fixed_discount_auction() public {
        CollateralType memory gold = init_collateral("gold", "gold");
        // swap auction house in the liquidation engine
        liquidationEngine.modifyParameters("gold", "collateralAuctionHouse", address(gold.increasingDiscountCollateralAuctionHouse));

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
        safeEngine.approveSAFEModification(address(gold.increasingDiscountCollateralAuctionHouse));
        gold.increasingDiscountCollateralAuctionHouse.buyCollateral(auction, 5 ether);

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
    // -- and there is a deficit in the MultiAccountingEngine
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
    // -- surplus in the MultiAccountingEngine
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

        // nothing left in the MultiGlobalSettlement
        assertEq(tokenCollateral("gold", address(globalSettlement)), 0);
        assertEq(balanceOf("gold", address(gold.collateralA)), 0);

        assertEq(coinBalance(address(postSettlementSurplusDrain)), 0);
    }

    // -- Scenario where there is one over-collateralised and one
    // -- under-collateralised SAFE of different collateral types
    // -- and no MultiAccountingEngine deficit or surplus
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
   } */
}
