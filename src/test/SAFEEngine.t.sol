pragma solidity 0.6.7;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";
import "ds-token/delegate.sol";

import {SAFEEngine} from '../SAFEEngine.sol';
import {LiquidationEngine} from '../LiquidationEngine.sol';
import {AccountingEngine} from '../AccountingEngine.sol';
import {TaxCollector} from '../TaxCollector.sol';
import '../BasicTokenAdapters.sol';

import {EnglishCollateralAuctionHouse} from './CollateralAuctionHouse.t.sol';
import {DebtAuctionHouse} from './DebtAuctionHouse.t.sol';
import {PostSettlementSurplusAuctionHouse} from './SurplusAuctionHouse.t.sol';

abstract contract Hevm {
    function warp(uint256) virtual public;
    function store(address,bytes32,bytes32) virtual external;
}
abstract contract HevmWarped {
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

contract Usr {
    SAFEEngine public safeEngine;
    constructor(SAFEEngine safeEngine_) public {
        safeEngine = safeEngine_;
    }
    function try_call(address addr, bytes calldata data) external returns (bool) {
        bytes memory _data = data;
        assembly {
            let ok := call(gas(), addr, 0, add(_data, 0x20), mload(_data), 0, 0)
            let free := mload(0x40)
            mstore(free, ok)
            mstore(0x40, add(free, 32))
            revert(free, 32)
        }
    }
    function can_modifySAFECollateralization(
      bytes32 collateralType,
      address safe,
      address collateralSource,
      address debtDestination,
      int deltaCollateral,
      int deltaDebt
    ) public returns (bool) {
        string memory sig = "modifySAFECollateralization(bytes32,address,address,address,int256,int256)";
        bytes memory data = abi.encodeWithSignature(
          sig, collateralType, safe, collateralSource, debtDestination, deltaCollateral, deltaDebt
        );

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", safeEngine, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function can_transferSAFECollateralAndDebt(
      bytes32 collateralType, address src, address dst, int deltaCollateral, int deltaDebt
    ) public returns (bool) {
        string memory sig = "transferSAFECollateralAndDebt(bytes32,address,address,int256,int256)";
        bytes memory data = abi.encodeWithSignature(sig, collateralType, src, dst, deltaCollateral, deltaDebt);

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", safeEngine, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function approve(address token, address target, uint wad) external {
        DSDelegateToken(token).approve(target, wad);
    }
    function join(address adapter, address safe, uint wad) external {
        BasicCollateralJoin(adapter).join(safe, wad);
    }
    function exit(address adapter, address safe, uint wad) external {
        BasicCollateralJoin(adapter).exit(safe, wad);
    }
    function modifySAFECollateralization(
      bytes32 collateralType, address safe, address collateralSrc, address debtDst, int deltaCollateral, int deltaDebt
    ) public {
        safeEngine.modifySAFECollateralization(collateralType, safe, collateralSrc, debtDst, deltaCollateral, deltaDebt);
    }
    function transferSAFECollateralAndDebt(
      bytes32 collateralType, address src, address dst, int deltaCollateral, int deltaDebt
    ) public {
        safeEngine.transferSAFECollateralAndDebt(collateralType, src, dst, deltaCollateral, deltaDebt);
    }
    function approveSAFEModification(address usr) public {
        safeEngine.approveSAFEModification(usr);
    }
}

contract ModifySAFECollateralizationTest is DSTest {
    TestSAFEEngine safeEngine;
    DSDelegateToken gold;
    DSDelegateToken stable;
    TaxCollector taxCollector;

    BasicCollateralJoin collateralA;
    address me;

    uint constant RAY = 10 ** 27;

    function try_modifySAFECollateralization(bytes32 collateralType, int collateralToDeposit, int generatedDebt) public returns (bool ok) {
        string memory sig = "modifySAFECollateralization(bytes32,address,address,address,int256,int256)";
        address self = address(this);
        (ok,) = address(safeEngine).call(abi.encodeWithSignature(sig, collateralType, self, self, self, collateralToDeposit, generatedDebt));
    }

    function try_transferSAFECollateralAndDebt(bytes32 collateralType, address dst, int deltaCollateral, int deltaDebt) public returns (bool ok) {
        string memory sig = "transferSAFECollateralAndDebt(bytes32,address,address,int256,int256)";
        address self = address(this);
        (ok,) = address(safeEngine).call(abi.encodeWithSignature(sig, collateralType, self, dst, deltaCollateral, deltaDebt));
    }

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }

    function setUp() public {
        safeEngine = new TestSAFEEngine();

        gold = new DSDelegateToken("GEM", '');
        gold.mint(1000 ether);

        safeEngine.initializeCollateralType("gold");

        collateralA = new BasicCollateralJoin(address(safeEngine), "gold", address(gold));

        safeEngine.modifyParameters("gold", "safetyPrice",    ray(1 ether));
        safeEngine.modifyParameters("gold", "debtCeiling", rad(1000 ether));
        safeEngine.modifyParameters("globalDebtCeiling", rad(1000 ether));

        taxCollector = new TaxCollector(address(safeEngine));
        taxCollector.initializeCollateralType("gold");
        safeEngine.addAuthorization(address(taxCollector));

        gold.approve(address(collateralA));
        gold.approve(address(safeEngine));

        safeEngine.addAuthorization(address(safeEngine));
        safeEngine.addAuthorization(address(collateralA));

        collateralA.join(address(this), 1000 ether);

        me = address(this);
    }

    function tokenCollateral(bytes32 collateralType, address safe) internal view returns (uint) {
        return safeEngine.tokenCollateral(collateralType, safe);
    }
    function lockedCollateral(bytes32 collateralType, address safe) internal view returns (uint) {
        (uint lockedCollateral_, uint generatedDebt_) =
          safeEngine.safes(collateralType, safe); generatedDebt_;
        return lockedCollateral_;
    }
    function generatedDebt(bytes32 collateralType, address safe) internal view returns (uint) {
        (uint lockedCollateral_, uint generatedDebt_) =
          safeEngine.safes(collateralType, safe); lockedCollateral_;
        return generatedDebt_;
    }

    function test_setup() public {
        assertEq(gold.balanceOf(address(collateralA)), 1000 ether);
        assertEq(tokenCollateral("gold", address(this)), 1000 ether);
    }
    function test_join() public {
        address safe = address(this);
        gold.mint(500 ether);
        assertEq(gold.balanceOf(address(this)),    500 ether);
        assertEq(gold.balanceOf(address(collateralA)),   1000 ether);
        collateralA.join(safe,                             500 ether);
        assertEq(gold.balanceOf(address(this)),      0 ether);
        assertEq(gold.balanceOf(address(collateralA)),   1500 ether);
        collateralA.exit(safe,                             250 ether);
        assertEq(gold.balanceOf(address(this)),    250 ether);
        assertEq(gold.balanceOf(address(collateralA)),   1250 ether);
    }
    function test_lock() public {
        assertEq(lockedCollateral("gold", address(this)), 0 ether);
        assertEq(tokenCollateral("gold", address(this)), 1000 ether);
        safeEngine.modifySAFECollateralization("gold", me, me, me, 6 ether, 0);
        assertEq(lockedCollateral("gold", address(this)),   6 ether);
        assertEq(tokenCollateral("gold", address(this)), 994 ether);
        safeEngine.modifySAFECollateralization("gold", me, me, me, -6 ether, 0);
        assertEq(lockedCollateral("gold", address(this)),    0 ether);
        assertEq(tokenCollateral("gold", address(this)), 1000 ether);
    }
    function test_calm() public {
        // calm means that the debt ceiling is not exceeded
        // it's ok to increase debt as long as you remain calm
        safeEngine.modifyParameters("gold", 'debtCeiling', rad(10 ether));
        assertTrue( try_modifySAFECollateralization("gold", 10 ether, 9 ether));
        // only if under debt ceiling
        assertTrue(!try_modifySAFECollateralization("gold",  0 ether, 2 ether));
    }
    function test_cool() public {
        // cool means that the debt has decreased
        // it's ok to be over the debt ceiling as long as you're cool
        safeEngine.modifyParameters("gold", 'debtCeiling', rad(10 ether));
        assertTrue(try_modifySAFECollateralization("gold", 10 ether,  8 ether));
        safeEngine.modifyParameters("gold", 'debtCeiling', rad(5 ether));
        // can decrease debt when over ceiling
        assertTrue(try_modifySAFECollateralization("gold",  0 ether, -1 ether));
    }
    function test_safe() public {
        // safe means that the safe is not risky
        // you can't frob a safe into unsafe
        safeEngine.modifySAFECollateralization("gold", me, me, me, 10 ether, 5 ether); // safe draw
        assertTrue(!try_modifySAFECollateralization("gold", 0 ether, 6 ether));  // unsafe draw
    }
    function test_nice() public {
        // nice means that the collateral has increased or the debt has
        // decreased. remaining unsafe is ok as long as you're nice

        safeEngine.modifySAFECollateralization("gold", me, me, me, 10 ether, 10 ether);
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(0.5 ether));  // now unsafe

        // debt can't increase if unsafe
        assertTrue(!try_modifySAFECollateralization("gold",  0 ether,  1 ether));
        // debt can decrease
        assertTrue( try_modifySAFECollateralization("gold",  0 ether, -1 ether));
        // lockedCollateral can't decrease
        assertTrue(!try_modifySAFECollateralization("gold", -1 ether,  0 ether));
        // lockedCollateral can increase
        assertTrue( try_modifySAFECollateralization("gold",  1 ether,  0 ether));

        // safe is still unsafe
        // lockedCollateral can't decrease, even if debt decreases more
        assertTrue(!this.try_modifySAFECollateralization("gold", -2 ether, -4 ether));
        // debt can't increase, even if lockedCollateral increases more
        assertTrue(!this.try_modifySAFECollateralization("gold",  5 ether,  1 ether));

        // lockedCollateral can decrease if end state is safe
        assertTrue( this.try_modifySAFECollateralization("gold", -1 ether, -4 ether));
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(0.4 ether));  // now unsafe
        // debt can increase if end state is safe
        assertTrue( this.try_modifySAFECollateralization("gold",  5 ether, 1 ether));
    }

    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }
    function test_alt_callers() public {
        Usr ali = new Usr(safeEngine);
        Usr bob = new Usr(safeEngine);
        Usr che = new Usr(safeEngine);

        address a = address(ali);
        address b = address(bob);
        address c = address(che);

        safeEngine.addAuthorization(a);
        safeEngine.addAuthorization(b);
        safeEngine.addAuthorization(c);

        safeEngine.modifyCollateralBalance("gold", a, int(rad(20 ether)));
        safeEngine.modifyCollateralBalance("gold", b, int(rad(20 ether)));
        safeEngine.modifyCollateralBalance("gold", c, int(rad(20 ether)));

        ali.modifySAFECollateralization("gold", a, a, a, 10 ether, 5 ether);

        // anyone can lock
        assertTrue( ali.can_modifySAFECollateralization("gold", a, a, a,  1 ether,  0 ether));
        assertTrue( bob.can_modifySAFECollateralization("gold", a, b, b,  1 ether,  0 ether));
        assertTrue( che.can_modifySAFECollateralization("gold", a, c, c,  1 ether,  0 ether));
        // but only with their own tokenss
        assertTrue(!ali.can_modifySAFECollateralization("gold", a, b, a,  1 ether,  0 ether));
        assertTrue(!bob.can_modifySAFECollateralization("gold", a, c, b,  1 ether,  0 ether));
        assertTrue(!che.can_modifySAFECollateralization("gold", a, a, c,  1 ether,  0 ether));

        // only the lad can frob
        assertTrue( ali.can_modifySAFECollateralization("gold", a, a, a, -1 ether,  0 ether));
        assertTrue(!bob.can_modifySAFECollateralization("gold", a, b, b, -1 ether,  0 ether));
        assertTrue(!che.can_modifySAFECollateralization("gold", a, c, c, -1 ether,  0 ether));
        // the lad can frob to anywhere
        assertTrue( ali.can_modifySAFECollateralization("gold", a, b, a, -1 ether,  0 ether));
        assertTrue( ali.can_modifySAFECollateralization("gold", a, c, a, -1 ether,  0 ether));

        // only the lad can draw
        assertTrue( ali.can_modifySAFECollateralization("gold", a, a, a,  0 ether,  1 ether));
        assertTrue(!bob.can_modifySAFECollateralization("gold", a, b, b,  0 ether,  1 ether));
        assertTrue(!che.can_modifySAFECollateralization("gold", a, c, c,  0 ether,  1 ether));
        // the lad can draw to anywhere
        assertTrue( ali.can_modifySAFECollateralization("gold", a, a, b,  0 ether,  1 ether));
        assertTrue( ali.can_modifySAFECollateralization("gold", a, a, c,  0 ether,  1 ether));

        safeEngine.mint(address(bob), 1 ether);
        safeEngine.mint(address(che), 1 ether);

        // anyone can wipe
        assertTrue( ali.can_modifySAFECollateralization("gold", a, a, a,  0 ether, -1 ether));
        assertTrue( bob.can_modifySAFECollateralization("gold", a, b, b,  0 ether, -1 ether));
        assertTrue( che.can_modifySAFECollateralization("gold", a, c, c,  0 ether, -1 ether));
        // but only with their own coin
        assertTrue(!ali.can_modifySAFECollateralization("gold", a, a, b,  0 ether, -1 ether));
        assertTrue(!bob.can_modifySAFECollateralization("gold", a, b, c,  0 ether, -1 ether));
        assertTrue(!che.can_modifySAFECollateralization("gold", a, c, a,  0 ether, -1 ether));
    }

    function test_approveSAFEModification() public {
        Usr ali = new Usr(safeEngine);
        Usr bob = new Usr(safeEngine);
        Usr che = new Usr(safeEngine);

        address a = address(ali);
        address b = address(bob);
        address c = address(che);

        safeEngine.modifyCollateralBalance("gold", a, int(rad(20 ether)));
        safeEngine.modifyCollateralBalance("gold", b, int(rad(20 ether)));
        safeEngine.modifyCollateralBalance("gold", c, int(rad(20 ether)));

        safeEngine.addAuthorization(a);
        safeEngine.addAuthorization(b);
        safeEngine.addAuthorization(c);

        ali.modifySAFECollateralization("gold", a, a, a, 10 ether, 5 ether);

        // only owner can do risky actions
        assertTrue( ali.can_modifySAFECollateralization("gold", a, a, a,  0 ether,  1 ether));
        assertTrue(!bob.can_modifySAFECollateralization("gold", a, b, b,  0 ether,  1 ether));
        assertTrue(!che.can_modifySAFECollateralization("gold", a, c, c,  0 ether,  1 ether));

        ali.approveSAFEModification(address(bob));

        // unless they hope another user
        assertTrue( ali.can_modifySAFECollateralization("gold", a, a, a,  0 ether,  1 ether));
        assertTrue( bob.can_modifySAFECollateralization("gold", a, b, b,  0 ether,  1 ether));
        assertTrue(!che.can_modifySAFECollateralization("gold", a, c, c,  0 ether,  1 ether));
    }

    function test_debtFloor() public {
        assertTrue( try_modifySAFECollateralization("gold", 9 ether,  1 ether));
        safeEngine.modifyParameters("gold", "debtFloor", rad(5 ether));
        assertTrue(!try_modifySAFECollateralization("gold", 5 ether,  2 ether));
        assertTrue( try_modifySAFECollateralization("gold", 0 ether,  5 ether));
        assertTrue(!try_modifySAFECollateralization("gold", 0 ether, -5 ether));
        assertTrue( try_modifySAFECollateralization("gold", 0 ether, -6 ether));
    }
}

