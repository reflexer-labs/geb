pragma solidity 0.6.7;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";
import "ds-token/delegate.sol";
import {UniswapV2Factory} from "./uniswapv2mock/core/contracts/UniswapV2Factory.sol";
import {UniswapV2Pair} from "./uniswapv2mock/core/contracts/UniswapV2Pair.sol";
import {UniswapV2Router02} from "./uniswapv2mock/periphery/contracts/UniswapV2Router02.sol";

import {Coin} from '../Coin.sol';
import {SAFEEngine} from '../SAFEEngine.sol';
import {LiquidationEngine} from '../LiquidationEngine.sol';
import {LiquidatingPeggedPool} from '../LiquidatingPeggedPool.sol';
import {AccountingEngine} from '../AccountingEngine.sol';
import {TaxCollector} from '../TaxCollector.sol';
import '../BasicTokenAdapters.sol';
import {OracleRelayer} from "../OracleRelayer.sol";
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
    LiquidatingPeggedPool token;
    Coin systemCoin;

    constructor(LiquidatingPeggedPool liquidatingPeggedPool_, Coin sysCoin) public {
        token = liquidatingPeggedPool_;
        systemCoin = sysCoin;
        systemCoin.approve(address(token), 100 * WAD);
    }

    //systemcoin functions
    function approvePool() public returns (bool ok) {
        string memory sig = "approve(address,uint256)";
        (ok,) = address(systemCoin).call(abi.encodeWithSignature(sig, address(token), uint256(-1)));
    }

    function depositToPool(uint256 wad) public returns (bool ok) {
        string memory sig = "deposit(address,uint256)";
        (ok,) = address(token).call(abi.encodeWithSignature(sig, address(this), wad));
    }

    function try_withdrawSystemCoin(uint256 wad) public returns (bool ok) {
        string memory sig = "withdraw(address,uint256)";
        (ok,) = address(token).call(abi.encodeWithSignature(sig, address(this), wad));
    }

    receive() external payable {}

    // rebase token functions
    function doTransferFrom(address from, address to, uint amount)
        public
        returns (bool)
    {
        return token.transferFrom(from, to, amount);
    }

    function doTransfer(address to, uint amount)
        public
        returns (bool)
    {
        return token.transfer(to, amount);
    }

    function doApprove(address recipient, uint amount)
        public
        returns (bool)
    {
        return token.approve(recipient, amount);
    }

    function doAllowance(address owner, address spender)
        public
        view
        returns (uint)
    {
        return token.allowance(owner, spender);
    }

    function doBalanceOf(address who) public view returns (uint) {
        return token.balanceOf(who);
    }

    function doApprove(address guy)
        public
        returns (bool)
    {
        return token.approve(guy);
    }
    function doPush(address who, uint amount) public {
        token.push(who, amount);
    }
    function doPull(address who, uint amount) public {
        token.pull(who, amount);
    }
    function doMove(address src, address dst, uint amount) public {
        token.move(src, dst, amount);
    }
    function doMint(uint wad) public {
        token.mint(wad);
    }
    function doBurn(uint wad) public {
        token.burn(wad);
    }
    function doMint(address guy, uint wad) public {
        token.mint(guy, wad);
    }
    function doBurn(address guy, uint wad) public {
        token.burn(guy, wad);
    }
}

