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


// @notice Fuzz the whole thing, assess the results to see if failures make sense
contract Fuzz is TaxCollectorMock {

    SignedSafeMath signedSafeMath;

    int256 constant private _INT256_MIN = -2**255;
    
    function rmul(uint256 x, uint256 y, uint256 b) internal pure returns (uint256 z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / b;
    }

    function rpowSolidity(uint x, uint n, uint b) internal pure returns (uint z) {
        z = n % 2 != 0 ? x : b;

        for (n /= 2; n != 0; n /= 2) {
            x = rmul(x, x, b);

            if (n % 2 != 0) {
                z = rmul(z, x, b);
            }
        }
    }

    constructor() public
        TaxCollectorMock(
            address(new SAFEEngineMock())
        ){
            signedSafeMath = new SignedSafeMath();
        }

    function fuzzSafeEngineParams(uint debtAmount, uint accumulatedRate, uint coinBalance) public {
        SAFEEngineMock(address(safeEngine)).fuzzSafeEngine(debtAmount, accumulatedRate, coinBalance);
    }

    function fuzz_rpow(uint x, uint n) public {
        assert(rpow(x, n, RAY) == rpowSolidity(x, n, RAY));

        // require(b>0); 
        // assert(rpow(x, n, b) == rpowSolidity(x, n, b)); will fail for lower b values.
    }

    function fuzzSignedSubtract(int x, int y) public {

        try signedSafeMath.subtract(x, y)
            returns (int _value)
        {
            assert(subtract(x, y) == _value);
        } catch {
            assert(subtract(x, y) == 1234); // should revert before the assertion, failing gracefully
        }
    }

    function fuzzSignedAddition(int x, int y) public {

        try signedSafeMath.addition(x, y)
            returns (int _value)
        {
            assert(addition(x, y) == _value);
        } catch {
            assert(addition(x, y) == 1234); // should revert before the assertion, failing gracefully
        }
    }

    function fuzzSignedMultiply(int x, int y) public {

        try signedSafeMath.multiply(x, y)
            returns (int _value)
        {
            assert(multiply(x, y) == _value);
        } catch {
            assert(multiply(x, y) == 1234); // should revert before the assertion, failing gracefully
        }
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


// @notice Fuzz rpow implementations only, will try to find the largest difference.
contract Rpow {
    uint256 constant RAY           = 10 ** 27;

    function rpow(uint256 x, uint256 n, uint256 b) internal pure returns (uint256 z) {
      assembly {
        switch x case 0 {switch n case 0 {z := b} default {z := 0}}
        default {
          switch mod(n, 2) case 0 { z := b } default { z := x }
          let half := div(b, 2)  // for rounding.
          for { n := div(n, 2) } n { n := div(n,2) } {
            let xx := mul(x, x)
            if iszero(eq(div(xx, x), x)) { revert(0,0) }
            let xxRound := add(xx, half)
            if lt(xxRound, xx) { revert(0,0) }
            x := div(xxRound, b)
            if mod(n,2) {
              let zx := mul(z, x)
              if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
              let zxRound := add(zx, half)
              if lt(zxRound, zx) { revert(0,0) }
              z := div(zxRound, b)
            }
          }
        }
      }
    }

    function rmul(uint256 x, uint256 y, uint256 b) internal pure returns (uint256 z) {
        z = x * y;
        require(y == 0 || z / y == x);
        z = z / b;
    }

    function rpowSolidity(uint x, uint n, uint b) internal pure returns (uint z) {
        z = n % 2 != 0 ? x : b;

        for (n /= 2; n != 0; n /= 2) {
            x = rmul(x, x, b);

            if (n % 2 != 0) {
                z = rmul(z, x, b);
            }
        }
    }

    function fuzz_rpow(uint x, uint n) public {
        assert(rpow(x, n, RAY) / 10 ** 15 == rpowSolidity(x, n, RAY) / 10 ** 15);
    }
}

