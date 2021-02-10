# Security Tests

The contracts in this folder are the fuzz scripts for the GEB repository.

To run the fuzzer, set up Echidna (https://github.com/crytic/echidna) on your machine.

Then run
```
echidna-test src/test/fuzz/<name of file>.sol --contract <Name of contract> --config src/test/fuzz/echidna.yaml
```

Configs are in this folder (echidna.yaml). 

The contracts in this folder are modified versions of the originals in the _src_ folder. They have assertions added to test for invariants, visibility of functions modified. Running the Fuzz against modified versions without the assertions is still possible, general properties on the Fuzz contract can be executed against unmodified contracts.

Tests should be run one at a time because they interfere with each other.

For all contracts being fuzzed, we tested the following:

1. Fuzzing a plain version of the contract, to check for unexpected failures
2. Writing assertions and/or turning "requires" into "asserts" within the smart contract itself. This will cause echidna to fail fuzzing, and upon failures echidna finds the lowest value that causes the assertion to fail. This is useful to test bounds of functions (i.e.: modifying safeMath functions to assertions will cause echidna to fail on overflows, giving insight on the bounds acceptable). This is useful to find out when these functions revert. Although reverting will not impact the contract's state, it could cause a denial of service (or the contract not updating state when necessary and getting stuck). We check the found bounds against the expected usage of the system.
3. For contracts that have state (i.e.: the auction house below), we also force the contract into common states like setting up the contract with an auction open, and then let echidna fuzz through an auction. On some cases we auth the echidna accounts too.

Echidna will generate random values and call all functions failing either for violated assertions, or for properties (functions starting with echidna_) that return false. Sequence of calls is limited by seqLen in the config file. Calls are also spaced over time (both block number and timestamp) in random ways. Once the fuzzer finds a new execution path, it will explore it by trying execution with values close to the ones that opened the new path.

# Results

## LiquidationEngine

### 1. Plain code fuzz

Goal: Check for unexpected failures. Use contract GeneralFuzz.sol, with checkAsserts == true in echidna config.

```
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
```

#### Conclusion: No issues noted.

### SAFE Fuzz

This script will fuzz a modified version of the LiquidationEngine, including a mock SafeEngine. The modified version will fire an assertion on overflows, results aim to provide an insight on safe bounds for all calculations in the contract.

For this we will fuzz a safe state (collateral and debt, through the custom ```fuzzSafe(lockedCollateral, generatedDebt)``` function). The Safe Engine mock version will always return the fuzzed values (disregarding collateral type and safe address), enabling us to analyze the liquidation process with the fuzzed values (without modifying the liquidateSAFE function). Goal here is to find out when the calculation overflows (which would prevent liquidations from happening).

```
assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzSafe(129747088119375309651257358574,115953324830350971415744056541225015777259025135427)
liquidateSAFE("",0x0)

assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzSafe(2052681306273291383173695501788748492407539991603,116249465701150515206245782751373535662228471911304)
liquidateSAFE("",0x0)
````

If fuzzing both collateral and debt, values close to the ones above will overflow, the case that was mostly reduced is the following:
                         129,747,088,119.375309651257358574
115,953,324,830,350,971,415,744,056,541,225.015777259025135427

129 Trillion ETH, along with 11 * 10^31 System coin is the minimum case found.

We also tested fuzzing only debt, with: 1000 ETH collateral.

```
assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzSafe(1593573193211699743555714681088209368725398,115962318970534578672575213196172476289404989529599)
    liquidateSAFE("",0x0)

    value: 115,962,318,970,534,578,672,575,213,196,172.476289404989529599
````

#### Conclusion: ETH available on the market will alone prevent overflows in this case. Even with a large collateral balance in the SAFE (or if using a lower priced collateral in another system), the cRatio will prevent overflows.

### Collateral Parameters Fuzz 

In this case we fuzz collateral parameters (function fuzzCollateral(debtAmount, accumulatedRate, safetyPrice, debtCeiling, liquidationPrice)), starting with fuzzing all of them, then focusing on sore spots, or parameters that could be the largest in real world scenarios. 

```
assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzCollateral(450992486657743016140264857026696769110506126496,1163589619993600885897239347144712372885483871469250752242,141717857058841484220302860016620462197477603704226775,0,0)
liquidateSAFE("",0x0)
````
This one failed because it set the debt ceiling and liquidation price to zero. Not very meaningful resulsts, since safetyPrice, debtCeiling and liquidationPrice are governance set, so we set them to near real workd value and broke it down by fuzzing only the values tha fluctuate from system usage: debtAmount and accumulatedRate.
```
fuzzCollateral(20322495390052294381148718653546535.671555256555527115,
    1158205436519173868301519626380.878836493514036996143978012) // wad, ray
liquidateSAFE("",0x0)
```
Only accumulatedRate, debtAmount set to 10mm:
```
assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzCollateral(1161411429974471145367254032213.244706580012183533262350610) // ray
    liquidateSAFE("",0x0)


assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzCollateral(1157997639923822943907917210751.064349855217408082103205029)
    liquidateSAFE("",0x0)

assertion in liquidateSAFE: failed!💥  
  Call sequence:
    fuzzCollateral(1158823425568521744927601028838.920837023251549674080992876)
    liquidateSAFE("",0x0)
```
Drilling further down, will check for each operation what are the minimum values that will cause an overflow:
amountToRaise:
```
assertion in fuzzAmountToRaise: failed!💥  
  Call sequence:
    fuzzAmountToRaise(115867312542273104931626618209252766)
```
For 1000000 Coin adjustedDebt, an accumulatedRate of 115867312.542273104931626618209252766 will cause an overflow, or 115 trillion system coins.

#### Conclusion: Overflows are unlikely, as the accumulatedRate above is unlikely to happen.


## FixedDiscountCollateralAuctionHouse

### Plain code fuzz
```
src/test/fuzz/fixedDiscountAuctionHouseFuzz.sol --contract GeneralFuzz  --config src/test/fuzz/echidna.yaml
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
```

Some of the getters overflow, as follows:

- getSystemCoinCeilingDeviatedPrice(116616512653811068243793757584434900370453896993835906454488): Overflows with a redemptionPrice of 116616512653811.068243793757584434900370453896993835906454488
 - getDiscountedCollateralPrice(29047792149950914941998691223,22820851174,1,4476306840354875696171)
 - getFinalBaseCollateralPrice(110376586915668636906989437976525516029949870719869704441644,22363478170431731215097728616756635465877599049678556111609)
 - getSystemCoinFloorDeviatedPrice(116038250365304167291688789558538801178441247388656827831822)
 - 116038250365304.167291688789558538801178441247388656827831822


### Conclusion: Bounds are reasonable considering ETH as a collateral and the RAI starting price of 3.14

### Fuzz Bids

In this case we setup an auction and let echidna fuzz the whole contract with three users. Users have an unlimited balance, and will basically settle the auction in multiple ways.

Here we are not looking for bounds, but instead checking the properties that either should remain constant, or that move as the auction evolves:

- auctionDeadline
- raisedAmount
- soldAmount
- Coins removed from auction on liquidationEngine
- amountToRaise
- amountToSell
- collateralType
- minimumBid
- lastReadRedemptionPrice
- lowerSystemCoinMedianDeviation
- upperSystemCoinMedianDeviation
- lowerCollateralMedianDeviation
- upperCollateralMedianDeviation
- discount
- minSystemCoinMedianDeviation

We also validate the token flows in and out of the auction contract.

These properties are verified in between all calls.

A function to aid the fuzzer to bid in the correct auction was also created (function bid in fuzz contract). It forces a valid bid on the auction. The fuzzer does find it's way to the correct auction/bid amounts, but enabling this function will increase it's effectiveness. To test without the aid function turn it's visibility to internal.

```
echidna_collateralType: passed! 🎉
echidna_minimumBid: passed! 🎉
echidna_lowerSystemCoinMedianDeviation: passed! 🎉
echidna_lastReadRedemptionPrice: passed! 🎉
echidna_bids: passed! 🎉
echidna_auctionsStarted: passed! 🎉
echidna_upperSystemCoinMedianDeviation: passed! 🎉
echidna_lowerCollateralMedianDeviation: passed! 🎉
echidna_upperCollateralMedianDeviation: passed! 🎉
echidna_discount: passed! 🎉
echidna_minSystemCoinMedianDeviation: passed! 🎉
```

#### Conclusion: No exceptions found.


### Auctions and bids

In this case we auth the fuzzer users, and let them both create auctions and bid on them. In this case there is also an aid function (bid) that will bid in one of the created auctions (settled or unsettled).

FOr these cases a high seqLen is recommended, 500 was used for this run. (This means that for every instance of the contract the fuzzer will try a sequence of 500 txs).

Turn the modifyParameters(bytes32,address) to internal to run this case (as it will prevent the fuzzer to change oracle and accountingEngine addresses), and do the same with terminateAuctionPrematurely, or the fuzzer will terminate auctions randomly.

We set the following properties for this case:
- colateralType
- lastReadRedemptionPrice
- raisedAmount
- soldAmount

We also check if the token flows are acceptable.
```
echidna_collateralType: passed! 🎉
echidna_lastReadRedemptionPrice: passed! 🎉
echidna_bids: passed! 🎉
```

#### Conclusion: No exceptions found.

## TaxCollector

### Overflows
```
Analyzing contract: /Users/fabio/Documents/reflexer/geb/src/test/fuzz/taxCollectorFuzz.sol:Fuzz
assertion in secondaryReceiverAccounts: passed! 🎉
assertion in latestSecondaryReceiver: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in taxManyOutcome: passed! 🎉
assertion in collateralList: failed!💥  
  Call sequence:
    collateralList(0)

assertion in addAuthorization: passed! 🎉
assertion in globalStabilityFee: passed! 🎉
assertion in primaryTaxReceiver: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in isSecondaryReceiver: passed! 🎉
assertion in initializeCollateralType: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in safeEngine: passed! 🎉
assertion in taxSingle: failed!💥  
  Call sequence:
    fuzzSafeEngineParams(0,579174376706775911274800714463840417781295696008,0)
    taxSingle("")

assertion in fuzzSafeEngineParams: passed! 🎉
assertion in secondaryTaxReceivers: passed! 🎉
assertion in removeAuthorization: passed! 🎉
assertion in secondaryReceiverNonce: passed! 🎉
assertion in collateralListLength: passed! 🎉
assertion in secondaryReceiversAmount: passed! 🎉
assertion in collectedManyTax: passed! 🎉
assertion in secondaryReceiverRevenueSources: passed! 🎉
assertion in collateralTypes: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in secondaryReceiverAllotedTax: passed! 🎉
assertion in taxSingleOutcome: failed!💥  
  Call sequence:
    taxSingle("")
    fuzzSafeEngineParams(0,115803778915825364049908770267911937638550693697789,0)
    taxSingleOutcome("")

assertion in usedSecondaryReceiver: passed! 🎉
assertion in taxMany: passed! 🎉
assertion in maxSecondaryReceivers: passed! 🎉
assertion in modifyParameters: passed! 🎉

Unique instructions: 4901
Unique codehashes: 2
Seed: -8725941163565682918
```

Failures in taxSingle:
fuzzSafeEngineParams(0,579174376706775911274800714463840417781295696008,0)

accumulatedRate of 579174376706775911274.800714463840417781295696008

Failure in taxSingleOutcome:
    taxSingle("")
    fuzzSafeEngineParams(0,115803778915825364049908770267911937638550693697789,0)
    taxSingleOutcome("")

accumulatedRate of 
1158037789158253640499087.702679119376385506936977895

#### Conclusion: Overflows are unlikely, as the accumulatedRate above is unlikely to happen.

### Math

#### rPow

We implemented the rPow function in Solidity, and rounding seem to be off a bit (results lack precision).

We first tested with base fixed at RAY (as it's used in production), and it failed with:

```
assertion in fuzz_rpow: failed!💥  
  Call sequence:
    fuzz_rpow(1000000000000000000000000001,1000000000000000000000000001)
````

The call above produces slightly different results: 
```
{
	"0": "uint256: sol 2718281828458957297665721793",
	"1": "uint256: asm 2718281828458990744961643954"
}
```
or on another examples
```
{
	"0": "uint256: sol 367879441171430420341698821",
	"1": "uint256: asm 367879441171434947308084559"
}

{
	"0": "uint256: sol 1174559060629581930499137600391251418047665",
	"1": "uint256: asm 1174559060629581930499137600401997209333852"
}
```

In taxCollector's context, rpow is used to multiply globalStabilityFee + collateralStabilityFee and the delta between now and the  last update for the collateral.

- stabilityFee (ray%): 1000.000000000000000000000001
- time since last update (seconds): 1000000000000000000000000001, 10055109076 years

We also tested how different are the results, and determined it affects the last 15 digits of the result. (results in RAY, contract Rpow).

#### Conclusion: As seen, implementations slightly differ in the results. This is likely due to how the solidity version is being compiled. This affects only precision after the last 15 digits of the result (result in RAY, so just a minor practical difference). Conclusion is we should maintain the current implementation, due to it being battletested on MCD and 1inch contracts. 

#### SignedMath
We checked the other signed math functions in the contract:
```
assertion in fuzzSignedSubtract: passed! 🎉
assertion in fuzzSignedAddition: passed! 🎉
assertion in fuzzSignedMultiply: failed!💥  
  Call sequence:
    fuzz_rpow(-1,-57896044618658097711785492504343953926634992332820282019728792003956564819968)
````

the Multiply (int,int) function needs to be updated to check for the edge case above (a=-1, b=minInt256).

#### Conclusion: Fixed in commit 422210bd509b15e60c2cd9f6b5615c5fc99935d8.

### SecondaryReceivers

We will auth the fuzzer accounts in the contract, so they can add/remove secondary receivers and initialize collateral (and reach the parts of the code that require these). This test is best run with a high seqLen.

```
Analyzing contract: /Users/fabio/Documents/reflexer/geb/src/test/fuzz/taxCollectorFuzz.sol:StatefulFuzz
assertion in secondaryReceiverAccounts: passed! 🎉
assertion in latestSecondaryReceiver: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in taxManyOutcome: failed!💥  
  Call sequence:
    initializeCollateralType("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL")
    fuzzSafeEngineParams(0,116722783967983422816141205997215843014688047892712,0)
    initializeCollateralType("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\142") Time delay: 0x1 Block delay: 0x1
    taxManyOutcome(0,0)

assertion in collateralList: failed!💥  
  Call sequence:
    collateralList(0)

assertion in addAuthorization: passed! 🎉
assertion in globalStabilityFee: passed! 🎉
assertion in primaryTaxReceiver: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in isSecondaryReceiver: passed! 🎉
assertion in initializeCollateralType: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in safeEngine: passed! 🎉
assertion in taxSingle: failed!💥  
  Call sequence:
    fuzzSafeEngineParams(24156297535047651174260027428945694198,2440833663884588063980026454756096814604,4055979757487036252849098407008606829)
    taxSingle("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL")

assertion in fuzzSafeEngineParams: passed! 🎉
assertion in secondaryTaxReceivers: passed! 🎉
assertion in removeAuthorization: passed! 🎉
assertion in secondaryReceiverNonce: passed! 🎉
assertion in collateralListLength: passed! 🎉
assertion in secondaryReceiversAmount: passed! 🎉
assertion in collectedManyTax: passed! 🎉
assertion in secondaryReceiverRevenueSources: passed! 🎉
assertion in collateralTypes: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in secondaryReceiverAllotedTax: passed! 🎉
assertion in taxSingleOutcome: failed!💥  
  Call sequence:
    fuzzSafeEngineParams(32009589394515823170620614171415115802900314972004807949104927289202285711,58127098963045144785531823126094668709999337501291827457972926705886648852901,5855237267068563497038537319648564433479856848423069762335917477095656913)
    taxSingleOutcome("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL")

assertion in usedSecondaryReceiver: passed! 🎉
assertion in taxMany: failed!💥  
  Call sequence:
    initializeCollateralType("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL")
    fuzzSafeEngineParams(0,115796792157171934533363076104241853622385144458508,247122978102071542620845283503554896831987181594491) Time delay: 0x1 Block delay: 0x1
    taxMany(0,0)

assertion in maxSecondaryReceivers: passed! 🎉
assertion in modifyParameters: passed! 🎉

Unique instructions: 8647
Unique codehashes: 2
Seed: 4704021613944476058

```
Failure in taxManyOutcome:
assertion in taxManyOutcome: failed!💥  
  Call sequence:
    initializeCollateralType("")
    fuzzSafeEngineParams(0,116722783967983422816141205997215843014688047892712,0)
    initializeCollateralType("142") Time delay: 0x1 Block delay: 0x1
    taxManyOutcome(0,0)
    
TaxManyOutcome will call taxSingle (below), it failed due to an incorrect period (as expected).
    

Failure in taxSingle:
assertion in taxSingle: failed!💥  
  Call sequence:
    fuzzSafeEngineParams(24156297535047651174260027428945694198,2440833663884588063980026454756096814604,4055979757487036252849098407008606829)
    taxSingle("")

debtAmount (wad):  24156297535047651174.260027428945694198
accumulatedRate (ray): 2440833663884.588063980026454756096814604
coiBalance (rad): .000000004055979757487036252849098407008606829

failure in taxSingleOutcome:
assertion in taxSingleOutcome: failed!💥  
  Call sequence:
    fuzzSafeEngineParams(32009589394515823170620614171415115802900314972004807949104927289202285711,58127098963045144785531823126094668709999337501291827457972926705886648852901,5855237267068563497038537319648564433479856848423069762335917477095656913)
    taxSingleOutcome("")

debtAmount (wad): 32009589394515823170620614171415115802900314972004807949.104927289202285711
accumulatedRate (ray): 58127098963045144785531823126094668709999337501291.827457972926705886648852901
coiBalance (rad): 585523726706856349703853731.9648564433479856848423069762335917477095656913

failure in taxMany:
assertion in taxMany: failed!💥  
  Call sequence:
    initializeCollateralType("")
    fuzzSafeEngineParams(0,115796792157171934533363076104241853622385144458508,247122978102071542620845283503554896831987181594491) Time delay: 0x1 Block delay: 0x1
    taxMany(0,0)
    
Failing because of incorrect period, it actually calls taxSingle (tested above) within execution.

#### Conclusion: We reached different limits on this test, but still all bounds are unlikely to happen (limited by debtAmount, the coin totalSupply and reasonableness of the accumulatedRate)

