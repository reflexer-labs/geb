pragma solidity ^0.6.7;

import "./AccountingEngineMock.sol";
import {SettlementSurplusAuctioneer} from "../../single/SettlementSurplusAuctioneer.sol";
import "../../single/SAFEEngine.sol";
import "./DelegateTOkenMock.sol";
import "../../../lib/ds-token/lib/ds-test/src/test.sol";
// import '../../shared/BasicTokenAdapters.sol';
// import {TaxCollector} from '../../single/TaxCollector.sol';

contract AuctionHouseMock {
    uint public auctionsStarted;
    address public protocolToken = address(0x1);

    function startAuction(uint, uint) public returns (uint) {
        auctionsStarted++;
    }

    function startAuction(address, uint, uint) public returns (uint) {
        auctionsStarted++;
    }
}

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract SAFEEngineMock is SAFEEngine {
    uint256 constant RAY = 10 ** 27;

    constructor() public {}

    function mint(address usr, uint rad) public {
        coinBalance[usr] += rad;
        globalDebt += rad;
    }
    function balanceOf(address usr) public view returns (uint) {
        return uint(coinBalance[usr] / RAY);
    }

    function setDebt(address usr, uint rad) public {
        debtBalance[usr] = rad;
    }
}

contract Gem {
    mapping (address => uint256) public balanceOf;
    function mint(address usr, uint rad) public {
        balanceOf[usr] += rad;
    }
}

