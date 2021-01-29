pragma solidity ^0.6.7;

pragma experimental ABIEncoderV2;

// import "../../../lib/ds-token/src/delegate.sol";

import {SAFEEngine} from '../../SAFEEngine.sol';
import {AccountingEngine} from '../../AccountingEngine.sol';
import {TaxCollector} from '../../TaxCollector.sol';
import {BasicCollateralJoin, ETHJoin, CoinJoin} from '../../BasicTokenAdapters.sol';

import {EnglishCollateralAuctionHouse} from '../../CollateralAuctionHouse.sol';
import {DebtAuctionHouse} from '../../DebtAuctionHouse.sol';
import {PostSettlementSurplusAuctionHouse} from '../../SurplusAuctionHouse.sol';

import "./mocks/LiquidationEngineMock.sol";


// @notice Fuzz the whole thing, assess the results to see if failures make sense
contract GeneralFuzz is LiquidationEngineMock {

    constructor() public
        LiquidationEngineMock(
            address(0x1)
        ){}
}

// @notice Fuzz arithmetic operations to find their bounds, 
contract FuzzMath is LiquidationEngineMock {

    constructor() public
        LiquidationEngineMock(
            address(new SafeEngineMock())
        ){

        }

    // change visibility to internal to prevent modifying functions from running
    function fuzzSafe(uint lockedCollateral, uint generatedDebt) internal {
        safeEngine.modifySafe(lockedCollateral, generatedDebt);
    }

    // change visibility to internal to prevent modifying functions from running
    function fuzzCollateral(
        // uint debtAmount,
        uint accumulatedRate
        // uint safetyPrice,
        // uint debtCeiling,
        // uint liquidationPrice
    ) public {
        safeEngine.modifyCollateral(
            // debtAmount,
            accumulatedRate
            // safetyPrice,
            // debtCeiling,
            // liquidationPrice            
        );
    }

    function fuzzAmountToRaise(uint accumulatedRate) public returns (uint) {
        return multiply(multiply(100000 ether, accumulatedRate), 1 ether) / WAD;
    }
}