contract SAFEDebtLimitTest is DSTest {
  Hevm hevm;

  TestSAFEEngine safeEngine;
  DSDelegateToken gold;
  DSDelegateToken stable;
  TaxCollector taxCollector;

  BasicCollateralJoin collateralA;
  address me;

  uint constant RAY = 10 ** 27;

  function try_modifySAFECollateralization(bytes32 collateralType, int collateralToDeposit, int generatedDebt) public returns (bool ok) {
      string memory sig = "modifySAFECollateralization(bytes32,address,address,address,int256,int256)";
      address self = address(this);
      (ok,) = address(safeEngine).call(abi.encodeWithSignature(sig, collateralType, self, self, self, collateralToDeposit, generatedDebt));
  }

  function try_transferSAFECollateralAndDebt(bytes32 collateralType, address dst, int deltaCollateral, int deltaDebt) public returns (bool ok) {
      string memory sig = "transferSAFECollateralAndDebt(bytes32,address,address,int256,int256)";
      address self = address(this);
      (ok,) = address(safeEngine).call(abi.encodeWithSignature(sig, collateralType, self, dst, deltaCollateral, deltaDebt));
  }

  function ray(uint wad) internal pure returns (uint) {
      return wad * 10 ** 9;
  }
  function rad(uint wad) internal pure returns (uint) {
      return wad * 10 ** 27;
  }

  function setUp() public {
      hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
      hevm.warp(604411200);

      safeEngine = new TestSAFEEngine();

      gold = new DSDelegateToken("GEM", '');
      gold.mint(1000 ether);

      safeEngine.initializeCollateralType("gold");

      collateralA = new BasicCollateralJoin(address(safeEngine), "gold", address(gold));

      safeEngine.modifyParameters("gold", "safetyPrice",    ray(1 ether));
      safeEngine.modifyParameters("gold", "debtCeiling", rad(1000 ether));
      safeEngine.modifyParameters("globalDebtCeiling", rad(1000 ether));

      taxCollector = new TaxCollector(address(safeEngine));
      taxCollector.initializeCollateralType("gold");
      taxCollector.modifyParameters("primaryTaxReceiver", address(0x1234));
      taxCollector.modifyParameters("gold", "stabilityFee", 1000000564701133626865910626);  // 5% / day
      safeEngine.addAuthorization(address(taxCollector));

      gold.approve(address(collateralA));
      gold.approve(address(safeEngine));

      safeEngine.addAuthorization(address(safeEngine));
      safeEngine.addAuthorization(address(collateralA));

      collateralA.join(address(this), 1000 ether);

      safeEngine.modifyParameters("gold", 'debtCeiling', rad(10 ether));
      safeEngine.modifyParameters('safeDebtCeiling', 5 ether);

      me = address(this);
  }

  function tokenCollateral(bytes32 collateralType, address safe) internal view returns (uint) {
      return safeEngine.tokenCollateral(collateralType, safe);
  }
  function lockedCollateral(bytes32 collateralType, address safe) internal view returns (uint) {
      (uint lockedCollateral_, uint generatedDebt_) =
        safeEngine.safes(collateralType, safe); generatedDebt_;
      return lockedCollateral_;
  }
  function generatedDebt(bytes32 collateralType, address safe) internal view returns (uint) {
      (uint lockedCollateral_, uint generatedDebt_) =
        safeEngine.safes(collateralType, safe); lockedCollateral_;
      return generatedDebt_;
  }

  function test_setup() public {
      assertEq(gold.balanceOf(address(collateralA)), 1000 ether);
      assertEq(tokenCollateral("gold", address(this)), 1000 ether);
      assertEq(safeEngine.safeDebtCeiling(), 5 ether);
  }
  function testFail_generate_debt_above_safe_limit() public {
      Usr ali = new Usr(safeEngine);
      address a = address(ali);

      safeEngine.addAuthorization(a);
      safeEngine.modifyCollateralBalance("gold", a, int(rad(20 ether)));

      ali.modifySAFECollateralization("gold", a, a, a, 10 ether, 7 ether);
  }
  function testFail_generate_debt_above_collateral_ceiling_but_below_safe_limit() public {
      safeEngine.modifyParameters("gold", 'debtCeiling', rad(4 ether));
      assertTrue(try_modifySAFECollateralization("gold", 10 ether, 4.5 ether));
  }
  function test_repay_debt() public {
      Usr ali = new Usr(safeEngine);
      address a = address(ali);

      safeEngine.addAuthorization(a);
      safeEngine.modifyCollateralBalance("gold", a, int(rad(20 ether)));

      ali.modifySAFECollateralization("gold", a, a, a, 10 ether, 5 ether);
      ali.modifySAFECollateralization("gold", a, a, a, 0, -5 ether);
  }
  function test_tax_and_repay_debt() public {
      Usr ali = new Usr(safeEngine);
      address a = address(ali);

      safeEngine.addAuthorization(a);
      safeEngine.modifyCollateralBalance("gold", a, int(rad(20 ether)));

      ali.modifySAFECollateralization("gold", a, a, a, 10 ether, 5 ether);

      hevm.warp(now + 1 days);
      taxCollector.taxSingle("gold");

      ali.modifySAFECollateralization("gold", a, a, a, 0, -4 ether);
  }
  function test_change_safe_limit_and_modify_cratio() public {
      Usr ali = new Usr(safeEngine);
      address a = address(ali);

      safeEngine.addAuthorization(a);
      safeEngine.modifyCollateralBalance("gold", a, int(rad(20 ether)));

      ali.modifySAFECollateralization("gold", a, a, a, 10 ether, 5 ether);

      safeEngine.modifyParameters('safeDebtCeiling', 4 ether);

      assertTrue(!try_modifySAFECollateralization("gold", 0, 2 ether));
      ali.modifySAFECollateralization("gold", a, a, a, 0, -1 ether);
      assertTrue(!try_modifySAFECollateralization("gold", 0, 2 ether));

      safeEngine.modifyParameters('safeDebtCeiling', uint(-1));
      ali.modifySAFECollateralization("gold", a, a, a, 0, 4 ether);
  }
}

