# Security Tests

The contracts in this folder are the fuzz and symbolic execution scripts for the rolling distribution incentives contract.

## Fuzz

To run the fuzzer, set up Echidna (https://github.com/crytic/echidna) on your machine.

Then run
```
echidna-test src/test/fuzz/<name of file>.sol --contract <Name of contract> --config src/test/fuzz/echidna.yaml
```

Configs are in this folder (echidna.yaml). 

The contracts in this folder are modified versions of the originals in the _src_ folder. They have assertions added to test for invariants, visibility of functions modified. Running the Fuzz against modified versions without the assertions is still possible, general properties on the Fuzz contract can be executed against unmodified contracts.

Tests were run one at a time because they interfere with each other.

## LiquidationEngine

### General fuzz

Goal: Check for unexpected failures. Use contract GeneralFuzz.sol, with checkAsserts == true in echidna config.
Analyzing contract: /Users/fabio/Documents/reflexer/geb/src/test/fuzz/liquidationEngineFuzz.sol:GeneralFuzz
assertion in getLimitAdjustedDebtToCover: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in chosenSAFESaviour: passed! 🎉
assertion in onAuctionSystemCoinLimit: passed! 🎉
assertion in removeCoinsFromAuction: passed! 🎉
assertion in addAuthorization: passed! 🎉
assertion in protectSAFE: passed! 🎉
assertion in currentOnAuctionSystemCoins: passed! 🎉
assertion in contractEnabled: passed! 🎉
assertion in mutex: passed! 🎉
assertion in liquidateSAFE: passed! 🎉
assertion in disconnectSAFESaviour: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in safeSaviours: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in safeEngine: passed! 🎉
assertion in disableContract: passed! 🎉
assertion in removeAuthorization: passed! 🎉
assertion in connectSAFESaviour: passed! 🎉
assertion in accountingEngine: passed! 🎉
assertion in collateralTypes: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in modifyParameters: passed! 🎉

Unique instructions: 2037
Unique codehashes: 1
Seed: -1285543104051193671

### Overflow Fuzz

This script will fuzz a modified version of the LiquidationEngine, including a mock SafeEngine. The modified version will fire an assertion on overflows, results aim to provide an insight on safe bounds for all calculations in the contract.

For this we will fuzz both a safe state (collateral and debt), as well as collateral parameters.

assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzSafe(129747088119375309651257358574,115953324830350971415744056541225015777259025135427)
    liquidateSAFE("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL",0x0)

assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzSafe(2052681306273291383173695501788748492407539991603,116249465701150515206245782751373535662228471911304)
    liquidateSAFE("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL",0x0)

If fuzzingboth collateral and debt, values close to the ones above will overflow, the case that was mostly reduced is the following:
                         129747088119.375309651257358574 
    115953324830350971415744056541225.015777259025135427 

We also tested fuzzing only debt, with: 1000 ETH collateral.

assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzSafe(1593573193211699743555714681088209368725398,115962318970534578672575213196172476289404989529599)
    liquidateSAFE("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL",0x0)

    value: 115962318970534578672575213196172.476289404989529599

### Conclusion: ETH and RAI balances turn overflows highly unlikely.

Fuzzing collateral parameters. 

assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzCollateral(450992486657743016140264857026696769110506126496,1163589619993600885897239347144712372885483871469250752242,141717857058841484220302860016620462197477603704226775,0,0)
    liquidateSAFE("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL",0x0)

Breaking it down:
Fuzzing only debtAmount and accumulatedRate
  Call sequence:
    fuzzCollateral(20322495390052294381148718653546535.671555256555527115,
    1158205436519173868301519626380.878836493514036996143978012) // wad, ray
    liquidateSAFE("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL",0x0)

Only accumulatedRate, debtAmount set to 10mm:
assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzCollateral(1161411429974471145367254032213.244706580012183533262350610) // ray
    liquidateSAFE("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL",0x0)

### Conclusion: Overflows are unlikely, as the accumulatedRate above is very unlikely to happen.

assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzCollateral(1157997639923822943907917210751.064349855217408082103205029)
    liquidateSAFE("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL",0x0)

assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzCollateral(1158823425568521744927601028838.920837023251549674080992876)
    liquidateSAFE("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL",0x0)

Drilling further down, will check for each operation what are the minimum values that will cause an overflow:
amountToRaise:

assertion in fuzzAmountToRaise: failed!💥  
  Call sequence:
    fuzzAmountToRaise(115867312542273104931626618209252766)

For 1000000 Coin adjustedDebt, an accumulatedRate of 115867312.542273104931626618209252766 will cause an overflow, or 115 trillion (USD?) value being auctioned.

Mainnet demo accumulatedRate 1.003780882956070313962213806

### Conclusion: Overflows are unlikely, as the accumulatedRate above is very unlikely to happen.


## LiquidationEngine

### General fuzz

Unique instructions: 1895
Unique codehashes: 1
Seed: 8581679829532695371
13:34:50 geb $ echidna-test src/test/fuzz/fixedDiscountAuctionHouseFuzz.sol --contract GeneralFuzz  --config src/test/fuzz/echidna.yaml
Analyzing contract: /Users/fabio/Documents/reflexer/geb/src/test/fuzz/fixedDiscountAuctionHouseFuzz.sol:GeneralFuzz
assertion in getCollateralMedianPrice: passed! 🎉
assertion in upperSystemCoinMedianDeviation: passed! 🎉
assertion in AUCTION_HOUSE_TYPE: passed! 🎉
assertion in lowerCollateralMedianDeviation: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in startAuction: passed! 🎉
assertion in settleAuction: passed! 🎉
assertion in lastReadRedemptionPrice: passed! 🎉
assertion in AUCTION_TYPE: passed! 🎉
assertion in addAuthorization: passed! 🎉
assertion in getCollateralBought: passed! 🎉
assertion in getSystemCoinMarketPrice: passed! 🎉
assertion in bids: passed! 🎉
assertion in liquidationEngine: passed! 🎉
assertion in upperCollateralMedianDeviation: passed! 🎉
assertion in lowerSystemCoinMedianDeviation: passed! 🎉
assertion in forgoneCollateralReceiver: passed! 🎉
assertion in getAdjustedBid: passed! 🎉
assertion in bidAmount: passed! 🎉
assertion in getSystemCoinCeilingDeviatedPrice: failed!💥  
  Call sequence:
    getSystemCoinCeilingDeviatedPrice(116616512653811068243793757584434900370453896993835906454488)

assertion in oracleRelayer: passed! 🎉
assertion in buyCollateral: passed! 🎉
assertion in auctionsStarted: passed! 🎉
assertion in amountToRaise: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in safeEngine: passed! 🎉
assertion in discount: passed! 🎉
assertion in totalAuctionLength: passed! 🎉
assertion in raisedAmount: passed! 🎉
assertion in getDiscountedCollateralPrice: failed!💥  
  Call sequence:
    getDiscountedCollateralPrice(29047792149950914941998691223,22820851174,1,4476306840354875696171)

assertion in getApproximateCollateralBought: passed! 🎉
assertion in terminateAuctionPrematurely: passed! 🎉
assertion in removeAuthorization: passed! 🎉
assertion in minSystemCoinMedianDeviation: passed! 🎉
assertion in getCollateralFSMAndFinalSystemCoinPrices: passed! 🎉
assertion in getFinalBaseCollateralPrice: failed!💥  
  Call sequence:
    getFinalBaseCollateralPrice(110376586915668636906989437976525516029949870719869704441644,22363478170431731215097728616756635465877599049678556111609)

assertion in minimumBid: passed! 🎉
assertion in systemCoinOracle: passed! 🎉
assertion in collateralType: passed! 🎉
assertion in remainingAmountToSell: passed! 🎉
assertion in collateralFSM: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in getSystemCoinFloorDeviatedPrice: failed!💥  
  Call sequence:
    getSystemCoinFloorDeviatedPrice(116038250365304167291688789558538801178441247388656827831822)

### Conclusion: Pending, check bounds

### Fuzz Bids

Will setup an auction, and allow echidna accounts to bid, checking for the following properties:



### Auctions and bids

Will allow echidna accounts to initiate auctions and bid, checking for the following properties:





