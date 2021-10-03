// pragma solidity 0.6.7;
//
// import "ds-test/test.sol";
//
// import {MultiSAFEEngine} from '../../multi/MultiSAFEEngine.sol';
//
// contract Usr {
//     MultiSAFEEngine public safeEngine;
//     constructor(MultiSAFEEngine safeEngine_) public {
//         safeEngine = safeEngine_;
//     }
//     function try_call(address addr, bytes calldata data) external returns (bool) {
//         bytes memory _data = data;
//         assembly {
//             let ok := call(gas(), addr, 0, add(_data, 0x20), mload(_data), 0, 0)
//             let free := mload(0x40)
//             mstore(free, ok)
//             mstore(0x40, add(free, 32))
//             revert(free, 32)
//         }
//     }
//     function can_modifySAFECollateralization(
//       bytes32 coinName,
//       bytes32 collateralType,
//       address safe,
//       address collateralSource,
//       address debtDestination,
//       int deltaCollateral,
//       int deltaDebt
//     ) public returns (bool) {
//         string memory sig = "modifySAFECollateralization(bytes32,bytes32,address,address,address,int256,int256)";
//         bytes memory data = abi.encodeWithSignature(
//           sig, address(this), coinName, collateralType, safe, collateralSource, debtDestination, deltaCollateral, deltaDebt
//         );
//
//         bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", safeEngine, data);
//         (bool ok, bytes memory success) = address(this).call(can_call);
//
//         ok = abi.decode(success, (bool));
//         if (ok) return true;
//     }
//     function can_transferSAFECollateralAndDebt(
//       bytes32 coinName,
//       bytes32 collateralType,
//       address src,
//       address dst,
//       int deltaCollateral,
//       int deltaDebt
//     ) public returns (bool) {
//         string memory sig = "transferSAFECollateralAndDebt(bytes32,bytes32,address,address,int256,int256)";
//         bytes memory data = abi.encodeWithSignature(sig, coinName, collateralType, src, dst, deltaCollateral, deltaDebt);
//
//         bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", safeEngine, data);
//         (bool ok, bytes memory success) = address(this).call(can_call);
//
//         ok = abi.decode(success, (bool));
//         if (ok) return true;
//     }
//     function modifySAFECollateralization(
//       bytes32 coinName,
//       bytes32 collateralType,
//       address safe,
//       address collateralSource,
//       address debtDestination,
//       int deltaCollateral,
//       int deltaDebt
//     ) public {
//         safeEngine.modifySAFECollateralization(
//           coinName, collateralType, safe, collateralSource, debtDestination, deltaCollateral, deltaDebt
//         );
//     }
//     function transferSAFECollateralAndDebt(
//       bytes32 coinName, bytes32 collateralType, address src, address dst, int deltaCollateral, int deltaDebt
//     ) public {
//         safeEngine.transferSAFECollateralAndDebt(coinName, collateralType, src, dst, deltaCollateral, deltaDebt);
//     }
//     function approveSAFEModification(bytes32 coinName, address usr) public {
//         safeEngine.approveSAFEModification(coinName, usr);
//     }
//     function pass() public {}
// }
//
// contract SingleTransferSAFECollateralAndDebtTest is DSTest {
//     MultiSAFEEngine safeEngine;
//     Usr ali;
//     Usr bob;
//     address a;
//     address b;
//
//     bytes32 coinName = "MAI";
//
//     function ray(uint wad) internal pure returns (uint) {
//         return wad * 10 ** 9;
//     }
//     function rad(uint wad) internal pure returns (uint) {
//         return wad * 10 ** 27;
//     }
//
//     function setUp() public {
//         safeEngine = new MultiSAFEEngine();
//         ali = new Usr(safeEngine);
//         bob = new Usr(safeEngine);
//         a = address(ali);
//         b = address(bob);
//
//         safeEngine.addCollateralJoin("collateralTokens", address(this));
//
//         safeEngine.initializeCoin(coinName, uint(-1));
//         safeEngine.initializeCollateralType(coinName, "collateralTokens");
//         safeEngine.modifyParameters(coinName, "collateralTokens", "safetyPrice", ray(0.5  ether));
//         safeEngine.modifyParameters(coinName, "collateralTokens", "debtCeiling", rad(1000 ether));
//         safeEngine.modifyParameters(coinName, "globalDebtCeiling", rad(1000 ether));
//
//         safeEngine.addAuthorization(coinName, a);
//         safeEngine.addAuthorization(coinName, b);
//
//         safeEngine.modifyCollateralBalance("collateralTokens", a, 80 ether);
//     }
//     function test_transferCollateralAndDebt_to_self() public {
//         ali.modifySAFECollateralization(coinName, "collateralTokens", a, a, a, 8 ether, 4 ether);
//         assertTrue( ali.can_transferSAFECollateralAndDebt(coinName, "collateralTokens", a, a, 8 ether, 4 ether));
//         assertTrue( ali.can_transferSAFECollateralAndDebt(coinName, "collateralTokens", a, a, 4 ether, 2 ether));
//         assertTrue(!ali.can_transferSAFECollateralAndDebt(coinName, "collateralTokens", a, a, 9 ether, 4 ether));
//     }
//     function test_transferCollateralAndDebt_to_other() public {
//         ali.modifySAFECollateralization(coinName, "collateralTokens", a, a, a, 8 ether, 4 ether);
//         assertTrue(!ali.can_transferSAFECollateralAndDebt(coinName, "collateralTokens", a, b, 8 ether, 4 ether));
//         bob.approveSAFEModification(coinName, address(ali));
//         assertTrue( ali.can_transferSAFECollateralAndDebt(coinName, "collateralTokens", a, b, 8 ether, 4 ether));
//     }
//     function test_give_to_other() public {
//         ali.modifySAFECollateralization(coinName, "collateralTokens", a, a, a, 8 ether, 4 ether);
//         bob.approveSAFEModification(coinName, address(ali));
//         assertTrue( ali.can_transferSAFECollateralAndDebt(coinName, "collateralTokens", a, b, 4 ether, 2 ether));
//         assertTrue(!ali.can_transferSAFECollateralAndDebt(coinName, "collateralTokens", a, b, 4 ether, 3 ether));
//         assertTrue(!ali.can_transferSAFECollateralAndDebt(coinName, "collateralTokens", a, b, 4 ether, 1 ether));
//     }
//     function test_transferCollateralAndDebt_dust() public {
//         ali.modifySAFECollateralization(coinName, "collateralTokens", a, a, a, 8 ether, 4 ether);
//         bob.approveSAFEModification(coinName, address(ali));
//         assertTrue( ali.can_transferSAFECollateralAndDebt(coinName, "collateralTokens", a, b, 4 ether, 2 ether));
//         safeEngine.modifyParameters(coinName, "collateralTokens", "debtFloor", rad(1 ether));
//         assertTrue( ali.can_transferSAFECollateralAndDebt(coinName, "collateralTokens", a, b, 2 ether, 1 ether));
//         assertTrue(!ali.can_transferSAFECollateralAndDebt(coinName, "collateralTokens", a, b, 1 ether, 0.5 ether));
//     }
// }
