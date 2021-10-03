// pragma solidity 0.6.7;
//
// import "ds-test/test.sol";
// import {TestMultiSAFEEngine as MultiSAFEEngine} from './MultiSAFEEngine.t.sol';
// import {MultiAccountingEngine} from '../../multi/MultiAccountingEngine.sol';
// import {MultiCoinJoin} from '../../shared/BasicTokenAdapters.sol';
//
// abstract contract Hevm {
//     function warp(uint256) virtual public;
// }
//
// contract Gem {
//     mapping (address => uint256) public balanceOf;
//     function mint(address usr, uint rad) public {
//         balanceOf[usr] += rad;
//     }
// }
//
// contract User {
//     function popDebtFromQueue(address accountingEngine, bytes32 coinName, uint timestamp) public {
//         MultiAccountingEngine(accountingEngine).popDebtFromQueue(coinName, timestamp);
//     }
// }
//
// contract MultiAccountingEngineTest is DSTest {
//     Hevm hevm;
//
//     MultiSAFEEngine safeEngine;
//     MultiAccountingEngine  accountingEngine;
//
//     User alice;
//
//     bytes32 coinName = "MAI";
//
//     function setUp() public {
//         hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
//         hevm.warp(604411200);
//
//         alice = new User();
//
//         safeEngine = new MultiSAFEEngine();
//         safeEngine.initializeCoin(coinName, uint(-1));
//
//         accountingEngine = new MultiAccountingEngine(address(safeEngine), address(0), 100 seconds, 28 days);
//         accountingEngine.addSystemComponent(address(this));
//         accountingEngine.initializeCoin(coinName, rad(100 ether), 1);
//     }
//
//     function try_popDebtFromQueue(uint era) internal returns (bool ok) {
//         string memory sig = "popDebtFromQueue(bytes32,uint256)";
//         (ok,) = address(accountingEngine).call(abi.encodeWithSignature(sig, coinName, era));
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
//     function can_TransferSurplus() public returns (bool) {
//         string memory sig = "transferExtraSurplus(bytes32)";
//         bytes memory data = abi.encodeWithSignature(sig, coinName);
//
//         bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", accountingEngine, data);
//         (bool ok, bytes memory success) = address(this).call(can_call);
//
//         ok = abi.decode(success, (bool));
//         if (ok) return true;
//     }
//
//     uint constant ONE = 10 ** 27;
//     function rad(uint wad) internal pure returns (uint) {
//         return wad * ONE;
//     }
//
//     function createUnbackedDebt(address who, uint wad) internal {
//         accountingEngine.pushDebtToQueue(coinName, rad(wad));
//         safeEngine.initializeCollateralType(coinName, '');
//         safeEngine.createUnbackedDebt(coinName, address(accountingEngine), who, rad(wad));
//     }
//     function popDebtFromQueue(uint wad) internal {
//         createUnbackedDebt(address(0), wad);  // create unbacked coins into the zero address
//         hevm.warp(now + accountingEngine.popDebtDelay() + 1);
//         accountingEngine.popDebtFromQueue(coinName, now - 1 - accountingEngine.popDebtDelay());
//         // assertEq(accountingEngine.debtPoppers(coinName, now), address(this));
//     }
//     function settleDebt(uint wad) internal {
//         accountingEngine.settleDebt(coinName, rad(wad));
//     }
//
//     function test_change_surplus_receiver() public {
//         accountingEngine.modifyParameters(coinName, 'extraSurplusReceiver', address(0x1));
//         assertEq(address(accountingEngine.extraSurplusReceiver(coinName)), address(0x1));
//     }
//
//     function test_popDebtFromQueue_delay() public {
//         assertEq(accountingEngine.popDebtDelay(), 100 seconds);
//
//         uint tic = now;
//         accountingEngine.pushDebtToQueue(coinName, 100 ether);
//         assertEq(accountingEngine.totalQueuedDebt(coinName), 100 ether);
//
//         assertTrue(!try_popDebtFromQueue(tic) );
//         hevm.warp(now + tic + 100 seconds);
//         assertTrue( try_popDebtFromQueue(tic) );
//
//         assertEq(accountingEngine.totalQueuedDebt(coinName), 0);
//         assertEq(accountingEngine.debtPoppers(coinName, tic), address(this));
//         assertEq(accountingEngine.debtQueue(coinName, tic), 0);
//     }
//
//     function testFail_pop_debt_after_being_popped() public {
//         popDebtFromQueue(100 ether);
//         assertEq(accountingEngine.debtPoppers(coinName, now), address(this));
//         alice.popDebtFromQueue(address(accountingEngine), coinName, now);
//     }
//
//     function test_surplus_transfer() public {
//         accountingEngine.modifyParameters(coinName, "extraSurplusReceiver", address(1));
//         accountingEngine.modifyParameters(coinName, "surplusTransferAmount", 100 ether);
//         safeEngine.mint(coinName, address(accountingEngine), 100 ether);
//         assertTrue( can_TransferSurplus() );
//     }
//
//     function test_surplus_transfer_twice_in_a_row() public {
//         accountingEngine.modifyParameters(coinName, "extraSurplusReceiver", address(1));
//         accountingEngine.modifyParameters(coinName, "surplusTransferAmount", 100 ether);
//         safeEngine.mint(coinName, address(accountingEngine), 200 ether);
//         accountingEngine.transferExtraSurplus(coinName);
//         assertEq(safeEngine.coinBalance(coinName, address(1)), 100 ether);
//         assertTrue( can_TransferSurplus() );
//         accountingEngine.transferExtraSurplus(coinName);
//         assertEq(safeEngine.coinBalance(coinName, address(1)), 200 ether);
//     }
//
//     function test_disable_coin() public {
//         accountingEngine.modifyParameters(coinName, "extraSurplusReceiver", address(1));
//         safeEngine.mint(coinName, accountingEngine.postSettlementSurplusDrain(), 100 ether);
//
//         assertEq(accountingEngine.coinEnabled(coinName), 1);
//         accountingEngine.disableCoin(coinName);
//
//         assertEq(accountingEngine.coinEnabled(coinName), 0);
//         assertEq(accountingEngine.coinInitialized(coinName), 1);
//         assertEq(accountingEngine.disableTimestamp(coinName), now);
//         assertEq(accountingEngine.totalQueuedDebt(coinName), 0);
//         assertEq(accountingEngine.extraSurplusReceiver(coinName), address(0));
//     }
//
//     function test_settlement_delay_transfer_surplus() public {
//         safeEngine.mint(coinName, address(accountingEngine), 100 ether);
//
//         accountingEngine.disableCoin(coinName);
//
//         assertEq(safeEngine.coinBalance(coinName, address(accountingEngine)), rad(100 ether));
//         assertEq(safeEngine.coinBalance(coinName, accountingEngine.postSettlementSurplusDrain()), 0);
//         hevm.warp(now + accountingEngine.disableCooldown() + 1);
//
//         accountingEngine.transferPostSettlementSurplus(coinName);
//         assertEq(safeEngine.coinBalance(coinName, address(accountingEngine)), 0);
//         assertEq(safeEngine.coinBalance(coinName, accountingEngine.postSettlementSurplusDrain()), rad(100 ether));
//
//         safeEngine.mint(coinName, address(accountingEngine), 100 ether);
//         accountingEngine.transferPostSettlementSurplus(coinName);
//         assertEq(safeEngine.coinBalance(coinName, address(accountingEngine)), 0);
//         assertEq(safeEngine.coinBalance(coinName, accountingEngine.postSettlementSurplusDrain()), rad(200 ether));
//     }
//
//     function test_no_transfer_surplus_pending_debt() public {
//         accountingEngine.modifyParameters(coinName, "extraSurplusReceiver", address(1));
//         accountingEngine.modifyParameters(coinName, "surplusTransferAmount", 50 ether);
//         safeEngine.mint(coinName, address(accountingEngine), 100 ether);
//
//         popDebtFromQueue(100 ether);
//         assertTrue(!can_TransferSurplus() );
//     }
//
//     function test_no_transfer_surplus_nonzero_bad_debt() public {
//         accountingEngine.modifyParameters(coinName, "extraSurplusReceiver", address(1));
//         accountingEngine.modifyParameters(coinName, "surplusTransferAmount", 0);
//
//         popDebtFromQueue(100 ether);
//         safeEngine.mint(coinName, address(accountingEngine), 50 ether);
//         assertTrue(!can_TransferSurplus() );
//     }
// }
