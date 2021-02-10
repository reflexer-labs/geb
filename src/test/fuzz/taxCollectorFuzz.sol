pragma solidity ^0.6.7;

pragma experimental ABIEncoderV2;

import "./mocks/TaxCollectorMock.sol";
import "./mocks/SignedSafeMath.sol";

contract SAFEEngineMock {
    uint debtAmount;
    uint accumulatedRate;
    uint _coinBalance;

    function collateralTypes(bytes32) virtual public view returns (
        uint256,       // [wad]
        uint256        // [ray]
    ) {
      return(debtAmount, accumulatedRate);
    }
    function updateAccumulatedRate(bytes32,address,int256) external {}
    function coinBalance(address) public view returns (uint) {
        return _coinBalance;
    }
    function fuzzSafeEngine(uint debt, uint rate, uint balance) public {
        debtAmount = debt;
        accumulatedRate = rate;
        _coinBalance = balance;

    }
}


// @notice Will auth fuzzer accounts to add/remove secondary receivers, as well as fuzzing safe parameters and remaining functions
contract StatefulFuzz is TaxCollectorMock {
    constructor() public
        TaxCollectorMock(
            address(new SAFEEngineMock())
        ){
            // authing accounts, authing them will also allow to modify parameters, add secondaryReceivers
            authorizedAccounts[address(0x10000)] = 1;
            authorizedAccounts[address(0x20000)] = 1;
            authorizedAccounts[address(0xabc00)] = 1;   

            maxSecondaryReceivers = 100;         
        }

    function fuzzSafeEngineParams(uint debtAmount, uint accumulatedRate, uint coinBalance) public {
        SAFEEngineMock(address(safeEngine)).fuzzSafeEngine(debtAmount, accumulatedRate, coinBalance);
    }

}