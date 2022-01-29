pragma solidity ^0.6.7;

import "./SAFEEngineMock.sol";
import "../../single/SAFEEngine.sol";
import "./DelegateTOkenMock.sol";
import "../../../lib/ds-token/lib/ds-test/src/test.sol";
import '../../shared/BasicTokenAdapters.sol';
import {TaxCollector} from '../../single/TaxCollector.sol';

// @notice Fuzz the whole thing, failures will show bounds (run with checkAsserts: on)
contract FuzzBounds is SAFEEngineMock {
    constructor() public SAFEEngineMock() {}

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

contract Usr {
    TestSAFEEngine public safeEngine;
    constructor(TestSAFEEngine safeEngine_) public {
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

    function transferCollateral(bytes32 collateralType, address src, address dst, uint256 wad) public {
        safeEngine.transferCollateral(collateralType, src, dst, wad);
    }

function transferInternalCoins(address src, address dst, uint256 wad) public {
        safeEngine.transferInternalCoins(src, dst, wad);
    }
}

// @notice Will create/modify safes for each of the callers, check for invatiants (fuzz with checkAsserts: off)
contract FuzzSafes is DSTest {
    TestSAFEEngine safeEngine;
    DSDelegateToken gold;
    DSDelegateToken stable;
    TaxCollector taxCollector;
    BasicCollateralJoin collateralA;
    CoinJoin coinA;
    DSDelegateToken coin;

    mapping (address => Usr) users;
    mapping (address => bool) isUser;
    address[] userAddresses;
    uint collateralTransferred;

    uint constant RAY = 10 ** 27;

    constructor() public {
        setUp();
    }
    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }

    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }

    function setUp() public {
        safeEngine = new TestSAFEEngine();

        gold = new DSDelegateToken("GEM", '');
        gold.mint(1000 ether);

        safeEngine.initializeCollateralType("gold");

        collateralA = new BasicCollateralJoin(address(safeEngine), "gold", address(gold));

        safeEngine.modifyParameters("gold", "safetyPrice",    ray(1 ether));
        safeEngine.modifyParameters("gold", "debtCeiling", rad(1000 ether));
        safeEngine.modifyParameters("gold", "debtFloor", rad(100 ether));
        safeEngine.modifyParameters("globalDebtCeiling", rad(1000 ether));

        taxCollector = new TaxCollector(address(safeEngine));
        taxCollector.initializeCollateralType("gold");
        safeEngine.addAuthorization(address(taxCollector));

        gold.approve(address(collateralA));

        safeEngine.addAuthorization(address(safeEngine));
        safeEngine.addAuthorization(address(collateralA));

        coin  = new DSDelegateToken("Coin", 'Coin');
        coinA = new CoinJoin(address(safeEngine), address(coin));
        safeEngine.addAuthorization(address(coinA));
        coin.setOwner(address(coinA));
    }

    // test with dapp tools
    function test_fuzz_setup() public {
        this.join(address(collateralA), 1000 ether);
        assertEq(safeEngine.tokenCollateral("gold", address(users[address(this)])), 1000 ether);

        this.exit(address(collateralA), 1 ether);
        assertEq(safeEngine.tokenCollateral("gold", address(users[address(this)])), 999 ether);

        this.transferCollateral(address(0xabc), 1 ether);
        assertEq(safeEngine.tokenCollateral("gold", address(0xabc)), 1 ether);
        assertEq(safeEngine.tokenCollateral("gold", address(users[address(this)])), 998 ether);

        // add collateral to safe
        this.modifySAFECollateralization(int256(998 ether), int256(0));
        assertEq(safeEngine.tokenCollateral("gold", address(users[address(this)])), 0);
        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", address(users[address(this)]));
        assertEq(lockedCollateral, 998 ether);
        assertEq(generatedDebt, 0);

        // generate debt
        this.modifySAFECollateralization(int256(0), int256(500 ether));
        assertEq(safeEngine.tokenCollateral("gold", address(users[address(this)])), 0);
        (lockedCollateral, generatedDebt) = safeEngine.safes("gold", address(users[address(this)]));
        assertEq(lockedCollateral, 998 ether);
        assertEq(generatedDebt, 500 ether);
        assertEq(safeEngine.coinBalance(address(users[address(this)])), rad(500 ether));

        // transfer internal coins
        this.transferInternalCoins(address(0x1), rad(5 ether));
        assertEq(safeEngine.coinBalance(address(users[address(this)])), rad(495 ether));
        assertEq(safeEngine.coinBalance(address(0x1)), rad(5 ether));

        // exit coins
        this.exit(address(coinA), 10 ether);
        assertEq(safeEngine.coinBalance(address(users[address(this)])), rad(485 ether));
        assertEq(coin.balanceOf(address(users[address(this)])), 10 ether);

        // join coins
        this.join(address(coinA), 5 ether);
        assertEq(safeEngine.coinBalance(address(users[address(this)])), rad(490 ether));
        assertEq(coin.balanceOf(address(users[address(this)])), 5 ether);
    }

    // modifier that creates users for callers (setup no. of callers in echidna.yaml)
    modifier createUser {
        if (address(users[msg.sender]) == address(0)) {
            users[msg.sender] = new Usr(safeEngine);
            users[msg.sender].approveSAFEModification(address(coinA));
            userAddresses.push(address(users[msg.sender]));
            isUser[address(users[msg.sender])] = true;
        }
        _;
    }

    // test with checkassets == true to enable assertions here to be flagged
    // with checkassers ==false these will still be called, but just the invariants below will be tested.
    function join(address join, uint amount) public createUser {
        if (join == address(collateralA)) gold.mint(address(users[msg.sender]), amount);
        users[msg.sender].approve(address(gold), address(collateralA), uint(-1));
        users[msg.sender].approve(address(coin), address(coinA), uint(-1));
        users[msg.sender].join(join, address(users[msg.sender]), amount);
    }

    function exit(address join, uint amount) public createUser {
        users[msg.sender].exit(join, address(users[msg.sender]), amount);
    }

    function transferCollateral(address dst, uint256 wad) public returns (bool) {
        uint previousUserBalance = safeEngine.tokenCollateral("gold", address(users[msg.sender]));
        uint previousDstBalance  = safeEngine.tokenCollateral("gold", dst);

        users[msg.sender].transferCollateral("gold", address(users[msg.sender]), dst, wad);
        if (! isUser[dst]) collateralTransferred += wad;

        if (address(users[msg.sender]) == dst) assert (safeEngine.tokenCollateral("gold", dst) == previousUserBalance);
        else {
            assert(safeEngine.tokenCollateral("gold", address(users[msg.sender])) == previousUserBalance - wad);
            assert(safeEngine.tokenCollateral("gold", dst) == previousDstBalance + wad);
        }
    }

    function transferInternalCoins(address dst, uint256 wad) public returns (bool) {
        uint previousUserBalance = safeEngine.coinBalance(address(users[msg.sender]));
        uint previousDstBalance  = safeEngine.coinBalance(dst);

        users[msg.sender].transferInternalCoins(address(users[msg.sender]), dst, wad);

        if (address(users[msg.sender]) == dst) assert (safeEngine.coinBalance(dst) == previousUserBalance);
        else {
            assert(safeEngine.coinBalance(address(users[msg.sender])) == previousUserBalance - wad);
            assert(safeEngine.coinBalance(dst) == previousDstBalance + wad);
        }
    }

    function modifySAFECollateralization(int256 deltaCollateral, int256 deltaDebt) public returns (bool) {
        (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", address(users[msg.sender]));

        users[msg.sender].modifySAFECollateralization(
            "gold",
            address(users[msg.sender]),
            address(users[msg.sender]),
            address(users[msg.sender]),
            deltaCollateral,
            deltaDebt
            );

        (uint newLockedCollateral, uint newGeneratedDebt) = safeEngine.safes("gold", address(users[msg.sender]));
        assert(newLockedCollateral == (deltaCollateral > 0 ? lockedCollateral + uint(deltaCollateral) : lockedCollateral - uint(deltaCollateral)));
        assert(newGeneratedDebt == (deltaDebt > 0 ? generatedDebt + uint(deltaDebt) : generatedDebt - uint(deltaDebt)));
    }

    // properties
    // collateral debt amount == sum of all debts
    function echidna_collateral_debt_vs_safes() public returns (bool) {
        uint totalDebt;
        for (uint i = 0; i < userAddresses.length; i++) {
            (, uint generatedDebt) = safeEngine.safes("gold", userAddresses[i]);
            totalDebt += generatedDebt;
        }
        (uint goldDebtAmount,,,,,) = safeEngine.collateralTypes("gold");
        return goldDebtAmount == totalDebt;
    }

    // collateral debt amount == global debt amount (testing just one collateral)
    function echidna_collateral_and_global_debt_match() public returns (bool) {
        (uint goldDebtAmount,,,,,) = safeEngine.collateralTypes("gold");
        return rad(goldDebtAmount) == safeEngine.globalDebt();
    }

    // debt amount <= debt ceiling
    function echidna_collateral_debt_ceiling() public returns (bool) {
        (uint goldDebtAmount,,, uint debtCeiling,,) = safeEngine.collateralTypes("gold");
        return goldDebtAmount <= debtCeiling;
    }

    // global debt amount < global debt ceiling
    function echidna_global_debt_ceiling() public returns (bool) {
        return safeEngine.globalDebt() <= safeEngine.globalDebtCeiling();
    }

    // safe debt >= debt floor
    function echidna_safe_debt_floor() public returns (bool) {
        (,,,, uint debtFloor,) = safeEngine.collateralTypes("gold");
        for (uint i = 0; i < userAddresses.length; i++) {
            (, uint generatedDebt) = safeEngine.safes("gold", userAddresses[i]);
            if (rad(generatedDebt) < debtFloor && generatedDebt != 0) return false;
        }
        return true;
    }

    // sum of all collateral / safe collateral is same as deposited in Join
    function echidna_join_collateral_balance() public returns (bool) {
        uint totalCollateral;
        for (uint i = 0; i < userAddresses.length; i++) {
            (uint lockedCollateral, uint generatedDebt) = safeEngine.safes("gold", userAddresses[i]);
            totalCollateral += lockedCollateral;
            totalCollateral += safeEngine.tokenCollateral("gold", userAddresses[i]);
        }

        totalCollateral += collateralTransferred;

        return totalCollateral == gold.balanceOf(address(collateralA));
    }

    // totalSupply of coin matches it's balance in safeEngine
    function echidna_coin_internal_balance() public returns (bool) {
        return coin.totalSupply() == safeEngine.coinBalance(address(coinA)) / RAY;
    }

    // unbacked debt == 0 (not creating it with this script)
    function echidna_unbacked_debt() public returns (bool) {
        return safeEngine.globalUnbackedDebt() == 0;
    }
}