pragma solidity 0.6.7;

import "ds-test/test.sol";
import {DSDelegateToken} from "ds-token/delegate.sol";
import {TestSAFEEngine as SAFEEngine} from './SAFEEngine.t.sol';
import {DebtAuctionHouse as DAH} from './DebtAuctionHouse.t.sol';
import {AccountingEngine} from '../AccountingEngine.sol';

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract ValidSystemStakingPool {
    DSDelegateToken token;

    constructor(address token_) public {
        token = DSDelegateToken(token_);
    }

    function transferProtocolTokens(address receiver, uint256 amount) public {
        token.transferFrom(address(this), receiver, amount);
    }
    function canPrintProtocolTokens() public view returns (bool) {
        return (token.balanceOf(address(this)) == 0);
    }
}

contract RevertableSystemStakingPool {
    DSDelegateToken token;

    bool reverts;

    constructor(address token_) public {
        token = DSDelegateToken(token_);
    }

    function switchRevertMode() public {
        reverts = !reverts;
    }

    function transferProtocolTokens(address receiver, uint256 amount) public {
        token.transferFrom(address(this), receiver, amount);
    }
    function canPrintProtocolTokens() public view returns (bool) {
        if (reverts) revert("not-allowed-to-call");
        return true;
    }
}

contract MissingImplementationSystemStakingPool {
    DSDelegateToken token;

    constructor(address token_) public {
        token = DSDelegateToken(token_);
    }

    function transferProtocolTokens(address receiver, uint256 amount) public {
        token.transferFrom(address(this), receiver, amount);
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

contract StakingPoolIntegrationTest is DSTest {
    Hevm hevm;

    SAFEEngine safeEngine;
    AccountingEngine accountingEngine;
    DAH debtAuctionHouse;
    DSDelegateToken protocolToken;
    ProtocolTokenAuthority tokenAuthority;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine = new SAFEEngine();

        protocolToken  = new DSDelegateToken("", "");
        debtAuctionHouse = new DAH(address(safeEngine), address(protocolToken));

        accountingEngine = new AccountingEngine(
          address(safeEngine), address(0), address(debtAuctionHouse)
        );
        debtAuctionHouse.addAuthorization(address(accountingEngine));

        accountingEngine.modifyParameters("debtAuctionBidSize", rad(100 ether));
        accountingEngine.modifyParameters("initialDebtAuctionMintedTokens", 200 ether);

        safeEngine.approveSAFEModification(address(debtAuctionHouse));

        tokenAuthority = new ProtocolTokenAuthority();
        tokenAuthority.addAuthorization(address(debtAuctionHouse));

        accountingEngine.modifyParameters("protocolTokenAuthority", address(tokenAuthority));
        safeEngine.initializeCollateralType('');
    }

    uint constant ONE = 10 ** 27;
    function rad(uint wad) internal pure returns (uint) {
        return wad * ONE;
    }

    function createUnbackedDebt(address who, uint wad) internal {
        accountingEngine.pushDebtToQueue(rad(wad));
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
    function can_auction_debt() public returns (bool) {
        string memory sig = "auctionDebt()";
        bytes memory data = abi.encodeWithSignature(sig);

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", accountingEngine, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
    }

    function test_auction_debt_pool_not_set() public {
        popDebtFromQueue(100 ether);
        uint id = accountingEngine.auctionDebt();
    }
    function testFail_set_staking_pool_with_missing_implementation() public {
        MissingImplementationSystemStakingPool stakingPool = new MissingImplementationSystemStakingPool(address(protocolToken));
        accountingEngine.modifyParameters("systemStakingPool", address(stakingPool));
    }
    function test_revertable_staking_pool() public {
        RevertableSystemStakingPool stakingPool = new RevertableSystemStakingPool(address(protocolToken));
        accountingEngine.modifyParameters("systemStakingPool", address(stakingPool));

        popDebtFromQueue(100 ether);
        uint id = accountingEngine.auctionDebt();
        assertEq(id, 1);

        stakingPool.switchRevertMode();
        hevm.warp(now + 1);

        popDebtFromQueue(100 ether);
        id = accountingEngine.auctionDebt();
        assertEq(id, 2);
    }
    function testFail_valid_staking_pool_reverts_debt_auction() public {
        ValidSystemStakingPool stakingPool = new ValidSystemStakingPool(address(protocolToken));
        accountingEngine.modifyParameters("systemStakingPool", address(stakingPool));

        protocolToken.mint(address(stakingPool), 1);

        popDebtFromQueue(100 ether);
        assertTrue(!accountingEngine.canPrintProtocolTokens());
        uint id = accountingEngine.auctionDebt();
    }
    function test_valid_staking_pool_reverts_then_allows_debt_auction() public {
        ValidSystemStakingPool stakingPool = new ValidSystemStakingPool(address(protocolToken));
        accountingEngine.modifyParameters("systemStakingPool", address(stakingPool));

        protocolToken.mint(address(stakingPool), 1);

        popDebtFromQueue(100 ether);
        assertTrue(!accountingEngine.canPrintProtocolTokens());

        stakingPool.transferProtocolTokens(address(0x123), 1);
        assertTrue(accountingEngine.canPrintProtocolTokens());
        uint id = accountingEngine.auctionDebt();
        assertEq(id, 1);
    }
    function test_valid_staking_pool_allows_debt_auction() public {
        ValidSystemStakingPool stakingPool = new ValidSystemStakingPool(address(protocolToken));
        accountingEngine.modifyParameters("systemStakingPool", address(stakingPool));

        popDebtFromQueue(100 ether);
        uint id = accountingEngine.auctionDebt();
        assertEq(id, 1);
    }
}
