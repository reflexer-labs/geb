pragma solidity 0.6.7;

import "ds-test/test.sol";
import {DebtAuctionHouse as DAH} from './DebtAuctionHouse.t.sol';
import {BurningSurplusAuctionHouse as SAH_ONE} from "./SurplusAuctionHouse.t.sol";
import {PostSettlementSurplusAuctionHouse as SAH_TWO} from "./SurplusAuctionHouse.t.sol";
import {TestSAFEEngine as SAFEEngine} from './SAFEEngine.t.sol';
import {AccountingEngine} from '../AccountingEngine.sol';
import {SettlementSurplusAuctioneer} from "../SettlementSurplusAuctioneer.sol";
import {CoinJoin} from '../BasicTokenAdapters.sol';

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract Gem {
    mapping (address => uint256) public balanceOf;
    function mint(address usr, uint rad) public {
        balanceOf[usr] += rad;
    }
}

contract User {
    function popDebtFromQueue(address accountingEngine, uint timestamp) public {
        AccountingEngine(accountingEngine).popDebtFromQueue(timestamp);
    }
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

contract AccountingEngineTest is DSTest {
    Hevm hevm;

    SAFEEngine  safeEngine;
    AccountingEngine  accountingEngine;
    DAH debtAuctionHouse;
    SAH_ONE surplusAuctionHouseOne;
    SAH_TWO surplusAuctionHouseTwo;
    SettlementSurplusAuctioneer postSettlementSurplusDrain;
    Gem  protocolToken;
    ProtocolTokenAuthority tokenAuthority;

    User alice;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        alice = new User();

        safeEngine = new SAFEEngine();

        protocolToken  = new Gem();
        debtAuctionHouse = new DAH(address(safeEngine), address(protocolToken));
        surplusAuctionHouseOne = new SAH_ONE(address(safeEngine), address(protocolToken));

        accountingEngine = new AccountingEngine(
          address(safeEngine), address(surplusAuctionHouseOne), address(debtAuctionHouse)
        );
        surplusAuctionHouseOne.addAuthorization(address(accountingEngine));

        debtAuctionHouse.addAuthorization(address(accountingEngine));

        accountingEngine.modifyParameters("surplusAuctionAmountToSell", rad(100 ether));
        accountingEngine.modifyParameters("debtAuctionBidSize", rad(100 ether));
        accountingEngine.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);

        safeEngine.approveSAFEModification(address(debtAuctionHouse));

        tokenAuthority = new ProtocolTokenAuthority();
        tokenAuthority.addAuthorization(address(debtAuctionHouse));

        accountingEngine.modifyParameters("protocolTokenAuthority", address(tokenAuthority));
    }

    function try_popDebtFromQueue(uint era) internal returns (bool ok) {
        string memory sig = "popDebtFromQueue(uint256)";
        (ok,) = address(accountingEngine).call(abi.encodeWithSignature(sig, era));
    }
    function try_decreaseSoldAmount(uint id, uint amountToBuy, uint bid) internal returns (bool ok) {
        string memory sig = "decreaseSoldAmount(uint256,uint256,uint256)";
        (ok,) = address(debtAuctionHouse).call(abi.encodeWithSignature(sig, id, amountToBuy, bid));
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
    function can_auctionSurplus() public returns (bool) {
        string memory sig = "auctionSurplus()";
        bytes memory data = abi.encodeWithSignature(sig);

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", accountingEngine, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function can_TransferSurplus() public returns (bool) {
        string memory sig = "transferExtraSurplus()";
        bytes memory data = abi.encodeWithSignature(sig);

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", accountingEngine, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }
    function can_auction_debt() public returns (bool) {
        string memory sig = "auctionDebt()";
        bytes memory data = abi.encodeWithSignature(sig);

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", accountingEngine, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }

    uint constant ONE = 10 ** 27;
    function rad(uint wad) internal pure returns (uint) {
        return wad * ONE;
    }

    function createUnbackedDebt(address who, uint wad) internal {
        accountingEngine.pushDebtToQueue(rad(wad));
        safeEngine.initializeCollateralType('');
        safeEngine.createUnbackedDebt(address(accountingEngine), who, rad(wad));
    }
    function popDebtFromQueue(uint wad) internal {
        createUnbackedDebt(address(0), wad);  // create unbacked coins into the zero address
        accountingEngine.popDebtFromQueue(now);
        assertEq(accountingEngine.debtPoppers(now), address(this));
    }
    function settleDebt(uint wad) internal {
        accountingEngine.settleDebt(rad(wad));
    }

    function test_change_auction_houses() public {
        SAH_ONE newSAH_ONE = new SAH_ONE(address(safeEngine), address(protocolToken));
        DAH newDAH = new DAH(address(safeEngine), address(protocolToken));

        newSAH_ONE.addAuthorization(address(accountingEngine));
        newDAH.addAuthorization(address(accountingEngine));

        assertTrue(safeEngine.canModifySAFE(address(accountingEngine), address(surplusAuctionHouseOne)));
        assertTrue(!safeEngine.canModifySAFE(address(accountingEngine), address(newSAH_ONE)));

        accountingEngine.modifyParameters('surplusAuctionHouse', address(newSAH_ONE));
        accountingEngine.modifyParameters('debtAuctionHouse', address(newDAH));

        assertEq(address(accountingEngine.surplusAuctionHouse()), address(newSAH_ONE));
        assertEq(address(accountingEngine.debtAuctionHouse()), address(newDAH));

        assertTrue(!safeEngine.canModifySAFE(address(accountingEngine), address(surplusAuctionHouseOne)));
        assertTrue(safeEngine.canModifySAFE(address(accountingEngine), address(newSAH_ONE)));
    }

    function test_popDebtFromQueue_delay() public {
        assertEq(accountingEngine.popDebtDelay(), 0);
        accountingEngine.modifyParameters('popDebtDelay', uint(100 seconds));
        assertEq(accountingEngine.popDebtDelay(), 100 seconds);

        uint tic = now;
        accountingEngine.pushDebtToQueue(100 ether);
        assertTrue(!try_popDebtFromQueue(tic) );
        hevm.warp(now + tic + 100 seconds);
        assertTrue( try_popDebtFromQueue(tic) );
    }

    function test_no_debt_auction_not_auth_permitted() public {
        tokenAuthority.removeAuthorization(address(debtAuctionHouse));
        assertTrue( !can_auction_debt() );
    }

    function test_no_debt_auction_token_auth_not_set() public {
        accountingEngine.modifyParameters("protocolTokenAuthority", address(0));
        assertTrue( !can_auction_debt() );
    }

    function test_no_reauction_debt() public {
        popDebtFromQueue(100 ether);
        assertTrue( can_auction_debt() );
        accountingEngine.auctionDebt();
        assertTrue(!can_auction_debt() );
    }

    function test_debt_auction_pending_surplus() public {
        popDebtFromQueue(200 ether);

        safeEngine.mint(address(accountingEngine), 100 ether);
        assertTrue(can_auction_debt());

        settleDebt(100 ether);
        assertTrue(can_auction_debt());
    }

    function test_debt_auction_less_unauction_debt_than_bid_size() public {
        accountingEngine.modifyParameters("debtAuctionBidSize", rad(150 ether));

        popDebtFromQueue(200 ether);
        safeEngine.mint(address(accountingEngine), 100 ether);

        assertTrue(can_auction_debt());
    }

    function testFail_pop_debt_after_being_popped() public {
        popDebtFromQueue(100 ether);
        assertEq(accountingEngine.debtPoppers(now), address(this));
        alice.popDebtFromQueue(address(accountingEngine), now);
    }

    function test_surplus_auction_when_transfer_permitted() public {
        accountingEngine.modifyParameters("extraSurplusIsTransferred", 1);
        safeEngine.mint(address(accountingEngine), 100 ether);
        assertTrue( !can_auctionSurplus() );
    }

    function test_auction_surplus_when_amount_null() public {
        accountingEngine.modifyParameters("surplusAuctionAmountToSell", 0);
        safeEngine.mint(address(accountingEngine), 100 ether);
        assertTrue( !can_auctionSurplus() );
    }

    function test_surplus_auction() public {
        safeEngine.mint(address(accountingEngine), 100 ether);
        assertTrue( can_auctionSurplus() );
    }

    function test_transfer_surplus_when_not_permitted() public {
        accountingEngine.modifyParameters("extraSurplusReceiver", address(1));
        accountingEngine.modifyParameters("surplusTransferAmount", 100 ether);
        safeEngine.mint(address(accountingEngine), 100 ether);
        assertTrue( !can_TransferSurplus() );
    }

    function test_transfer_surplus_when_receiver_not_defined() public {
        accountingEngine.modifyParameters("extraSurplusIsTransferred", 1);
        accountingEngine.modifyParameters("surplusTransferAmount", 100 ether);
        safeEngine.mint(address(accountingEngine), 100 ether);
        assertTrue( !can_TransferSurplus() );
    }

    function test_transfer_surplus_when_amount_not_defined() public {
        accountingEngine.modifyParameters("extraSurplusIsTransferred", 1);
        accountingEngine.modifyParameters("extraSurplusReceiver", address(1));
        safeEngine.mint(address(accountingEngine), 100 ether);
        assertTrue( !can_auctionSurplus() );
    }

    function test_surplus_transfer() public {
        accountingEngine.modifyParameters("extraSurplusIsTransferred", 1);
        accountingEngine.modifyParameters("extraSurplusReceiver", address(1));
        accountingEngine.modifyParameters("surplusTransferAmount", 100 ether);
        safeEngine.mint(address(accountingEngine), 100 ether);
        assertTrue( !can_auctionSurplus() );
        assertTrue( can_TransferSurplus() );
    }

    function test_surplus_transfer_twice_in_a_row() public {
        accountingEngine.modifyParameters("extraSurplusIsTransferred", 1);
        accountingEngine.modifyParameters("extraSurplusReceiver", address(1));
        accountingEngine.modifyParameters("surplusTransferAmount", 100 ether);
        safeEngine.mint(address(accountingEngine), 200 ether);
        accountingEngine.transferExtraSurplus();
        assertEq(safeEngine.coinBalance(address(1)), 100 ether);
        assertTrue( can_TransferSurplus() );
        accountingEngine.transferExtraSurplus();
        assertEq(safeEngine.coinBalance(address(1)), 200 ether);
    }

    function test_surplus_transfer_after_waiting() public {
        accountingEngine.modifyParameters("extraSurplusIsTransferred", 1);
        accountingEngine.modifyParameters("extraSurplusReceiver", address(1));
        accountingEngine.modifyParameters("surplusTransferAmount", 100 ether);
        accountingEngine.modifyParameters("surplusTransferDelay", 1);
        safeEngine.mint(address(accountingEngine), 200 ether);
        assertTrue( !can_TransferSurplus() );
        hevm.warp(now + 1);
        accountingEngine.transferExtraSurplus();
        assertEq(safeEngine.coinBalance(address(1)), 100 ether);
        assertTrue( !can_TransferSurplus() );
    }

    function test_settlement_auction_surplus() public {
        // Post settlement auction house setup
        surplusAuctionHouseTwo = new SAH_TWO(address(safeEngine), address(protocolToken));
        // Auctioneer setup
        postSettlementSurplusDrain = new SettlementSurplusAuctioneer(address(accountingEngine), address(surplusAuctionHouseTwo));
        surplusAuctionHouseTwo.addAuthorization(address(postSettlementSurplusDrain));

        safeEngine.mint(address(postSettlementSurplusDrain), 100 ether);
        accountingEngine.disableContract();
        uint id = postSettlementSurplusDrain.auctionSurplus();
        assertEq(id, 1);
    }

    function test_settlement_delay_transfer_surplus() public {
        // Post settlement auction house setup
        surplusAuctionHouseTwo = new SAH_TWO(address(safeEngine), address(protocolToken));
        // Auctioneer setup
        postSettlementSurplusDrain = new SettlementSurplusAuctioneer(address(accountingEngine), address(surplusAuctionHouseTwo));
        surplusAuctionHouseTwo.addAuthorization(address(postSettlementSurplusDrain));

        accountingEngine.modifyParameters("postSettlementSurplusDrain", address(postSettlementSurplusDrain));
        safeEngine.mint(address(accountingEngine), 100 ether);

        accountingEngine.modifyParameters("disableCooldown", 1);
        accountingEngine.disableContract();

        assertEq(safeEngine.coinBalance(address(accountingEngine)), rad(100 ether));
        assertEq(safeEngine.coinBalance(address(postSettlementSurplusDrain)), 0);
        hevm.warp(now + 1);

        accountingEngine.transferPostSettlementSurplus();
        assertEq(safeEngine.coinBalance(address(accountingEngine)), 0);
        assertEq(safeEngine.coinBalance(address(postSettlementSurplusDrain)), rad(100 ether));

        safeEngine.mint(address(accountingEngine), 100 ether);
        accountingEngine.transferPostSettlementSurplus();
        assertEq(safeEngine.coinBalance(address(accountingEngine)), 0);
        assertEq(safeEngine.coinBalance(address(postSettlementSurplusDrain)), rad(200 ether));
    }

    function test_no_surplus_auction_pending_debt() public {
        accountingEngine.modifyParameters("surplusAuctionAmountToSell", uint256(0 ether));
        popDebtFromQueue(100 ether);

        safeEngine.mint(address(accountingEngine), 50 ether);
        assertTrue(!can_auctionSurplus() );
    }
    function test_no_transfer_surplus_pending_debt() public {
        accountingEngine.modifyParameters("extraSurplusIsTransferred", 1);
        accountingEngine.modifyParameters("extraSurplusReceiver", address(1));
        accountingEngine.modifyParameters("surplusTransferAmount", 0 ether);

        popDebtFromQueue(100 ether);
        safeEngine.mint(address(accountingEngine), 50 ether);
        assertTrue(!can_TransferSurplus() );
    }
    function test_no_surplus_auction_nonzero_bad_debt() public {
        accountingEngine.modifyParameters("surplusAuctionAmountToSell", uint256(0 ether));
        popDebtFromQueue(100 ether);
        safeEngine.mint(address(accountingEngine), 50 ether);
        assertTrue(!can_auctionSurplus() );
    }
    function test_no_transfer_surplus_nonzero_bad_debt() public {
        accountingEngine.modifyParameters("extraSurplusIsTransferred", 1);
        accountingEngine.modifyParameters("extraSurplusReceiver", address(1));
        accountingEngine.modifyParameters("surplusTransferAmount", 0);

        popDebtFromQueue(100 ether);
        safeEngine.mint(address(accountingEngine), 50 ether);
        assertTrue(!can_TransferSurplus() );
    }
    function test_no_surplus_auction_pending_debt_auction() public {
        popDebtFromQueue(100 ether);
        accountingEngine.debtAuctionHouse();

        safeEngine.mint(address(accountingEngine), 100 ether);

        assertTrue(!can_auctionSurplus() );
    }
    function test_no_transfer_surplus_pending_debt_auction() public {
        accountingEngine.modifyParameters("extraSurplusIsTransferred", 1);
        accountingEngine.modifyParameters("extraSurplusReceiver", address(1));

        popDebtFromQueue(100 ether);
        accountingEngine.debtAuctionHouse();

        safeEngine.mint(address(accountingEngine), 100 ether);

        assertTrue(!can_TransferSurplus() );
    }
    function test_no_surplus_auction_pending_settleDebt() public {
        popDebtFromQueue(100 ether);
        uint id = accountingEngine.auctionDebt();

        safeEngine.mint(address(this), 100 ether);
        debtAuctionHouse.decreaseSoldAmount(id, 0 ether, rad(100 ether));

        assertTrue(!can_auctionSurplus() );
    }
    function test_no_transfer_surplus_pending_settleDebt() public {
        accountingEngine.modifyParameters("extraSurplusIsTransferred", 1);
        accountingEngine.modifyParameters("extraSurplusReceiver", address(1));

        popDebtFromQueue(100 ether);
        uint id = accountingEngine.auctionDebt();

        safeEngine.mint(address(this), 100 ether);
        debtAuctionHouse.decreaseSoldAmount(id, 0 ether, rad(100 ether));

        assertTrue(!can_TransferSurplus() );
    }
    function test_no_surplus_after_good_debt_auction() public {
        popDebtFromQueue(100 ether);
        uint id = accountingEngine.auctionDebt();
        safeEngine.mint(address(this), 100 ether);

        debtAuctionHouse.decreaseSoldAmount(id, 0 ether, rad(100 ether));  // debt auction succeeds..

        assertTrue(!can_auctionSurplus() );
    }
    function test_no_transfer_surplus_after_good_debt_auction() public {
        accountingEngine.modifyParameters("extraSurplusIsTransferred", 1);
        accountingEngine.modifyParameters("extraSurplusReceiver", address(1));

        popDebtFromQueue(100 ether);
        uint id = accountingEngine.auctionDebt();
        safeEngine.mint(address(this), 100 ether);

        debtAuctionHouse.decreaseSoldAmount(id, 0 ether, rad(100 ether));  // debt auction succeeds..

        assertTrue(!can_TransferSurplus() );
    }
    function test_multiple_increaseBidSize() public {
        popDebtFromQueue(100 ether);
        uint id = accountingEngine.auctionDebt();

        safeEngine.mint(address(this), 100 ether);
        assertTrue(try_decreaseSoldAmount(id, 2 ether, rad(100 ether)));

        safeEngine.mint(address(this), 100 ether);
        assertTrue(try_decreaseSoldAmount(id, 1 ether,  rad(100 ether)));
    }
}
