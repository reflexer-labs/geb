pragma solidity 0.6.7;


import "./mocks/StabilityFeeTreasuryMock.sol";

contract GeneralFuzz is StabilityFeeTreasuryMock {

   // --- Basic Setup ---
   constructor() public {
      address safe = address(new SAFEEngine());
      address coin = address(new CoinMock("Coin", "COIN", 99));
      address systemcoin = address(new CoinJoin(safe, coin));
      setUp(safe, address(2), systemcoin);
      
      // Authorizing Echidna Accounts
      authorizedAccounts[address(0x10000)] = 1;
      authorizedAccounts[address(0x20000)] = 1;
      authorizedAccounts[address(0xabc00)] = 1;

      safeEngine.approveSAFEModification(address(systemcoin));
      SAFEEngine(address(safeEngine)).createUnbackedDebt(address(0x10000), address(this), 2000000000000000000000000000000000 ether);
   }

   function depositUnbackedToTreasury(uint256 amount) public {
      SAFEEngine(address(safeEngine)).createUnbackedDebt(address(0x1), address(this), amount * RAY);
   }

   function depositCoinToTreasury(uint amount) public {
      CoinMock(address(systemCoin)).mint(address(this), amount);
   } 
}

contract StatefulFuzzBase {

   StabilityFeeTreasuryMock stabilityFeeTreasury;
   CoinMock coin;
   CoinJoin systemcoin;
   SAFEEngine safeEngine;
   address receiver = address(0x30000);
   address bob = address(0xf);


   // --- Tracking Variables ---
   // Tracks the previous time that the surplus was transferred
   uint256 previousSurplusTransferTime = 0;
   // Tracks weather the surplus has been transferred at least once
   uint256 surplusTransfersCount = 0;
   // tracker to check if contract has been initialized
   bool inited;

   //--- Helpers ---
   uint constant HUNDRED = 10 ** 2;
   uint constant RAY     = 10 ** 27;

   function _ray(uint wad) internal pure returns (uint) {
      return wad * 10 ** 9;
   }
   function _rad(uint wad) internal pure returns (uint) {
      return wad * RAY;
   }

      
   // --- SetUp ---
   modifier setUp() {
      if(!inited) baseSetup();
      _;
   }
   function baseSetup() internal {
      address safe_ = address(new SAFEEngine());
      address coin_ = address(new CoinMock("Coin", "COIN", 99));
      address systemcoin_ = address(new CoinJoin(safe_, coin_));
      stabilityFeeTreasury = new StabilityFeeTreasuryMock();
      stabilityFeeTreasury.setUp(safe_, msg.sender, systemcoin_);

      //Setting basic variables, otherwise echidna fails to initialize
      stabilityFeeTreasury.modifyParameters("minimumFundsRequired",0);
      stabilityFeeTreasury.modifyParameters("expensesMultiplier", 5 * HUNDRED);
      stabilityFeeTreasury.modifyParameters("treasuryCapacity", _rad(50 ether));
      stabilityFeeTreasury.modifyParameters("surplusTransferDelay", 10 minutes);

      inited = true;
   }


   //--- Base Echidna Tests ---
   function echidna_always_has_minimumFundsRequired() public setUp returns(bool) {
      return stabilityFeeTreasury.minimumFundsRequired() == 0 || safeEngine.coinBalance(address(stabilityFeeTreasury)) >= stabilityFeeTreasury.minimumFundsRequired();
   }

   function echidna_systemCoin_is_never_null() public setUp returns(bool) {
      return address(stabilityFeeTreasury.coinJoin()) != address(0);
   }

   function echidna_extraSurplusReceiver_is_never_null() public setUp returns(bool) {
      return stabilityFeeTreasury.extraSurplusReceiver() != address(0);
   }

   function echidna_surplus_transfer_interval_is_always_respected() public setUp returns(bool) {
      uint256 interval = stabilityFeeTreasury.latestSurplusTransferTime() - previousSurplusTransferTime;
      return surplusTransfersCount >= 2 || interval >= stabilityFeeTreasury.surplusTransferDelay();
   }

   function echidna_treasury_does_not_have_allowance() public setUp returns(bool) {
      (uint total, uint perBlock) = stabilityFeeTreasury.allowance(address(stabilityFeeTreasury));
      return total == 0 && perBlock == 0;
   }

   function echidna_contract_is_enabled() public setUp returns(bool) {
      return stabilityFeeTreasury.contractEnabled() == 1;
   }

   // --- Base Public Actions ---
   function pullFunds(address dstAccount, address token, uint256 wad) external setUp {
      stabilityFeeTreasury.pullFunds(dstAccount, token, wad);
   }
   function transferSurplusFunds() external setUp{
      //Update testing variables
      previousSurplusTransferTime = stabilityFeeTreasury.latestSurplusTransferTime();
      surplusTransfersCount++;
      // Execute function
      stabilityFeeTreasury.transferSurplusFunds();
   }

   function depositUnbackedToTreasury(uint256 amount) public setUp {
      safeEngine.createUnbackedDebt(bob, address(stabilityFeeTreasury), _rad(amount));
   }

   function depositCoinToTreasury(uint amount) public setUp {
      coin.mint(address(stabilityFeeTreasury), amount);
   } 
}


contract AllowanceFuzz is StatefulFuzzBase {

   bool sanity = true;

   // --- Allowance Actions ---
   function setTotalAllowance(address account, uint256 rad) external setUp {
      stabilityFeeTreasury.setTotalAllowance(account, rad);
   }

   function setPerBlockAllowance(address account, uint256 rad) external setUp {
      stabilityFeeTreasury.setPerBlockAllowance(account, rad);
   }

   function echidna_tt() public returns(bool) {
      return true;
   }

   function echidna_sanity() public returns(bool) {
      return sanity;
   }

   function echidna_inited() public setUp returns(bool) {
      return inited;
   }


}
