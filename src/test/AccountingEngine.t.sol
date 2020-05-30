pragma solidity ^0.5.15;

import "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";
import {DebtAuctionHouse as DAH} from './DebtAuctionHouse.t.sol';
import {SurplusAuctionHouseOne as SAH_ONE} from "./SurplusAuctionHouse.t.sol";
import {SurplusAuctionHouseTwo as SAH_TWO} from './SurplusAuctionHouse.t.sol';
import {TestCDPEngine as CDPEngine} from './CDPEngine.t.sol';
import {AccountingEngine} from '../AccountingEngine.sol';
import {SettlementSurplusAuctioner} from "../SettlementSurplusAuctioner.sol";
import {CoinJoin} from '../BasicTokenAdapters.sol';

contract Hevm {
    function warp(uint256) public;
}

contract DexLike {
    bytes32 public constant INPUT  = bytes32("INPUT");

    uint256 give;

    constructor(
      uint256 give_
    ) public {
      give = give_;
    }

    function tkntkn(bytes32 side, uint amountSold, address dst, address[] calldata swapPath) external returns (uint) {
        DSToken(swapPath[0]).transferFrom(msg.sender, address(this), amountSold);
        DSToken(swapPath[1]).transfer(dst, give);
        return give;
    }
}

contract AccountingEngineDexFlapperTest is DSTest {
    Hevm hevm;

    CDPEngine cdpEngine;
    AccountingEngine accountingEngine;
    DAH debtAuctionHouse;
    SAH_TWO surplusAuctionHouseTwo;
    DexLike dex;

    DSToken protocolToken;
    DSToken systemCoin;
    CoinJoin systemCoinA;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        cdpEngine = new CDPEngine();

        protocolToken  = new DSToken('');
        systemCoin = new DSToken("Coin");
        dex  = new DexLike(1 ether);
        systemCoinA = new CoinJoin(address(cdpEngine), address(systemCoin));

        cdpEngine.addAuthorization(address(systemCoinA));
        systemCoin.mint(address(this), 50 ether);
        systemCoin.setOwner(address(systemCoinA));

        debtAuctionHouse = new DAH(address(cdpEngine), address(protocolToken));

        surplusAuctionHouseTwo = new SAH_TWO(address(cdpEngine), address(protocolToken));
        surplusAuctionHouseTwo.modifyParameters("systemCoin", address(systemCoin));
        surplusAuctionHouseTwo.modifyParameters("dex", address(dex));
        surplusAuctionHouseTwo.modifyParameters("coinJoin", address(systemCoinA));
        surplusAuctionHouseTwo.modifyParameters("leftoverReceiver", address(this));

        cdpEngine.approveCDPModification(address(surplusAuctionHouseTwo));
        protocolToken.approve(address(surplusAuctionHouseTwo));

        accountingEngine = new AccountingEngine(
          address(cdpEngine), address(surplusAuctionHouseTwo), address(debtAuctionHouse)
        );
        surplusAuctionHouseTwo.addAuthorization(address(accountingEngine));
        debtAuctionHouse.addAuthorization(address(accountingEngine));

        accountingEngine.modifyParameters("surplusAuctionAmountToSell", rad(100 ether));
        accountingEngine.modifyParameters("debtAuctionBidSize", rad(100 ether));
        accountingEngine.modifyParameters("initialDebtAuctionAmount", 200 ether);

        cdpEngine.approveCDPModification(address(debtAuctionHouse));
        cdpEngine.addAuthorization(address(accountingEngine));

        protocolToken.mint(200 ether);
        protocolToken.setOwner(address(surplusAuctionHouseTwo));
        protocolToken.push(address(dex), 200 ether);

        cdpEngine.createUnbackedDebt(address(this), address(this), 1000 ether * 10 ** 27);
        cdpEngine.transferInternalCoins(address(this), address(systemCoinA), 100 ether * 10 ** 27);
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
            let ok := call(gas, addr, 0, add(_data, 0x20), mload(_data), 0, 0)
            let free := mload(0x40)
            mstore(free, ok)
            mstore(0x40, add(free, 32))
            revert(free, 32)
        }
    }
    function can_auction_surplus() public returns (bool) {
        string memory sig = "auctionSurplus()";
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

    uint constant RAY = 10 ** 27;
    function rad(uint wad) internal pure returns (uint) {
        return wad * RAY;
    }

    function createUnbackedDebt(address who, uint wad) internal {
        accountingEngine.pushDebtToQueue(rad(wad));
        cdpEngine.initializeCollateralType('');
        cdpEngine.createUnbackedDebt(address(accountingEngine), who, rad(wad));
    }
    function popDebtFromQueue(uint wad) internal {
        createUnbackedDebt(address(0), wad);  // createUnbackedDebt coin into the zero address
        accountingEngine.popDebtFromQueue(now);
    }
    function settleDebt(uint wad) internal {
        accountingEngine.settleDebt(rad(wad));
    }

    function test_change_auction_houses() public {
        SAH_TWO newSurplusAuctionHouse = new SAH_TWO(address(cdpEngine), address(protocolToken));
        DAH newDAH = new DAH(address(cdpEngine), address(protocolToken));

        newSurplusAuctionHouse.addAuthorization(address(accountingEngine));
        newDAH.addAuthorization(address(accountingEngine));

        assertTrue(cdpEngine.canModifyCDP(address(accountingEngine), address(surplusAuctionHouseTwo)));
        assertTrue(!cdpEngine.canModifyCDP(address(accountingEngine), address(newSurplusAuctionHouse)));

        accountingEngine.modifyParameters('surplusAuctionHouse', address(newSurplusAuctionHouse));
        accountingEngine.modifyParameters('debtAuctionHouse', address(newDAH));

        assertEq(address(accountingEngine.surplusAuctionHouse()), address(newSurplusAuctionHouse));
        assertEq(address(accountingEngine.debtAuctionHouse()), address(newDAH));

        assertTrue(!cdpEngine.canModifyCDP(address(accountingEngine), address(surplusAuctionHouseTwo)));
        assertTrue(cdpEngine.canModifyCDP(address(accountingEngine), address(newSurplusAuctionHouse)));
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

    function test_no_reauction_debt() public {
        popDebtFromQueue(100 ether);
        assertTrue( can_auction_debt() );
        accountingEngine.auctionDebt();
        assertTrue(!can_auction_debt() );
    }

    function test_no_debt_auction_pending_surplus() public {
        popDebtFromQueue(200 ether);

        cdpEngine.mint(address(accountingEngine), 100 ether);
        assertTrue(!can_auction_debt() );

        settleDebt(100 ether);
        assertTrue( can_auction_debt() );
    }

    function test_basic_disable() public {
        assertEq(surplusAuctionHouseTwo.contractEnabled(), 1);
        assertEq(debtAuctionHouse.contractEnabled(), 1);
        accountingEngine.disableContract();
        assertEq(surplusAuctionHouseTwo.contractEnabled(), 0);
        assertEq(debtAuctionHouse.contractEnabled(), 0);
    }

    function test_disable_prefunded_surplus_auction_house() public {
        systemCoin.transfer(address(surplusAuctionHouseTwo), 50 ether);
        accountingEngine.disableContract();
        assertEq(systemCoin.balanceOf(address(surplusAuctionHouseTwo)), 0);
        assertEq(cdpEngine.coinBalance(address(surplusAuctionHouseTwo)), 0);
        assertEq(systemCoin.balanceOf(address(accountingEngine)), 0);
        assertEq(cdpEngine.coinBalance(address(accountingEngine)), 0);
    }

    function test_surplus_auction_two() public {
        cdpEngine.mint(address(accountingEngine), 100 ether * 10 ** 27);
        assertTrue( can_auction_surplus() );
    }

    function test_no_surplus_auction_pending_debt() public {
        accountingEngine.modifyParameters("surplusAuctionAmountToSell", uint256(0 ether));
        popDebtFromQueue(100 ether);

        cdpEngine.mint(address(accountingEngine), 50 ether);
        assertTrue(!can_auction_surplus() );
    }
    function test_no_surplus_auction_nonzero_woe() public {
        accountingEngine.modifyParameters("surplusAuctionAmountToSell", uint256(0 ether));
        popDebtFromQueue(100 ether);
        cdpEngine.mint(address(accountingEngine), 50 ether);
        assertTrue(!can_auction_surplus() );
    }
    function test_no_surplus_auction_pending_debt_auction() public {
        popDebtFromQueue(100 ether);
        accountingEngine.debtAuctionHouse();

        cdpEngine.mint(address(accountingEngine), 100 ether);

        assertTrue(!can_auction_surplus() );
    }
    function test_no_surplus_auction_pending_settleDebt() public {
        popDebtFromQueue(100 ether);
        uint id = accountingEngine.auctionDebt();

        cdpEngine.mint(address(this), 100 ether);
        debtAuctionHouse.decreaseSoldAmount(id, 0 ether, rad(100 ether));

        assertTrue(!can_auction_surplus() );
    }

    function test_no_surplus_after_good_debt_auction() public {
        popDebtFromQueue(100 ether);
        uint id = accountingEngine.auctionDebt();
        cdpEngine.mint(address(this), 100 ether);

        debtAuctionHouse.decreaseSoldAmount(id, 0 ether, rad(100 ether));  // debt auction succeeds..

        assertTrue(!can_auction_surplus() );
    }

    function test_multiple_debt_auction_increaseBidSizes() public {
        popDebtFromQueue(100 ether);
        uint id = accountingEngine.auctionDebt();

        cdpEngine.mint(address(this), 100 ether);
        assertTrue(try_decreaseSoldAmount(id, 2 ether,  rad(100 ether)));

        cdpEngine.mint(address(this), 100 ether);
        assertTrue(try_decreaseSoldAmount(id, 1 ether,  rad(100 ether)));
    }
}

contract Gem {
    mapping (address => uint256) public balanceOf;
    function mint(address usr, uint rad) public {
        balanceOf[usr] += rad;
    }
}

contract AccountingEngineAuctionFlapperTest is DSTest {
    Hevm hevm;

    CDPEngine  cdpEngine;
    AccountingEngine  accountingEngine;
    DAH debtAuctionHouse;
    SAH_ONE surplusAuctionHouseOne;
    SettlementSurplusAuctioner settlementSurplusAuctioner;
    Gem  protocolToken;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        cdpEngine = new CDPEngine();

        protocolToken  = new Gem();
        debtAuctionHouse = new DAH(address(cdpEngine), address(protocolToken));
        surplusAuctionHouseOne = new SAH_ONE(address(cdpEngine), address(protocolToken));

        accountingEngine = new AccountingEngine(
          address(cdpEngine), address(surplusAuctionHouseOne), address(debtAuctionHouse)
        );
        surplusAuctionHouseOne.addAuthorization(address(accountingEngine));

        settlementSurplusAuctioner = new SettlementSurplusAuctioner(address(accountingEngine));
        accountingEngine.modifyParameters("settlementSurplusAuctioner", address(settlementSurplusAuctioner));
        surplusAuctionHouseOne.addAuthorization(address(settlementSurplusAuctioner));

        debtAuctionHouse.addAuthorization(address(accountingEngine));

        accountingEngine.modifyParameters("surplusAuctionAmountToSell", rad(100 ether));
        accountingEngine.modifyParameters("debtAuctionBidSize", rad(100 ether));
        accountingEngine.modifyParameters("initialDebtAuctionAmount", 200 ether);

        cdpEngine.approveCDPModification(address(debtAuctionHouse));
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
            let ok := call(gas, addr, 0, add(_data, 0x20), mload(_data), 0, 0)
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
        cdpEngine.initializeCollateralType('');
        cdpEngine.createUnbackedDebt(address(accountingEngine), who, rad(wad));
    }
    function popDebtFromQueue(uint wad) internal {
        createUnbackedDebt(address(0), wad);  // create unbacked coins into the zero address
        accountingEngine.popDebtFromQueue(now);
    }
    function settleDebt(uint wad) internal {
        accountingEngine.settleDebt(rad(wad));
    }

    function test_change_auction_houses() public {
        SAH_ONE newSAH_ONE = new SAH_ONE(address(cdpEngine), address(protocolToken));
        DAH newDAH = new DAH(address(cdpEngine), address(protocolToken));

        newSAH_ONE.addAuthorization(address(accountingEngine));
        newDAH.addAuthorization(address(accountingEngine));

        assertTrue(cdpEngine.canModifyCDP(address(accountingEngine), address(surplusAuctionHouseOne)));
        assertTrue(!cdpEngine.canModifyCDP(address(accountingEngine), address(newSAH_ONE)));

        accountingEngine.modifyParameters('surplusAuctionHouse', address(newSAH_ONE));
        accountingEngine.modifyParameters('debtAuctionHouse', address(newDAH));

        assertEq(address(accountingEngine.surplusAuctionHouse()), address(newSAH_ONE));
        assertEq(address(accountingEngine.debtAuctionHouse()), address(newDAH));

        assertTrue(!cdpEngine.canModifyCDP(address(accountingEngine), address(surplusAuctionHouseOne)));
        assertTrue(cdpEngine.canModifyCDP(address(accountingEngine), address(newSAH_ONE)));
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

    function test_no_reauction_debt() public {
        popDebtFromQueue(100 ether);
        assertTrue( can_auction_debt() );
        accountingEngine.auctionDebt();
        assertTrue(!can_auction_debt() );
    }

    function test_no_debt_auction_pending_joy() public {
        popDebtFromQueue(200 ether);

        cdpEngine.mint(address(accountingEngine), 100 ether);
        assertTrue(!can_auction_debt() );

        settleDebt(100 ether);
        assertTrue( can_auction_debt() );
    }

    function test_surplus_auction_one() public {
        cdpEngine.mint(address(accountingEngine), 100 ether);
        assertTrue( can_auctionSurplus() );
    }

    function test_settlement_auction_surplus() public {
        cdpEngine.mint(address(settlementSurplusAuctioner), 100 ether);
        accountingEngine.disableContract();
        uint id = settlementSurplusAuctioner.auctionSurplus();
        assertEq(id, 1);
    }

    function test_no_surplus_auction_pending_debt() public {
        accountingEngine.modifyParameters("surplusAuctionAmountToSell", uint256(0 ether));
        popDebtFromQueue(100 ether);

        cdpEngine.mint(address(accountingEngine), 50 ether);
        assertTrue(!can_auctionSurplus() );
    }
    function test_no_surplus_auction_nonzero_bad_debt() public {
        accountingEngine.modifyParameters("surplusAuctionAmountToSell", uint256(0 ether));
        popDebtFromQueue(100 ether);
        cdpEngine.mint(address(accountingEngine), 50 ether);
        assertTrue(!can_auctionSurplus() );
    }
    function test_no_surplus_auction_pending_debt_auction() public {
        popDebtFromQueue(100 ether);
        accountingEngine.debtAuctionHouse();

        cdpEngine.mint(address(accountingEngine), 100 ether);

        assertTrue(!can_auctionSurplus() );
    }
    function test_no_surplus_auction_pending_settleDebt() public {
        popDebtFromQueue(100 ether);
        uint id = accountingEngine.auctionDebt();

        cdpEngine.mint(address(this), 100 ether);
        debtAuctionHouse.decreaseSoldAmount(id, 0 ether, rad(100 ether));

        assertTrue(!can_auctionSurplus() );
    }
    function test_no_surplus_after_good_debt_auction() public {
        popDebtFromQueue(100 ether);
        uint id = accountingEngine.auctionDebt();
        cdpEngine.mint(address(this), 100 ether);

        debtAuctionHouse.decreaseSoldAmount(id, 0 ether, rad(100 ether));  // debt auction succeeds..

        assertTrue(!can_auctionSurplus() );
    }
    function test_multiple_increaseBidSize() public {
        popDebtFromQueue(100 ether);
        uint id = accountingEngine.auctionDebt();

        cdpEngine.mint(address(this), 100 ether);
        assertTrue(try_decreaseSoldAmount(id, 2 ether, rad(100 ether)));

        cdpEngine.mint(address(this), 100 ether);
        assertTrue(try_decreaseSoldAmount(id, 1 ether,  rad(100 ether)));
    }
}
