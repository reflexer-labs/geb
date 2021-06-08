pragma solidity 0.6.7;


import "./mocks/StabilityFeeTreasureMock.sol";

contract GeneralFuzz is StabilityFeeTreasuryMock {

   // --- Basic Setup ---
   constructor() public {
      address s = address(new SAFEEngine());
      address c = address(new Coin("Coin", "COIN", 99));
      address sc = address(new CoinJoin(s, c));
      setUp(s, address(2), sc);
   }
}