contract User {
    function popDebtFromQueue(address accountingEngine, uint timestamp) public {
        AccountingEngineMock(accountingEngine).popDebtFromQueue(timestamp);
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

// @notice Fuzz the whole thing, failures will show bounds (run with checkAsserts: on)
contract FuzzBounds is AccountingEngineMock {
    constructor() public AccountingEngineMock(
        address(new SAFEEngine()),
        address(new AuctionHouseMock()),
        address(new AuctionHouseMock())
    ) {}

}

// // @notice Fuzzing state changes
contract FuzzAccountingEngine is DSTest {
    Hevm hevm= Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    SAFEEngineMock safeEngine;
    AccountingEngineMock accountingEngine;
    AuctionHouseMock debtAuctionHouse;
    AuctionHouseMock surplusAuctionHouse;
    SettlementSurplusAuctioneer postSettlementSurplusDrain;
    Gem  protocolToken;
    ProtocolTokenAuthority tokenAuthority;

    uint[] debtQueueTimestamps;

    constructor() public {
        setUp();
    }

    function rad(uint wad) internal pure returns (uint) {
        return wad * 10**27;
    }

    function setUp() public {
        safeEngine = new SAFEEngineMock();

        protocolToken  = new Gem();
        debtAuctionHouse = new AuctionHouseMock();
        surplusAuctionHouse = new AuctionHouseMock();

        accountingEngine = new AccountingEngineMock(
          address(safeEngine), address(surplusAuctionHouse), address(debtAuctionHouse)
        );

        accountingEngine.modifyParameters("surplusAuctionAmountToSell", rad(100 ether));
        accountingEngine.modifyParameters("debtAuctionBidSize", rad(100 ether));
        accountingEngine.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);

        // safeEngine.approveSAFEModification(address(debtAuctionHouse));

        tokenAuthority = new ProtocolTokenAuthority();
        tokenAuthority.addAuthorization(address(debtAuctionHouse));

        accountingEngine.modifyParameters("protocolTokenAuthority", address(tokenAuthority));
    }

    // test with dapp tools
    function test_fuzz_setup2() public {
        createUnbackedDebt(1 ether);
        assertEq(safeEngine.debtBalance(address(accountingEngine)), 1 ether);

        mintCoinsToAccountingEngine(1 ether);
        assertEq(safeEngine.coinBalance(address(accountingEngine)), 1 ether);

        settleDebt(1 ether);
        assertEq(safeEngine.debtBalance(address(accountingEngine)), 0);
        assertEq(safeEngine.debtBalance(address(accountingEngine)), 0);

        pushDebtToQueue(1 ether);
        uint pushDebtTimestamp = now;
        hevm.warp(now + 1000);
        popDebtFromQueue(pushDebtTimestamp);

        createUnbackedDebt(rad(1000 ether));
        auctionDebt();
        cancelAuctionedDebtWithSurplus(rad(1 ether));

        mintCoinsToAccountingEngine(rad(1e6 ether));
        auctionSurplus();
    }

    // fuzzing params
    // accounting engine coin balance
    function mintCoinsToAccountingEngine(uint wad) public {
        safeEngine.mint(address(accountingEngine), wad);
    }

    // actions // will be called by the fuzzer to change state on the contracts
    // create unbacked debt
    function createUnbackedDebt(uint debt) public {
        safeEngine.createUnbackedDebt(address(accountingEngine), address(0x0), debt);
    }

    // push debt to queue, normally called by liquidationEngine
    function pushDebtToQueue(uint debtBlock) public {
        debtQueueTimestamps.push(now);
        uint previousDebtInSlot = accountingEngine.debtQueue(now);

        uint previousTotalQueuedDebt = accountingEngine.totalQueuedDebt();
        accountingEngine.pushDebtToQueue(debtBlock);

        assert(accountingEngine.debtQueue(now) == previousDebtInSlot + debtBlock);
        assert(accountingEngine.totalQueuedDebt() == previousTotalQueuedDebt + debtBlock);
    }

    // pop debt from queue // will pop one of the pushed debts, aiding the fuzzer so it does not have to guess timestamps
    function popDebtFromQueue(uint slot) public {
        if (debtQueueTimestamps.length == 0) return; // nothing to pop
        slot = slot % debtQueueTimestamps.length;
        accountingEngine.popDebtFromQueue(slot);

        assert(accountingEngine.debtPoppers(slot) == address(this));
        assert(accountingEngine.debtQueue(slot) == 0);
    }

    // settle debt
    function settleDebt(uint rad) public {
        uint prevDebtBalance = safeEngine.debtBalance(address(accountingEngine));
        uint prevCoinBalance = safeEngine.coinBalance(address(accountingEngine));

        accountingEngine.settleDebt(rad);

        assert(safeEngine.debtBalance(address(accountingEngine)) == prevDebtBalance - rad);
        assert(safeEngine.coinBalance(address(accountingEngine)) == prevCoinBalance - rad);
    }

    // auctionDebt
    function auctionDebt() public {
        uint previousDebt = unqueuedUnauctionedDebt();
        uint previousCoinBalance = safeEngine.coinBalance(address(accountingEngine));
        accountingEngine.auctionDebt();
        require(unqueuedUnauctionedDebt() == previousDebt - previousCoinBalance - accountingEngine.debtAuctionBidSize());
    }

    // cancelAuctionedDebtWithSurplus // called by the debt Auction house to settle debt
    function cancelAuctionedDebtWithSurplus(uint rad) public {
        if (debtAuctionHouse.auctionsStarted() > 0) return; // avoid just before the first auction
        uint previousDebt = unqueuedUnauctionedDebt();

        accountingEngine.cancelAuctionedDebtWithSurplus(rad);
        assert(previousDebt - rad == unqueuedUnauctionedDebt());
    }

    // auctionSurplus
    function auctionSurplus() public {
        if (safeEngine.coinBalance(address(accountingEngine)) > unqueuedUnauctionedDebt())
            accountingEngine.settleDebt(unqueuedUnauctionedDebt());

        uint previousCoinBalance = safeEngine.coinBalance(address(accountingEngine));
        accountingEngine.auctionSurplus();

        assert(previousCoinBalance == safeEngine.coinBalance(address(accountingEngine)));
    }


    // properties // will be tested for every call performed to actions/fuzzing functions above
    // unqueuedUnauctionedDebt
    function echidna_unqueuedUnauctionedDebt() public returns (bool) {
        if (unqueuedUnauctionedDebt() == 0) return true;
        return safeEngine.debtBalance(address(accountingEngine)) - accountingEngine.totalQueuedDebt() - accountingEngine.totalOnAuctionDebt() == unqueuedUnauctionedDebt();
    }

    function echidna_canPrintProtocolTokens() public returns (bool) {
        return accountingEngine.canPrintProtocolTokens();
    }

    function unqueuedUnauctionedDebt() public returns (uint) {
        try accountingEngine.unqueuedUnauctionedDebt() returns (uint rad) { // reverts if negative
            return rad;
        } catch {
            return 0;
        }
    }
}