pragma solidity 0.6.7;

import "ds-test/test.sol";

import {SAFEEngine} from '../SAFEEngine.sol';

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
          sig, address(this), collateralType, safe, collateralSource, debtDestination, deltaCollateral, deltaDebt
        );

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", safeEngine, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function can_transferSAFECollateralAndDebt(
      bytes32 collateralType,
      address src,
      address dst,
      int deltaCollateral,
      int deltaDebt
    ) public returns (bool) {
        string memory sig = "transferSAFECollateralAndDebt(bytes32,address,address,int256,int256)";
        bytes memory data = abi.encodeWithSignature(sig, collateralType, src, dst, deltaCollateral, deltaDebt);

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", safeEngine, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function modifySAFECollateralization(
      bytes32 collateralType,
      address safe,
      address collateralSource,
      address debtDestination,
      int deltaCollateral,
      int deltaDebt
    ) public {
        safeEngine.modifySAFECollateralization(
          collateralType, safe, collateralSource, debtDestination, deltaCollateral, deltaDebt
        );
    }
    function transferSAFECollateralAndDebt(
      bytes32 collateralType, address src, address dst, int deltaCollateral, int deltaDebt
    ) public {
        safeEngine.transferSAFECollateralAndDebt(collateralType, src, dst, deltaCollateral, deltaDebt);
    }
    function approveSAFEModification(address usr) public {
        safeEngine.approveSAFEModification(usr);
    }
    function pass() public {}
}

contract TransferSAFECollateralAndDebtTest is DSTest {
    SAFEEngine safeEngine;
    Usr ali;
    Usr bob;
    address a;
    address b;

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }
    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }

    function setUp() public {
        safeEngine = new SAFEEngine();
        ali = new Usr(safeEngine);
        bob = new Usr(safeEngine);
        a = address(ali);
        b = address(bob);

        safeEngine.initializeCollateralType("collateralTokens");
        safeEngine.modifyParameters("collateralTokens", "safetyPrice", ray(0.5  ether));
        safeEngine.modifyParameters("collateralTokens", "debtCeiling", rad(1000 ether));
        safeEngine.modifyParameters("globalDebtCeiling", rad(1000 ether));

        safeEngine.addAuthorization(a);
        safeEngine.addAuthorization(b);

        safeEngine.modifyCollateralBalance("collateralTokens", a, 80 ether);
    }
    function test_transferCollateralAndDebt_to_self() public {
        ali.modifySAFECollateralization("collateralTokens", a, a, a, 8 ether, 4 ether);
        assertTrue( ali.can_transferSAFECollateralAndDebt("collateralTokens", a, a, 8 ether, 4 ether));
        assertTrue( ali.can_transferSAFECollateralAndDebt("collateralTokens", a, a, 4 ether, 2 ether));
        assertTrue(!ali.can_transferSAFECollateralAndDebt("collateralTokens", a, a, 9 ether, 4 ether));
    }
    function test_transferCollateralAndDebt_to_other() public {
        ali.modifySAFECollateralization("collateralTokens", a, a, a, 8 ether, 4 ether);
        assertTrue(!ali.can_transferSAFECollateralAndDebt("collateralTokens", a, b, 8 ether, 4 ether));
        bob.approveSAFEModification(address(ali));
        assertTrue( ali.can_transferSAFECollateralAndDebt("collateralTokens", a, b, 8 ether, 4 ether));
    }
    function test_give_to_other() public {
        ali.modifySAFECollateralization("collateralTokens", a, a, a, 8 ether, 4 ether);
        bob.approveSAFEModification(address(ali));
        assertTrue( ali.can_transferSAFECollateralAndDebt("collateralTokens", a, b, 4 ether, 2 ether));
        assertTrue(!ali.can_transferSAFECollateralAndDebt("collateralTokens", a, b, 4 ether, 3 ether));
        assertTrue(!ali.can_transferSAFECollateralAndDebt("collateralTokens", a, b, 4 ether, 1 ether));
    }
    function test_transferCollateralAndDebt_dust() public {
        ali.modifySAFECollateralization("collateralTokens", a, a, a, 8 ether, 4 ether);
        bob.approveSAFEModification(address(ali));
        assertTrue( ali.can_transferSAFECollateralAndDebt("collateralTokens", a, b, 4 ether, 2 ether));
        safeEngine.modifyParameters("collateralTokens", "debtFloor", rad(1 ether));
        assertTrue( ali.can_transferSAFECollateralAndDebt("collateralTokens", a, b, 2 ether, 1 ether));
        assertTrue(!ali.can_transferSAFECollateralAndDebt("collateralTokens", a, b, 1 ether, 0.5 ether));
    }
}
