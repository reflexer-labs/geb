pragma solidity 0.6.7;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";
import "ds-token/delegate.sol";

import {Coin} from '../Coin.sol';
import {SAFEEngine} from '../SAFEEngine.sol';
import {LiquidationEngine} from '../LiquidationEngine.sol';
import {LiquidationPool} from '../LiquidationPool.sol';
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

contract Guy {
    uint256 constant WAD = 10 ** 18;
    LiquidationPool liquidationPool;
    Coin systemCoin;

    constructor(LiquidationPool liquidationPool_, Coin sysCoin) public {
        liquidationPool = liquidationPool_;
        systemCoin = sysCoin;
        systemCoin.approve(address(liquidationPool), 100 * 10 ** 18);
    }

    function approvePool() public returns (bool ok) {
        string memory sig = "approve(address)";
        (ok,) = address(systemCoin).call(abi.encodeWithSignature(sig, address(liquidationPool)));
    }

    function depositToPool(uint256 wad) public returns (bool ok) {
        string memory sig = "deposit(uint256)";
        (ok,) = address(liquidationPool).call(abi.encodeWithSignature(sig, wad));
    }

    function try_withdrawSystemCoin(uint256 wad) public returns (bool ok) {
        string memory sig = "withdrawSystemCoin(uint256)";
        (ok,) = address(liquidationPool).call(abi.encodeWithSignature(sig, wad));
    }

    function try_withdrawRewards() public returns (bool ok) {
        string memory sig = "withdrawRewards()";
        (ok,) = address(liquidationPool).call(abi.encodeWithSignature(sig));
    }

    receive() external payable {}
}

