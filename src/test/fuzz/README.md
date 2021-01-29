# Security Tests

The contracts in this folder are the fuzz and symbolic execution scripts for the rolling distribution incentives contract.

## Fuzz

To run the fuzzer, set up Echidna (https://github.com/crytic/echidna) on your machine.

Then run
```
echidna-test src/test/fuzz/<name of file>.sol --contract <Name of contract> --config src/test/fuzz/echidna.yaml
```

Configs are in this folder (echidna.yaml). You can set the number of and depth of runs, number of total runs and 

The contracts in this folder are modified versions of the originals in the _src_ folder. They have assertions added to test for invariants, visibility of functions modified. Running the Fuzz against modified versions without the assertions is still possible, general properties on the Fuzz contract can be executed against unmodified contracts.

Tests should only run one at a time because they interfere with each other.

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

Conclusion: ETH and RAI balances turn overflows highly unlikely.

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

    Conclusion: tbd, check possible bounds

assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzCollateral(1157997639923822943907917210751064349855217408082103205029)
    liquidateSAFE("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL",0x0)

assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzCollateral(1158823425568521744927601028838920837023251549674080992876)
    liquidateSAFE("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL",0x0)

Drilling further down, will check for each operation what are the minimum values that will cause an overflow:
amountToRaise:

assertion in fuzzAmountToRaise: failed!💥  
  Call sequence:
    fuzzAmountToRaise(115867312542273104931626618209252766)

For 1000000 Coin adjustedDebt, an accumulatedRate of 115867312.542273104931626618209252766 will cause an overflow