contract LiquidatingPeggedPoolTest is DSTest {
    Hevm hevm;
    UniswapV2Factory factory;
    UniswapV2Pair pair;
    UniswapV2Router02 router;

    TestSAFEEngine safeEngine;
    TestAccountingEngine accountingEngine;
    LiquidationEngine liquidationEngine;
    LiquidatingPeggedPool liquidatingPeggedPool;
    LiquidatingPeggedPool token;
    OracleRelayer oracleRelayer;
    TaxCollector taxCollector;
    BasicCollateralJoin collateralA;
    EnglishCollateralAuctionHouse collateralAuctionHouse;
    DebtAuctionHouse debtAuctionHouse;
    PostSettlementSurplusAuctionHouse surplusAuctionHouse;

    Coin systemCoin;
    Coin gold;
    DSDelegateToken protocolToken;
    CoinJoin systemCoinA;

    address self;
    address payable user1;
    address payable user2;
    address payable user3;
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 initialBalance;
    uint256 initialSystemCoinBalance;
    uint256 initialRedemptionRate;

    event PrintThree(uint256 a, uint256 b, uint256 c);
    event log_named_address      (string key, address val);
    event log_named_uint         (string key, uint256 val);
    event log_named_bytes32      (string key, bytes32 val);

    function try_modifySAFECollateralization(
      bytes32 collateralType, int lockedCollateral, int generatedDebt
    ) public returns (bool ok) {
        string memory sig = "modifySAFECollateralization(bytes32,address,address,address,int256,int256)";
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
        gold = new Coin("GEM", "GEM", 99);
        gold.mint(address(this), 10000 ether);
        systemCoin = new Coin("TAI", "TAI", 99);
        safeEngine = new TestSAFEEngine();
        safeEngine = safeEngine;
        systemCoinA = new CoinJoin(address(safeEngine), address(systemCoin));
        systemCoin.addAuthorization(address(systemCoinA));
        safeEngine.createUnbackedDebt(address(0x1), address(this), rad(10000 ether));
        safeEngine.approveSAFEModification(address(systemCoinA));
        systemCoinA.exit(address(this), 10000 ether);

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

        //set up uniswap pool with liquidity
        factory = new UniswapV2Factory(address(this));
        pair = UniswapV2Pair(factory.createPair(address(systemCoin), address(gold)));
        router = new UniswapV2Router02(address(factory), address(gold));
        pair.approve(address(router), uint(-1));
        systemCoin.push(address(pair), 1000 * WAD);
        systemCoin.push(address(router), 1000 * WAD);
        gold.push(address(pair), 100 * WAD);
        pair.mint(address(this));

        safeEngine.initializeCollateralType("gold");
        collateralA = new BasicCollateralJoin(address(safeEngine), "gold", address(gold));
        safeEngine.addAuthorization(address(collateralA));
        gold.approve(address(collateralA), uint256(-1));
        collateralA.join(address(this), 1000 ether);
        // collateral is token for whole money god league, may need ETHJoin adaption too.
        liquidatingPeggedPool = new LiquidatingPeggedPool("USDR", "USDR", 99, address(systemCoinA), address(collateralA));
        systemCoin.approve(address(liquidatingPeggedPool), uint256(-1));
        liquidationEngine = new LiquidationEngine(address(safeEngine));
        liquidatingPeggedPool.addAuthorization(address(liquidationEngine));
        liquidatingPeggedPool.modifyParameters("swapRouter", address(router));
        liquidatingPeggedPool.modifyParameters("oracleRelayer", address(router));
        liquidationEngine.modifyParameters("accountingEngine", address(accountingEngine));
        liquidationEngine.modifyParameters("liquidatingPeggedPool", address(liquidatingPeggedPool));
        safeEngine.addAuthorization(address(liquidationEngine));
        accountingEngine.addAuthorization(address(liquidationEngine));

        safeEngine.modifyParameters("gold", "safetyPrice", ray(1 ether));
        safeEngine.modifyParameters("gold", "debtCeiling", rad(1000 ether));
        safeEngine.modifyParameters("globalDebtCeiling", rad(1000 ether));

        oracleRelayer = new OracleRelayer(address(safeEngine));
        initialRedemptionRate = 4 * RAY;
        oracleRelayer.modifyParameters("redemptionPrice", initialRedemptionRate);
        liquidatingPeggedPool.modifyParameters("oracleRelayer", address(oracleRelayer));

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
        gold.approve(address(safeEngine), uint256(-1));
        protocolToken.approve(address(surplusAuctionHouse));

        self = address(this);
        user1 = address(new Guy(liquidatingPeggedPool, systemCoin));
        user2 = address(new Guy(liquidatingPeggedPool, systemCoin));
        user3 = address(new Guy(liquidatingPeggedPool, systemCoin));
        systemCoin.transfer(self, 100 * WAD);
        systemCoin.transfer(user1, 100 * WAD);
        systemCoin.transfer(user2, 100 * WAD);
        systemCoin.transfer(user3, 100 * WAD);
        Guy(user1).approvePool();
        Guy(user2).approvePool();
        Guy(user3).approvePool();
        liquidatingPeggedPool.deposit(self, 100 * WAD);
        initialBalance = liquidatingPeggedPool.balanceOf(address(this));
        initialSystemCoinBalance = systemCoin.balanceOf(self);

        log_named_uint("initialBalance ", initialBalance);
        token = liquidatingPeggedPool; // simpler alias
    }

    function liquidateSAFE(uint256 targetAuctionId) internal {
        uint256 MAX_LIQUIDATION_QUANTITY = uint256(-1) / 10 ** 27;
        liquidationEngine.modifyParameters("gold", "liquidationQuantity", MAX_LIQUIDATION_QUANTITY);
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1.1 ether);

        safeEngine.modifyParameters("globalDebtCeiling", rad(300000 ether));
        safeEngine.modifyParameters("gold", "debtCeiling", rad(300000 ether));
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(5 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(5 ether));
        safeEngine.modifySAFECollateralization("gold", self, self, self, 10 ether, 50 ether);

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

    function systemCoinToRebase(uint256 amount) internal returns (uint256) {
        return amount * (initialRedemptionRate / RAY);
    }

    function rebaseToSystemCoin(uint256 amount) internal returns (uint256) {
        return amount / (initialRedemptionRate / RAY);
    }

    function doubleRedemptionRate() internal {
        oracleRelayer.modifyParameters("redemptionPrice", 8 * RAY);
    }

    function halveRedemptionRate() internal {
        oracleRelayer.modifyParameters("redemptionPrice", 2 * RAY);
    }


    function testPoolDepositsAndWithdrawals() public {
        assertTrue(Guy(user1).depositToPool(40 * WAD));
        assertTrue(Guy(user2).depositToPool(50 * WAD));
        assertTrue(Guy(user3).depositToPool(60 * WAD));
        assertTrue(Guy(user1).depositToPool(40 * WAD));
        //Ensure no one can withdraw more than their share
        assertTrue(!Guy(user2).try_withdrawSystemCoin(50 * WAD + 1));
        assertTrue(!Guy(user1).try_withdrawSystemCoin(80 * WAD + 1));
        assertTrue(!Guy(user3).try_withdrawSystemCoin(60 * WAD + 1));
        assertTrue(Guy(user2).try_withdrawSystemCoin(50 * WAD));
        assertTrue(Guy(user1).try_withdrawSystemCoin(80 * WAD));
        assertTrue(Guy(user3).try_withdrawSystemCoin(60 * WAD));
    }

    function testPoolLiquidation() public {
        assertTrue(Guy(user1).depositToPool(40 * WAD));
        assertTrue(Guy(user2).depositToPool(50 * WAD));
        assertTrue(Guy(user3).depositToPool(60 * WAD));
        uint256 poolInitialBalance = systemCoin.balanceOf(address(liquidatingPeggedPool));
        // ensure stability pool performed liquidation and there are 0 auctions
        liquidateSAFE(0);
        // ensure rebase collateral has been maintained
        uint256 poolFinalBalance = systemCoin.balanceOf(address(liquidatingPeggedPool));
        assertEq(poolInitialBalance, poolFinalBalance);
    }

    function testPoolAllowanceStartsAtZero() public logs_gas {
        assertEq(systemCoin.allowance(user1, user2), 0);
    }
    
    function testPoolValidTransfers() public logs_gas {
        uint256 sendAmount = 25 * WAD;

        log_named_uint("u2 orig bal", token.balanceOf(user2));

        token.transfer(user2, sendAmount);

        log_named_uint("u2 fina bal", token.balanceOf(user2));

        assertClose(token.balanceOf(user2), sendAmount);
        assertClose(token.balanceOf(self), initialBalance - sendAmount);
    }

    function testFailPoolWrongAccountTransfers() public logs_gas {
        uint sentAmount = 250;
        token.transferFrom(user2, self, sentAmount);
    }

    function testFailPoolInsufficientFundsTransfers() public logs_gas {
        uint sentAmount = 25 * WAD;
        token.transfer(user1, initialBalance - sentAmount);
        token.transfer(user2, sentAmount + 10);
    }

    function testPoolApproveSetsAllowance() public logs_gas {
        token.approve(user2, 25);
        assertEq(token.allowance(self, user2), 25);
    }

    function testChargesAmountApproved() public logs_gas {
        uint amountApproved = 20 * WAD;
        token.approve(user2, amountApproved);
        assertTrue(Guy(user2).doTransferFrom(self, user2, amountApproved));
        assertClose(token.balanceOf(self), initialBalance - amountApproved);
    }

    function testFailTransferWithoutApproval() public logs_gas {
        token.transfer(user1, 50 * WAD);
        token.transferFrom(user1, self, 1);
    }

    function testFailChargeMoreThanApproved() public logs_gas {
        token.transfer(user1, 50 * WAD);
        Guy(user1).doApprove(self, 20 * WAD);
        token.transferFrom(user1, self, 21 * WAD);
    }
    function testTransferFromSelf() public {
        token.transferFrom(self, user1, 50 * WAD);
        assertClose(token.balanceOf(user1), 50 * WAD);
    }
    function testFailTransferFromSelfNonArbitrarySize() public {
        // you shouldn't be able to evade balance checks by transferring
        // to yourself
        token.transferFrom(self, self, token.balanceOf(self) + 1 * WAD);
    }

    function testMint() public {
        uint mintAmount = 10 * WAD;
        token.mint(mintAmount);
        assertClose(token.totalSupply(), initialBalance + systemCoinToRebase(mintAmount));
    }
    function testMintself() public {
        uint mintAmount = 10 * WAD;
        token.mint(mintAmount);
        assertClose(token.balanceOf(self), initialBalance + systemCoinToRebase(mintAmount));
    }
    function testMintGuy() public {
        uint mintAmount = 10 * WAD;
        token.mint(user1, mintAmount);
        assertClose(token.balanceOf(user1), systemCoinToRebase(mintAmount));
    }
    function testFailMintInsufficientSystemCoin() public {
        Guy(user1).doMint(10000 * WAD);
    }
    function testBurn() public {
        uint burnAmount = 10 * WAD;
        token.burn(burnAmount);
        assertClose(token.totalSupply(), initialBalance - systemCoinToRebase(burnAmount));
        assertClose(systemCoin.balanceOf(self), initialSystemCoinBalance + burnAmount);
    }
    function testFailBurnInsufficientBalance() public {
        token.transfer(user1, 10 * WAD);
        Guy(user1).doBurn(11 * WAD);
    }

    function testFailUntrustedTransferFrom() public {
        assertClose(token.allowance(self, user2), 0);
        Guy(user1).doTransferFrom(self, user2, 200);
    }
    function testTrusting() public {
        assertClose(token.allowance(self, user2), 0);
        token.approve(user2, 100 * WAD);
        assertClose(token.allowance(self, user2), 100 * WAD);
        token.approve(user2, 0);
        assertClose(token.allowance(self, user2), 0);
    }
    function testTrustedTransferFrom() public {
        token.approve(user1);
        Guy(user1).doTransferFrom(self, user2, 200 * WAD);
        assertClose(token.balanceOf(user2), 200 * WAD);
    }
    function testPush() public {
        assertClose(token.balanceOf(user1), 0);
        token.push(user1, 100 * WAD);
        assertClose(token.balanceOf(self), initialBalance - 100 * WAD);
        assertClose(token.balanceOf(user1), 100 * WAD);
        Guy(user1).doPush(user2, 50 * WAD);
        assertClose(token.balanceOf(user1), 50 * WAD);
        assertClose(token.balanceOf(user2), 50 * WAD);
    }
    function testFailPullWithoutTrust() public {
        Guy(user1).doPull(self, 1000);
    }
    function testPullWithTrust() public {
        token.approve(user1);
        Guy(user1).doPull(self, 1000);
    }
    function testFailMoveWithoutTrust() public {
        Guy(user1).doMove(self, user2, 1000);
    }
    function testMoveWithTrust() public {
        token.approve(user1);
        Guy(user1).doMove(self, user2, 1000);
    }
    function testApproveWillModifyAllowance() public {
        assertClose(token.allowance(self, user1), 0);
        assertClose(token.balanceOf(user1), 0);
        token.approve(user1, 50 * WAD);
        assertClose(token.allowance(self, user1), 50 * WAD);
        Guy(user1).doPull(self, 40 * WAD);
        assertClose(token.balanceOf(user1), 40 * WAD);
        assertClose(token.allowance(self, user1), 10 * WAD);
    }
    function testFailTransferOnlyTrustedCaller() public {
        // only the entity actually trusted should be able to call
        // and move tokens.
        token.push(user1, 1);
        Guy(user1).doApprove(user2);
        token.transferFrom(user1, user2, 1);
    }

    function testModifyingRedemptionRate() public {
        // double redemption rate
        oracleRelayer.modifyParameters("redemptionPrice", 4 * RAY);
    }

    function testFailBalancesAfterRedemptionRateChangeNoUpdate() public {
        assertClose(token.balanceOf(user1), 0);
        token.push(user1, 100 * WAD);
        assertClose(token.balanceOf(self), initialBalance - 100 * WAD);
        assertClose(token.balanceOf(user1), 100 * WAD);
        Guy(user1).doPush(user2, 50 * WAD);
        assertClose(token.balanceOf(user1), 50 * WAD);
        assertClose(token.balanceOf(user2), 50 * WAD);
        doubleRedemptionRate();
        assertClose(token.balanceOf(user1), 100 * WAD);
        assertClose(token.balanceOf(user2), 100 * WAD);
        halveRedemptionRate();
        assertClose(token.balanceOf(user1), 25 * WAD);
        assertClose(token.balanceOf(user2), 25 * WAD);
    }

    function testBalancesAfterRedemptionRateChangeWithUpdate() public {
        assertClose(token.balanceOf(user1), 0);
        token.push(user1, 100 * WAD);
        assertClose(token.balanceOf(self), initialBalance - 100 * WAD);
        assertClose(token.balanceOf(user1), 100 * WAD);
        Guy(user1).doPush(user2, 50 * WAD);
        assertClose(token.balanceOf(user1), 50 * WAD);
        assertClose(token.balanceOf(user2), 50 * WAD);
        doubleRedemptionRate();
        token.withdraw(self, 1 * WAD);
        assertClose(token.balanceOf(user1), 100 * WAD);
        assertClose(token.balanceOf(user2), 100 * WAD);
        halveRedemptionRate();
        token.withdraw(self, 1 * WAD);
        assertClose(token.balanceOf(user1), 25 * WAD);
        assertClose(token.balanceOf(user2), 25 * WAD);
    }

    function testCanStillWithdrawAllSystemCoinAfterRateChange() public {
        uint256 user1InitialSysCoinBal = systemCoin.balanceOf(user1);
        token.push(user1, 100 * WAD);
        assertClose(token.balanceOf(user1), 100 * WAD);
        halveRedemptionRate();
        token.withdraw(self, 1 * WAD);
        assertClose(token.balanceOf(user1), 50 * WAD);
        Guy(user1).doBurn(token.balanceInSystemCoin(user1));
        assertClose(user1InitialSysCoinBal, systemCoin.balanceOf(user1) - rebaseToSystemCoin(100 * WAD));
    }

    function testApprovalsUnaffectedByRedemptionRate() public {
        assertClose(token.allowance(self, user1), 0);
        assertClose(token.balanceOf(user1), 0);
        token.approve(user1, 50 * WAD);
        halveRedemptionRate();
        token.withdraw(self, 1 * WAD);
        assertClose(token.allowance(self, user1), 50 * WAD);
        Guy(user1).doPull(self, 40 * WAD);
        assertClose(token.balanceOf(user1), 40 * WAD);
        doubleRedemptionRate();
        token.withdraw(self, 1 * WAD);
        assertClose(token.allowance(self, user1), 10 * WAD);
    }
}