contract JoinTest is DSTest {
    TestSAFEEngine safeEngine;
    DSDelegateToken collateral;
    BasicCollateralJoin collateralA;
    ETHJoin ethA;
    CoinJoin coinA;
    DSDelegateToken coin;
    address me;

    uint constant WAD = 10 ** 18;

    function setUp() public {
        safeEngine = new TestSAFEEngine();
        safeEngine.initializeCollateralType("ETH");

        collateral  = new DSDelegateToken("Gem", 'Gem');
        collateralA = new BasicCollateralJoin(address(safeEngine), "collateral", address(collateral));
        safeEngine.addAuthorization(address(collateralA));

        ethA = new ETHJoin(address(safeEngine), "ETH");
        safeEngine.addAuthorization(address(ethA));

        coin  = new DSDelegateToken("Coin", 'Coin');
        coinA = new CoinJoin(address(safeEngine), address(coin));
        safeEngine.addAuthorization(address(coinA));
        coin.setOwner(address(coinA));

        me = address(this);
    }
    function draw(bytes32 collateralType, int wad, int coin_) internal {
        address self = address(this);
        safeEngine.modifyCollateralBalance(collateralType, self, wad);
        safeEngine.modifySAFECollateralization(collateralType, self, self, self, wad, coin_);
    }
    function try_disable_contract(address a) public payable returns (bool ok) {
        string memory sig = "disableContract()";
        (ok,) = a.call(abi.encodeWithSignature(sig));
    }
    function try_join_tokenCollateral(address usr, uint wad) public returns (bool ok) {
        string memory sig = "join(address,uint256)";
        (ok,) = address(collateralA).call(abi.encodeWithSignature(sig, usr, wad));
    }
    function try_join_eth(address usr) public payable returns (bool ok) {
        string memory sig = "join(address)";
        (ok,) = address(ethA).call{value: msg.value}(abi.encodeWithSignature(sig, usr));
    }
    function try_exit_coin(address usr, uint wad) public returns (bool ok) {
        string memory sig = "exit(address,uint256)";
        (ok,) = address(coinA).call(abi.encodeWithSignature(sig, usr, wad));
    }

    receive () external payable {}
    function test_collateral_join() public {
        collateral.mint(20 ether);
        collateral.approve(address(collateralA), 20 ether);
        assertTrue( try_join_tokenCollateral(address(this), 10 ether));
        assertEq(safeEngine.tokenCollateral("collateral", me), 10 ether);
        assertTrue( try_disable_contract(address(collateralA)));
        assertTrue(!try_join_tokenCollateral(address(this), 10 ether));
        assertEq(safeEngine.tokenCollateral("collateral", me), 10 ether);
    }
    function test_eth_join() public {
        assertTrue( this.try_join_eth{value: 10 ether}(address(this)));
        assertEq(safeEngine.tokenCollateral("ETH", me), 10 ether);
        assertTrue( try_disable_contract(address(ethA)));
        assertTrue(!this.try_join_eth{value: 10 ether}(address(this)));
        assertEq(safeEngine.tokenCollateral("ETH", me), 10 ether);
    }
    function test_eth_exit() public {
        address payable safe = address(this);
        ethA.join{value: 50 ether}(safe);
        ethA.exit(safe, 10 ether);
        assertEq(safeEngine.tokenCollateral("ETH", me), 40 ether);
    }
    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }
    function test_coin_exit() public {
        address safe = address(this);
        safeEngine.mint(address(this), 100 ether);
        safeEngine.approveSAFEModification(address(coinA));
        assertTrue( try_exit_coin(safe, 40 ether));
        assertEq(coin.balanceOf(address(this)), 40 ether);
        assertEq(safeEngine.coinBalance(me), rad(60 ether));
        assertTrue( try_disable_contract(address(coinA)));
        assertTrue(!try_exit_coin(safe, 40 ether));
        assertEq(coin.balanceOf(address(this)), 40 ether);
        assertEq(safeEngine.coinBalance(me), rad(60 ether));
    }
    function test_coin_exit_join() public {
        address safe = address(this);
        safeEngine.mint(address(this), 100 ether);
        safeEngine.approveSAFEModification(address(coinA));
        coinA.exit(safe, 60 ether);
        coin.approve(address(coinA), uint(-1));
        coinA.join(safe, 30 ether);
        assertEq(coin.balanceOf(address(this)), 30 ether);
        assertEq(safeEngine.coinBalance(me), rad(70 ether));
    }
    function test_fallback_reverts() public {
        (bool ok,) = address(ethA).call("invalid calldata");
        assertTrue(!ok);
    }
    function test_nonzero_fallback_reverts() public {
        (bool ok,) = address(ethA).call{value: 10}("invalid calldata");
        assertTrue(!ok);
    }
    function test_disable_contract_no_access() public {
        collateralA.removeAuthorization(address(this));
        assertTrue(!try_disable_contract(address(collateralA)));
        ethA.removeAuthorization(address(this));
        assertTrue(!try_disable_contract(address(ethA)));
        coinA.removeAuthorization(address(this));
        assertTrue(!try_disable_contract(address(coinA)));
    }
}