contract LiquidationPoolTest is DSTest {
    Hevm hevm;

    TestSAFEEngine safeEngine;
    TestAccountingEngine accountingEngine;
    LiquidationEngine liquidationEngine;
    LiquidationPool liquidationPool;
    DSDelegateToken gold;
    Coin systemCoin;
    TaxCollector taxCollector;

    BasicCollateralJoin collateralA;

    EnglishCollateralAuctionHouse collateralAuctionHouse;
    DebtAuctionHouse debtAuctionHouse;
    PostSettlementSurplusAuctionHouse surplusAuctionHouse;

    DSDelegateToken protocolToken;
    CoinJoin systemCoinA;

    address me;
    address payable userA;
    address payable userB;
    address payable userC;
    uint256 constant WAD = 10 ** 18;

    event PrintThree(uint256 a, uint256 b, uint256 c);
    event log_named_address      (string key, address val);
    event log_named_uint         (string key, uint256 val);
    event log_named_bytes32      (string key, bytes32 val);

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
        gold = new DSDelegateToken("GEM", "GEM");
        gold.mint(1000 ether);
        systemCoin = new Coin("TAI", "TAI", 99);
        safeEngine = new TestSAFEEngine();
        safeEngine = safeEngine;
        systemCoinA = new CoinJoin(address(safeEngine), address(systemCoin));
        systemCoin.addAuthorization(address(systemCoinA));
        safeEngine.createUnbackedDebt(address(0x1), address(this), rad(1000 ether));
        safeEngine.approveSAFEModification(address(systemCoinA));
        systemCoinA.exit(address(this), 1000 ether);

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

        liquidationPool = new LiquidationPool(address(systemCoinA), "gold");
        systemCoin.approve(address(liquidationPool), uint256(-1));
        liquidationEngine = new LiquidationEngine(address(safeEngine));
        liquidationPool.addAuthorization(address(liquidationEngine));
        liquidationEngine.modifyParameters("accountingEngine", address(accountingEngine));
        liquidationEngine.modifyParameters("liquidationPool", address(liquidationPool));
        safeEngine.addAuthorization(address(liquidationEngine));
        accountingEngine.addAuthorization(address(liquidationEngine));

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
        userA = address(new Guy(liquidationPool, systemCoin));
        userB = address(new Guy(liquidationPool, systemCoin));
        userC = address(new Guy(liquidationPool, systemCoin));
        systemCoin.transfer(userA, 100 * WAD);
        systemCoin.transfer(userB, 100 * WAD);
        systemCoin.transfer(userC, 100 * WAD);
        Guy(userA).approvePool();
        Guy(userB).approvePool();
        Guy(userC).approvePool();
    }

    function liquidateSAFE(uint256 targetAuctionId) internal {
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
        assertEq(auction, targetAuctionId);
    }

    /*
    Due to rounding there will be a slight discrepancy in results which have been multiplied by a proportion of a wad.
    Extremely tiny errors will always be there but this could be alleviated if pool used rad precision more internally.
    */
    function assertClose(uint256 value, uint256 target) internal {
        uint256 allowableError = target / 10 ** 17;
        assertLe(value, target + allowableError);
        assertGe(value + allowableError, target);
    }

    function testPoolDepositsAndWithdrawals() public {
        assertTrue(Guy(userA).depositToPool(40 * WAD));
        assertTrue(Guy(userB).depositToPool(50 * WAD));
        assertTrue(Guy(userC).depositToPool(60 * WAD));
        assertTrue(Guy(userA).depositToPool(40 * WAD));
        //Ensure no one can withdraw more than their share
        assertTrue(!Guy(userB).try_withdrawSystemCoin(50 * WAD + 1));
        assertTrue(!Guy(userA).try_withdrawSystemCoin(80 * WAD + 1));
        assertTrue(!Guy(userC).try_withdrawSystemCoin(60 * WAD + 1));
        assertTrue(Guy(userB).try_withdrawSystemCoin(50 * WAD));
        assertTrue(Guy(userA).try_withdrawSystemCoin(80 * WAD));
        assertTrue(Guy(userC).try_withdrawSystemCoin(60 * WAD));
    }

    function testPoolMissingOutLiquidation() public {
        assertTrue(Guy(userA).depositToPool(1 * WAD));
        assertTrue(Guy(userB).depositToPool(1 * WAD));
        assertTrue(Guy(userC).depositToPool(2 * WAD));
        liquidateSAFE(1);
    }

    function testPoolLiquidation() public {
        assertTrue(Guy(userA).depositToPool(40 * WAD));
        assertTrue(Guy(userB).depositToPool(50 * WAD));
        assertTrue(Guy(userC).depositToPool(60 * WAD));
        liquidateSAFE(0);
    }

    function testPoolRewardWithdrawal() public {
        assertTrue(Guy(userB).depositToPool(40 * WAD));
        assertTrue(Guy(userC).depositToPool(60 * WAD));
        assertTrue(tokenCollateral("gold", address(liquidationPool)) == 0);
        liquidateSAFE(0);
        assertTrue(tokenCollateral("gold", address(liquidationPool)) == 10 * WAD);
        assertTrue(Guy(userA).depositToPool(100 * WAD));
        // Ensure userA who had 0% system coin share at liquidation and now has 50% is eligible for 0 rewards
        assertTrue(Guy(userA).try_withdrawRewards());
        assertTrue(tokenCollateral("gold", userA) == 0);
        // Ensure userB who had a 40% system coin share at time of liquidation and now about 20% gets 40% of rewards
        assertTrue(Guy(userB).try_withdrawRewards());
        assertClose(tokenCollateral("gold", userB), 4 * WAD);
    }

    function testPoolSysCoinRemovalPostLiquidation() public {
        assertTrue(Guy(userA).depositToPool(60 * WAD));
        assertTrue(Guy(userB).depositToPool(40 * WAD));
        liquidateSAFE(0);
        log_named_uint("pool had 100 wad sys coins and now has ", tokenCollateral("gold", address(liquidationPool)) / WAD);
        // remaining balance is 10 wad so 6 for A and 4 for B
        assertTrue(!Guy(userA).try_withdrawSystemCoin(6 * WAD + WAD * 10**17));
        assertTrue(!Guy(userB).try_withdrawSystemCoin(4 * WAD + WAD * 10**17));
        assertTrue(Guy(userA).try_withdrawSystemCoin(6 * WAD));
        assertTrue(Guy(userB).try_withdrawSystemCoin(4 * WAD));
    }

    function testPoolSysCoinRemovalPostLiquidationWithComplications() public {
        assertTrue(Guy(userA).depositToPool(60 * WAD));
        assertTrue(Guy(userB).depositToPool(40 * WAD));
        liquidateSAFE(0);
        log_named_uint("pool had 100 wad sys coins and now has ", tokenCollateral("gold", address(liquidationPool)) / WAD);
        // remaining balance is 10 wad so 6 for A and 4 for B
        assertTrue(Guy(userC).depositToPool(50 * WAD));
        assertTrue(!Guy(userC).try_withdrawSystemCoin(51 * WAD));
        assertTrue(Guy(userC).try_withdrawSystemCoin(30 * WAD));
        assertTrue(Guy(userA).try_withdrawSystemCoin(1 * WAD));
        assertTrue(Guy(userB).try_withdrawSystemCoin(1 * WAD));
        assertTrue(!Guy(userA).try_withdrawSystemCoin(5 * WAD + WAD * 10**17));
        assertTrue(!Guy(userB).try_withdrawSystemCoin(3 * WAD + WAD * 10**17));
        assertTrue(Guy(userA).try_withdrawSystemCoin(5 * WAD));
        assertTrue(Guy(userB).try_withdrawSystemCoin(3 * WAD));
    }

    function testPoolRewardsAfterEarlyRemovalOfSysCoins() public {
        assertTrue(Guy(userA).depositToPool(60 * WAD));
        assertTrue(Guy(userB).depositToPool(40 * WAD));
        liquidateSAFE(0);
        assertTrue(Guy(userA).try_withdrawSystemCoin(10 * WAD));
        //Ensure userA who has reduced their shares can still withdraw rewards, 6 for A and 4 for B.
        assertTrue(Guy(userA).try_withdrawRewards());
        assertClose(tokenCollateral("gold", userA), 6 * WAD);
        assertTrue(Guy(userC).depositToPool(50 * WAD));
        assertTrue(Guy(userB).try_withdrawRewards());
        assertClose(tokenCollateral("gold", userB), 4 * WAD);
    }

    // Make sure after claiming rewards and no new liquidations that repeated attempts with new syscoin activity will yield nothing
    function testPoolRepeatedRewardClaim() public {
        assertTrue(Guy(userA).depositToPool(60 * WAD));
        assertTrue(Guy(userB).depositToPool(40 * WAD));
        liquidateSAFE(0);
        assertTrue(Guy(userA).try_withdrawRewards());
        assertClose(tokenCollateral("gold", userA), 6 * WAD);
        assertTrue(Guy(userA).try_withdrawRewards());
        assertClose(tokenCollateral("gold", userA), 6 * WAD);
        assertTrue(Guy(userA).depositToPool(20 * WAD));
        assertTrue(Guy(userC).depositToPool(30 * WAD));
        assertTrue(Guy(userA).try_withdrawRewards());
        assertClose(tokenCollateral("gold", userA), 6 * WAD);
        assertTrue(Guy(userA).try_withdrawSystemCoin(5 * WAD));
        assertTrue(Guy(userB).try_withdrawSystemCoin(3 * WAD));
        assertTrue(Guy(userA).try_withdrawRewards());
        assertClose(tokenCollateral("gold", userA), 6 * WAD);
        //Finally make sure rewards are still there for B to take
        assertTrue(Guy(userB).try_withdrawRewards());
        assertClose(tokenCollateral("gold", userB), 4 * WAD);
    }
}
