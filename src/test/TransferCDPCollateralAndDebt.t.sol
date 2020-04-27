pragma solidity ^0.5.15;

import "ds-test/test.sol";
import "ds-token/token.sol";

import {CDPEngine} from '../CDPEngine.sol';

contract Usr {
    CDPEngine public cdpEngine;
    constructor(CDPEngine cdpEngine_) public {
        cdpEngine = cdpEngine_;
    }
    function try_call(address addr, bytes calldata data) external returns (bool) {
        bytes memory _data = data;
        assembly {
            let ok := call(gas, addr, 0, add(_data, 0x20), mload(_data), 0, 0)
            let free := mload(0x40)
            mstore(free, ok)
            mstore(0x40, add(free, 32))
            revert(free, 32)
        }
    }
    function can_modifyCDPCollateralization(
      bytes32 collateralType,
      address cdp,
      address collateralSource,
      address debtDestination,
      int deltaCollateral,
      int deltaDebt
    ) public returns (bool) {
        string memory sig = "modifyCDPCollateralization(bytes32,address,address,address,int256,int256)";
        bytes memory data = abi.encodeWithSignature(
          sig, address(this), collateralType, cdp, collateralSource, debtDestination, deltaCollateral, deltaDebt
        );

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", cdpEngine, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function can_transferCDPCollateralAndDebt(
      bytes32 collateralType,
      address src,
      address dst,
      int deltaCollateral,
      int deltaDebt
    ) public returns (bool) {
        string memory sig = "transferCDPCollateralAndDebt(bytes32,address,address,int256,int256)";
        bytes memory data = abi.encodeWithSignature(sig, collateralType, src, dst, deltaCollateral, deltaDebt);

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", cdpEngine, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function modifyCDPCollateralization(
      bytes32 collateralType,
      address cdp,
      address collateralSource,
      address debtDestination,
      int deltaCollateral,
      int deltaDebt
    ) public {
        cdpEngine.modifyCDPCollateralization(
          collateralType, cdp, collateralSource, debtDestination, deltaCollateral, deltaDebt
        );
    }
    function transferCDPCollateralAndDebt(
      bytes32 collateralType, address src, address dst, int deltaCollateral, int deltaDebt
    ) public {
        cdpEngine.transferCDPCollateralAndDebt(collateralType, src, dst, deltaCollateral, deltaDebt);
    }
    function approveCDPModification(address usr) public {
        cdpEngine.approveCDPModification(usr);
    }
    function pass() public {}
}

contract TransferCDPCollateralAndDebtTest is DSTest {
    CDPEngine cdpEngine;
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
        cdpEngine = new CDPEngine();
        ali = new Usr(cdpEngine);
        bob = new Usr(cdpEngine);
        a = address(ali);
        b = address(bob);

        cdpEngine.initializeCollateralType("gems");
        cdpEngine.modifyParameters("gems", "safetyPrice", ray(0.5  ether));
        cdpEngine.modifyParameters("gems", "debtCeiling", rad(1000 ether));
        cdpEngine.modifyParameters("globalDebtCeiling", rad(1000 ether));

        cdpEngine.addAuthorization(a);
        cdpEngine.addAuthorization(b);

        cdpEngine.modifyCollateralBalance("gems", a, 80 ether);
    }
    function test_transferCollateralAndDebt_to_self() public {
        ali.modifyCDPCollateralization("gems", a, a, a, 8 ether, 4 ether);
        assertTrue( ali.can_transferCDPCollateralAndDebt("gems", a, a, 8 ether, 4 ether));
        assertTrue( ali.can_transferCDPCollateralAndDebt("gems", a, a, 4 ether, 2 ether));
        assertTrue(!ali.can_transferCDPCollateralAndDebt("gems", a, a, 9 ether, 4 ether));
    }
    function test_transferCollateralAndDebt_to_other() public {
        ali.modifyCDPCollateralization("gems", a, a, a, 8 ether, 4 ether);
        assertTrue(!ali.can_transferCDPCollateralAndDebt("gems", a, b, 8 ether, 4 ether));
        bob.approveCDPModification(address(ali));
        assertTrue( ali.can_transferCDPCollateralAndDebt("gems", a, b, 8 ether, 4 ether));
    }
    function test_give_to_other() public {
        ali.modifyCDPCollateralization("gems", a, a, a, 8 ether, 4 ether);
        bob.approveCDPModification(address(ali));
        assertTrue( ali.can_transferCDPCollateralAndDebt("gems", a, b, 4 ether, 2 ether));
        assertTrue(!ali.can_transferCDPCollateralAndDebt("gems", a, b, 4 ether, 3 ether));
        assertTrue(!ali.can_transferCDPCollateralAndDebt("gems", a, b, 4 ether, 1 ether));
    }
    function test_transferCollateralAndDebt_dust() public {
        ali.modifyCDPCollateralization("gems", a, a, a, 8 ether, 4 ether);
        bob.approveCDPModification(address(ali));
        assertTrue( ali.can_transferCDPCollateralAndDebt("gems", a, b, 4 ether, 2 ether));
        cdpEngine.modifyParameters("gems", "debtFloor", rad(1 ether));
        assertTrue( ali.can_transferCDPCollateralAndDebt("gems", a, b, 2 ether, 1 ether));
        assertTrue(!ali.can_transferCDPCollateralAndDebt("gems", a, b, 1 ether, 0.5 ether));
    }
}