abstract contract EnglishCollateralAuctionHouseLike {
    struct Bid {
        uint256 bidAmount;
        uint256 amountToSell;
        address highBidder;
        uint48  bidExpiry;
        uint48  auctionDeadline;
        address safeAuctioned;
        address auctionIncomeRecipient;
        uint256 amountToRaise;
    }
    function bids(uint) virtual public view returns (
        uint256 bidAmount,
        uint256 amountToSell,
        address highBidder,
        uint48  bidExpiry,
        uint48  auctionDeadline,
        address safeAuctioned,
        address auctionIncomeRecipient,
        uint256 amountToRaise
    );
}

contract ProtocolTokenAuthority {
    mapping (address => uint) public authorizedAccounts;

    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) external {
        authorizedAccounts[account] = 1;
    }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(address account) external {
        authorizedAccounts[account] = 0;
    }
}

contract LiquidationTest is DSTest {
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

    ProtocolTokenAuthority tokenAuthority;

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

        protocolToken = new DSDelegateToken('GOV', '');
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

        gold = new DSDelegateToken("GEM", '');
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

        tokenAuthority = new ProtocolTokenAuthority();
        tokenAuthority.addAuthorization(address(debtAuctionHouse));

        accountingEngine.modifyParameters("protocolTokenAuthority", address(tokenAuthority));

        me = address(this);
    }

    function test_set_liquidation_quantity() public {
        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(115792 ether));
        (,, uint256 liquidationQuantity) = liquidationEngine.collateralTypes("gold");
        assertEq(liquidationQuantity, rad(115792 ether));
    }
    function test_set_auction_system_coin_limit() public {
        liquidationEngine.modifyParameters("onAuctionSystemCoinLimit", rad(1));
        assertEq(liquidationEngine.onAuctionSystemCoinLimit(), rad(1));
    }
    function testFail_liquidation_quantity_too_large() public {
        liquidationEngine.modifyParameters("gold", "liquidationQuantity", uint256(-1) / 10 ** 27 + 1);
    }
    function test_liquidate_max_liquidation_quantity() public {
        uint256 MAX_LIQUIDATION_QUANTITY = uint256(-1) / 10 ** 27;
        liquidationEngine.modifyParameters("gold", "liquidationQuantity", MAX_LIQUIDATION_QUANTITY);

        safeEngine.modifyParameters("globalDebtCeiling", rad(300000 ether));
        safeEngine.modifyParameters("gold", "debtCeiling", rad(300000 ether));
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(205 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(205 ether));
        safeEngine.modifySAFECollateralization("gold", me, me, me, 1000 ether, 200000 ether);

        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2 ether));      // now unsafe
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2 ether));

        uint auction = liquidationEngine.liquidateSAFE("gold", address(this));
        (,,,,,,, uint256 amountToRaise) = collateralAuctionHouse.bids(auction);
        assertEq(amountToRaise, MAX_LIQUIDATION_QUANTITY / 10 ** 27 * 10 ** 27);
    }
    function testFail_liquidate_forced_over_max_liquidation_quantity() public {
        uint256 MAX_LIQUIDATION_QUANTITY = uint256(-1) / 10 ** 27;
        hevm.store(
            address(liquidationEngine),
            bytes32(uint256(keccak256(abi.encode(bytes32("gold"), uint256(1)))) + 2),
            bytes32(MAX_LIQUIDATION_QUANTITY + 1)
        );

        safeEngine.modifyParameters("globalDebtCeiling", rad(300000 ether));
        safeEngine.modifyParameters("gold", "debtCeiling", rad(300000 ether));
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(205 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(205 ether));
        safeEngine.modifySAFECollateralization("gold", me, me, me, 1000 ether, 200000 ether);

        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2 ether));      // now unsafe
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2 ether));

        uint auction = liquidationEngine.liquidateSAFE("gold", address(this));
        assertEq(auction, 1);
    }
    function test_liquidate_under_liquidation_quantity() public {
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2.5 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2.5 ether));

        safeEngine.modifySAFECollateralization("gold", me, me, me, 40 ether, 100 ether);

        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2 ether));

        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(111 ether));
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1.1 ether);

        uint auction = liquidationEngine.liquidateSAFE("gold", address(this));
        // the full SAFE is liquidated
        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", address(this));
        assertEq(lockedCollateral, 0);
        assertEq(generatedDebt, 0);
        // all debt goes to the accounting engine
        assertEq(accountingEngine.totalQueuedDebt(), rad(100 ether));
        // auction is for all collateral
        (,uint amountToSell,,,,,, uint256 amountToRaise) = collateralAuctionHouse.bids(auction);
        assertEq(amountToSell, 40 ether);
        assertEq(amountToRaise, rad(110 ether));
    }
    function test_liquidate_over_liquidation_quantity() public {
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2.5 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2.5 ether));

        safeEngine.modifySAFECollateralization("gold", me, me, me, 40 ether, 100 ether);

        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2 ether));

        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(82.5 ether));
        liquidationEngine.modifyParameters("gold", "liquidationPenalty", 1.1 ether);

        uint auction = liquidationEngine.liquidateSAFE("gold", address(this));
        // the SAFE is partially liquidated
        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", address(this));
        assertEq(lockedCollateral, 10 ether);
        assertEq(generatedDebt, 25 ether);
        // all debt goes to the accounting engine
        assertEq(accountingEngine.totalQueuedDebt(), rad(75 ether));
        // auction is for all collateral
        (,uint amountToSell,,,,,, uint256 amountToRaise) = collateralAuctionHouse.bids(auction);
        assertEq(amountToSell, 30 ether);
        assertEq(amountToRaise, rad(82.5 ether));
    }
    function test_liquidate_happy_safe() public {
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2.5 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2.5 ether));

        safeEngine.modifySAFECollateralization("gold", me, me, me, 40 ether, 100 ether);

        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2 ether));

        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", address(this));
        assertEq(lockedCollateral, 40 ether);
        assertEq(generatedDebt, 100 ether);
        assertEq(accountingEngine.totalQueuedDebt(), 0);
        assertEq(safeEngine.tokenCollateral("gold", address(this)), 960 ether);

        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(200 ether));  // => liquidate everything
        uint auction = liquidationEngine.liquidateSAFE("gold", address(this));
        (lockedCollateral, generatedDebt) = safeEngine.safes("gold", address(this));
        assertEq(lockedCollateral, 0);
        assertEq(generatedDebt, 0);
        assertEq(accountingEngine.debtQueue(now), rad(100 ether));
        assertEq(safeEngine.tokenCollateral("gold", address(this)), 960 ether);

        assertEq(safeEngine.coinBalance(address(accountingEngine)), 0 ether);
        collateralAuctionHouse.increaseBidSize(auction, 40 ether, rad(1 ether));
        collateralAuctionHouse.increaseBidSize(auction, 40 ether, rad(100 ether));

        assertEq(safeEngine.coinBalance(address(this)), 0 ether);
        assertEq(safeEngine.tokenCollateral("gold", address(this)), 960 ether);

        safeEngine.mint(address(this), 100 ether);  // magic up some system coins for bidding
        collateralAuctionHouse.decreaseSoldAmount(auction, 38 ether, rad(100 ether));
        assertEq(safeEngine.coinBalance(address(accountingEngine)), rad(100 ether));
        assertEq(safeEngine.tokenCollateral("gold", address(this)), 962 ether);
        assertEq(accountingEngine.debtQueue(now), rad(100 ether));

        hevm.warp(now + 4 hours);
        collateralAuctionHouse.settleAuction(auction);
        assertEq(safeEngine.coinBalance(address(accountingEngine)), rad(100 ether));
    }
    function test_liquidate_when_system_deficit() public {
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2.5 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2.5 ether));

        safeEngine.modifySAFECollateralization("gold", me, me, me, 40 ether, 100 ether);

        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2 ether));

        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(200 ether));  // => liquidate everything
        assertEq(accountingEngine.debtQueue(now), rad(0 ether));
        uint auction = liquidationEngine.liquidateSAFE("gold", address(this));
        assertEq(accountingEngine.debtQueue(now), rad(100 ether));

        assertEq(accountingEngine.totalQueuedDebt(), rad(100 ether));
        accountingEngine.popDebtFromQueue(now);
        assertEq(accountingEngine.totalQueuedDebt(), rad(  0 ether));
        assertEq(accountingEngine.unqueuedUnauctionedDebt(), rad(100 ether));
        assertEq(accountingEngine.totalSurplus(), rad(  0 ether));
        assertEq(accountingEngine.totalOnAuctionDebt(), rad(  0 ether));

        accountingEngine.modifyParameters("debtAuctionBidSize", rad(10 ether));
        accountingEngine.modifyParameters("initialDebtAuctionMintedTokens", 2000 ether);
        uint f1 = accountingEngine.auctionDebt();
        assertEq(accountingEngine.unqueuedUnauctionedDebt(),  rad(90 ether));
        assertEq(accountingEngine.totalSurplus(),  rad( 0 ether));
        assertEq(accountingEngine.totalOnAuctionDebt(),  rad(10 ether));
        debtAuctionHouse.decreaseSoldAmount(f1, 1000 ether, rad(10 ether));
        assertEq(accountingEngine.unqueuedUnauctionedDebt(), rad(90 ether));
        assertEq(accountingEngine.totalSurplus(),  rad( 0 ether));
        assertEq(accountingEngine.totalOnAuctionDebt(), rad( 0 ether));

        assertEq(protocolToken.balanceOf(address(this)),  100 ether);
        hevm.warp(now + 4 hours);
        protocolToken.setOwner(address(debtAuctionHouse));
        debtAuctionHouse.settleAuction(f1);
        assertEq(protocolToken.balanceOf(address(this)), 1100 ether);
    }
    function test_liquidate_when_system_surplus() public {
        // get some surplus
        safeEngine.mint(address(accountingEngine), 100 ether);
        assertEq(safeEngine.coinBalance(address(accountingEngine)), rad(100 ether));
        assertEq(protocolToken.balanceOf(address(this)), 100 ether);

        accountingEngine.modifyParameters("surplusAuctionAmountToSell", rad(100 ether));
        assertEq(accountingEngine.unqueuedUnauctionedDebt(), 0 ether);
        assertEq(accountingEngine.totalOnAuctionDebt(), 0 ether);
        uint id = accountingEngine.auctionSurplus();

        assertEq(safeEngine.coinBalance(address(this)),  0 ether);
        assertEq(protocolToken.balanceOf(address(this)), 100 ether);
        surplusAuctionHouse.increaseBidSize(id, rad(100 ether), 10 ether);
        hevm.warp(now + 4 hours);
        protocolToken.setOwner(address(surplusAuctionHouse));
        surplusAuctionHouse.settleAuction(id);
        assertEq(safeEngine.coinBalance(address(this)), rad(100 ether));
        assertEq(protocolToken.balanceOf(address(this)), 90 ether);
    }
    // tests a partial liquidation because it would fill the onAuctionSystemCoinLimit
    function test_partial_liquidation_fill_limit() public {
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2.5 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2.5 ether));

        safeEngine.modifySAFECollateralization("gold", me, me, me, 100 ether, 150 ether);

        safeEngine.modifyParameters("gold", 'safetyPrice', ray(1 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(1 ether));

        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", address(this));
        assertEq(lockedCollateral, 100 ether);
        assertEq(generatedDebt, 150 ether);
        assertEq(accountingEngine.unqueuedUnauctionedDebt(), 0 ether);
        assertEq(accountingEngine.totalOnAuctionDebt(), 0 ether);
        assertEq(safeEngine.tokenCollateral("gold", address(this)), 900 ether);

        liquidationEngine.modifyParameters("onAuctionSystemCoinLimit", rad(75 ether));
        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(100 ether));
        assertEq(liquidationEngine.onAuctionSystemCoinLimit(), rad(75 ether));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 0);
        uint auction = liquidationEngine.liquidateSAFE("gold", address(this));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(75 ether));
        (lockedCollateral, generatedDebt) = safeEngine.safes("gold", address(this));
        assertEq(lockedCollateral, 50 ether);
        assertEq(generatedDebt, 75 ether);
        assertEq(accountingEngine.debtQueue(now), rad(75 ether));
        assertEq(safeEngine.tokenCollateral("gold", address(this)), 900 ether);

        assertEq(safeEngine.coinBalance(address(this)), rad(150 ether));
        assertEq(safeEngine.coinBalance(address(accountingEngine)), 0 ether);
        collateralAuctionHouse.increaseBidSize(auction, 50 ether, rad( 1 ether));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(75 ether));
        assertEq(safeEngine.coinBalance(address(this)), rad(149 ether));
        collateralAuctionHouse.increaseBidSize(auction, 50 ether, rad(75 ether));
        assertEq(safeEngine.coinBalance(address(this)), rad(75 ether));

        assertEq(safeEngine.tokenCollateral("gold", address(this)),  900 ether);
        collateralAuctionHouse.decreaseSoldAmount(auction, 25 ether, rad(75 ether));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(75 ether));
        assertEq(safeEngine.coinBalance(address(this)), rad(75 ether));
        assertEq(safeEngine.tokenCollateral("gold", address(this)), 925 ether);
        assertEq(accountingEngine.debtQueue(now), rad(75 ether));

        hevm.warp(now + 4 hours);
        collateralAuctionHouse.settleAuction(auction);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 0);
        assertEq(safeEngine.tokenCollateral("gold", address(this)),  950 ether);
        assertEq(safeEngine.coinBalance(address(this)), rad(75 ether));
        assertEq(safeEngine.coinBalance(address(accountingEngine)),  rad(75 ether));
    }
    function testFail_liquidate_fill_over_limit() public {
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2.5 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2.5 ether));

        safeEngine.modifySAFECollateralization("gold", me, me, me, 100 ether, 150 ether);

        safeEngine.modifyParameters("gold", 'safetyPrice', ray(1 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(1 ether));

        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", address(this));
        assertEq(lockedCollateral, 100 ether);
        assertEq(generatedDebt, 150 ether);
        assertEq(accountingEngine.unqueuedUnauctionedDebt(), 0 ether);
        assertEq(safeEngine.tokenCollateral("gold", address(this)), 900 ether);

        liquidationEngine.modifyParameters("onAuctionSystemCoinLimit", rad(75 ether));
        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(100 ether));
        assertEq(liquidationEngine.onAuctionSystemCoinLimit(), rad(75 ether));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 0);
        liquidationEngine.liquidateSAFE("gold", address(this));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(75 ether));

        (lockedCollateral, generatedDebt) = safeEngine.safes("gold", address(this));
        assertEq(lockedCollateral, 50 ether);
        assertEq(generatedDebt, 75 ether);
        assertEq(accountingEngine.debtQueue(now), rad(75 ether));
        assertEq(safeEngine.tokenCollateral("gold", address(this)), 900 ether);

        liquidationEngine.liquidateSAFE("gold", address(this));
    }

    function test_multiple_liquidations_partial_fill_limit() public {
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2.5 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2.5 ether));

        safeEngine.modifySAFECollateralization("gold", me, me, me, 100 ether, 150 ether);

        safeEngine.modifyParameters("gold", 'safetyPrice', ray(1 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(1 ether));

        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", address(this));
        assertEq(lockedCollateral, 100 ether);
        assertEq(generatedDebt, 150 ether);
        assertEq(accountingEngine.unqueuedUnauctionedDebt(), 0 ether);
        assertEq(safeEngine.tokenCollateral("gold", address(this)), 900 ether);

        liquidationEngine.modifyParameters("onAuctionSystemCoinLimit", rad(75 ether));
        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(100 ether));
        assertEq(liquidationEngine.onAuctionSystemCoinLimit(), rad(75 ether));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 0);
        uint auction = liquidationEngine.liquidateSAFE("gold", address(this));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(75 ether));

        (lockedCollateral, generatedDebt) = safeEngine.safes("gold", address(this));
        assertEq(lockedCollateral, 50 ether);
        assertEq(generatedDebt, 75 ether);
        assertEq(accountingEngine.debtQueue(now), rad(75 ether));
        assertEq(safeEngine.tokenCollateral("gold", address(this)), 900 ether);

        assertEq(safeEngine.coinBalance(address(this)), rad(150 ether));
        assertEq(safeEngine.coinBalance(address(accountingEngine)), 0 ether);
        collateralAuctionHouse.increaseBidSize(auction, 50 ether, rad( 1 ether));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(75 ether));
        assertEq(safeEngine.coinBalance(address(this)), rad(149 ether));
        collateralAuctionHouse.increaseBidSize(auction, 50 ether, rad(75 ether));
        assertEq(safeEngine.coinBalance(address(this)), rad(75 ether));

        assertEq(safeEngine.tokenCollateral("gold", address(this)),  900 ether);
        collateralAuctionHouse.decreaseSoldAmount(auction, 25 ether, rad(75 ether));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(75 ether));
        assertEq(safeEngine.coinBalance(address(this)), rad(75 ether));
        assertEq(safeEngine.tokenCollateral("gold", address(this)), 925 ether);
        assertEq(accountingEngine.debtQueue(now), rad(75 ether));

        // Another liquidateSAFE() here would fail and revert because we would go above the limit so we first
        // have to settle an auction and then liquidate again

        hevm.warp(now + 4 hours);
        collateralAuctionHouse.settleAuction(auction);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 0);
        assertEq(safeEngine.tokenCollateral("gold", address(this)),  950 ether);
        assertEq(safeEngine.coinBalance(address(this)), rad(75 ether));
        assertEq(safeEngine.coinBalance(address(accountingEngine)), rad(75 ether));

        // now liquidate more
        auction = liquidationEngine.liquidateSAFE("gold", address(this));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(75 ether));

        (lockedCollateral, generatedDebt) = safeEngine.safes("gold", address(this));
        assertEq(lockedCollateral, 0);
        assertEq(generatedDebt, 0);
        assertEq(accountingEngine.debtQueue(now), rad(75 ether));
        assertEq(safeEngine.tokenCollateral("gold", address(this)), 950 ether);

        assertEq(safeEngine.coinBalance(address(this)), rad(75 ether));
        assertEq(safeEngine.coinBalance(address(accountingEngine)), rad(75 ether));
        collateralAuctionHouse.increaseBidSize(auction, 50 ether, rad( 1 ether));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(75 ether));
        assertEq(safeEngine.coinBalance(address(this)), rad(74 ether));
        collateralAuctionHouse.increaseBidSize(auction, 50 ether, rad(75 ether));
        assertEq(safeEngine.coinBalance(address(this)), 0);

        assertEq(safeEngine.tokenCollateral("gold", address(this)),  950 ether);
        collateralAuctionHouse.decreaseSoldAmount(auction, 25 ether, rad(75 ether));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(75 ether));
        assertEq(safeEngine.coinBalance(address(this)), 0);
        assertEq(safeEngine.tokenCollateral("gold", address(this)), 975 ether);
        assertEq(accountingEngine.debtQueue(now), rad(75 ether));

        hevm.warp(now + 4 hours);
        collateralAuctionHouse.settleAuction(auction);
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 0);
        assertEq(safeEngine.tokenCollateral("gold", address(this)),  1000 ether);
        assertEq(safeEngine.coinBalance(address(this)), 0);
        assertEq(safeEngine.coinBalance(address(accountingEngine)), rad(150 ether));
    }

    function testFail_liquidation_quantity_small_leaves_dust() public {
        safeEngine.modifyParameters("gold", 'debtFloor', rad(150 ether));
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2.5 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2.5 ether));

        safeEngine.modifySAFECollateralization("gold", me, me, me, 100 ether, 150 ether);

        safeEngine.modifyParameters("gold", 'safetyPrice', ray(1 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(1 ether));

        liquidationEngine.modifyParameters("onAuctionSystemCoinLimit", rad(150 ether));
        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(1 ether));

        assertEq(liquidationEngine.onAuctionSystemCoinLimit(), rad(150 ether));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 0);

        assertEq(liquidationEngine.getLimitAdjustedDebtToCover("gold", address(this)), 1 ether);

        liquidationEngine.liquidateSAFE("gold", address(this));
    }

    function testFail_liquidation_remaining_on_auction_limit_results_in_dust() public {
        safeEngine.modifyParameters("gold", 'debtFloor', rad(150 ether));
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2.5 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2.5 ether));

        safeEngine.modifySAFECollateralization("gold", me, me, me, 100 ether, 150 ether);

        safeEngine.modifyParameters("gold", 'safetyPrice', ray(1 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(1 ether));

        liquidationEngine.modifyParameters("onAuctionSystemCoinLimit", rad(149 ether));
        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(150 ether));

        assertEq(liquidationEngine.onAuctionSystemCoinLimit(), rad(149 ether));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 0);

        assertEq(liquidationEngine.getLimitAdjustedDebtToCover("gold", address(this)), 149 ether);

        liquidationEngine.liquidateSAFE("gold", address(this));
    }

    function test_liquidation_remaining_on_auction_limit_right_above_safe_debt() public {
        safeEngine.modifyParameters("gold", 'debtFloor', rad(149 ether));
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2.5 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2.5 ether));

        safeEngine.modifySAFECollateralization("gold", me, me, me, 100 ether, 150 ether);

        safeEngine.modifyParameters("gold", 'safetyPrice', ray(1 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(1 ether));

        liquidationEngine.modifyParameters("onAuctionSystemCoinLimit", rad(150 ether));
        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(1 ether));

        assertEq(liquidationEngine.onAuctionSystemCoinLimit(), rad(150 ether));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 0);

        assertEq(liquidationEngine.getLimitAdjustedDebtToCover("gold", address(this)), 1 ether);

        liquidationEngine.liquidateSAFE("gold", address(this));

        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", address(this));
        assertEq(lockedCollateral, 99333333333333333334);
        assertEq(generatedDebt, 149 ether);
    }

    function test_double_liquidate_safe() public {
        safeEngine.modifyParameters("gold", 'debtFloor', rad(149 ether));
        safeEngine.modifyParameters("gold", 'safetyPrice', ray(2.5 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(2.5 ether));

        safeEngine.modifySAFECollateralization("gold", me, me, me, 100 ether, 150 ether);

        safeEngine.modifyParameters("gold", 'safetyPrice', ray(1 ether));
        safeEngine.modifyParameters("gold", 'liquidationPrice', ray(1 ether));

        liquidationEngine.modifyParameters("onAuctionSystemCoinLimit", rad(150 ether));
        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(1 ether));

        assertEq(liquidationEngine.onAuctionSystemCoinLimit(), rad(150 ether));
        assertEq(liquidationEngine.currentOnAuctionSystemCoins(), 0);

        assertEq(liquidationEngine.getLimitAdjustedDebtToCover("gold", address(this)), 1 ether);

        liquidationEngine.liquidateSAFE("gold", address(this));

        liquidationEngine.modifyParameters("onAuctionSystemCoinLimit", uint(-1));
        liquidationEngine.modifyParameters("gold", "liquidationQuantity", rad(1000 ether));

        assertEq(liquidationEngine.getLimitAdjustedDebtToCover("gold", address(this)), 149 ether);

        liquidationEngine.liquidateSAFE("gold", address(this));

        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", address(this));
        assertEq(lockedCollateral, 0);
        assertEq(generatedDebt, 0);
    }
}

contract AccumulateRatesTest is DSTest {
    SAFEEngine safeEngine;

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }
    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }
    function totalAdjustedDebt(bytes32 collateralType, address safe) internal view returns (uint) {
        (, uint generatedDebt_) =
          safeEngine.safes(collateralType, safe);
        (, uint accumulatedRate_, , , , ) =
          safeEngine.collateralTypes(collateralType);
        return generatedDebt_ * accumulatedRate_;
    }

    function setUp() public {
        safeEngine = new SAFEEngine();
        safeEngine.initializeCollateralType("gold");
        safeEngine.modifyParameters("globalDebtCeiling", rad(100 ether));
        safeEngine.modifyParameters("gold", "debtCeiling", rad(100 ether));
    }
    function generateDebt(bytes32 collateralType, uint coin) internal {
        safeEngine.modifyParameters("globalDebtCeiling", rad(coin));
        safeEngine.modifyParameters(collateralType, "debtCeiling", rad(coin));
        safeEngine.modifyParameters(collateralType, "safetyPrice", 10 ** 27 * 10000 ether);
        address self = address(this);
        safeEngine.modifyCollateralBalance(collateralType, self,  10 ** 27 * 1 ether);
        safeEngine.modifySAFECollateralization(collateralType, self, self, self, 1 ether, int(coin));
    }
    function test_accumulate_rates() public {
        address self = address(this);
        address ali  = address(bytes20("ali"));
        generateDebt("gold", 1 ether);

        assertEq(totalAdjustedDebt("gold", self), rad(1.00 ether));
        safeEngine.updateAccumulatedRate("gold", ali, int(ray(0.05 ether)));
        assertEq(totalAdjustedDebt("gold", self), rad(1.05 ether));
        assertEq(safeEngine.coinBalance(ali), rad(0.05 ether));
    }
}
