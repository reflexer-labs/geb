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

Echidna will generate random values and call all functions failing either for violated assertions, or for properties (functions starting with echidna\_) that return false. Sequence of calls is limited by seqLen in the config file. Calls are also spaced over time (both block number and timestamp) in random ways. Once the fuzzer finds a new execution path, it will explore it by trying execution with values close to the ones that opened the new path.

# Results

## LiquidationEngine

### 1. Plain code fuzz

Goal: Check for unexpected failures. Use contract GeneralFuzz.sol, in echidna config.

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

For this we will fuzz a safe state (collateral and debt, through the custom `fuzzSafe(lockedCollateral, generatedDebt)` function). The Safe Engine mock version will always return the fuzzed values (disregarding collateral type and safe address), enabling us to analyze the liquidation process with the fuzzed values (without modifying the liquidateSAFE function). Goal here is to find out when the calculation overflows (which would prevent liquidations from happening).

```
assertion in liquidateSAFE: failed!💥
  Call sequence:
    fuzzSafe(129747088119375309651257358574,115953324830350971415744056541225015777259025135427)
liquidateSAFE("",0x0)

assertion in liquidateSAFE: failed!💥
  Call sequence:
    fuzzSafe(2052681306273291383173695501788748492407539991603,116249465701150515206245782751373535662228471911304)
liquidateSAFE("",0x0)
```

If fuzzing both collateral and debt, values close to the ones above will overflow, the case that was mostly reduced is the following:
129,747,088,119.375309651257358574
115,953,324,830,350,971,415,744,056,541,225.015777259025135427

129 Trillion ETH, along with 11 \* 10^31 System coin is the minimum case found.

We also tested fuzzing only debt, with: 1000 ETH collateral.

```
assertion in liquidateSAFE: failed!💥
  Call sequence:
    fuzzSafe(1593573193211699743555714681088209368725398,115962318970534578672575213196172476289404989529599)
    liquidateSAFE("",0x0)

    value: 115,962,318,970,534,578,672,575,213,196,172.476289404989529599
```

#### Conclusion: ETH available on the market will alone prevent overflows in this case. Even with a large collateral balance in the SAFE (or if using a lower priced collateral in another system), the cRatio will prevent overflows.

### Collateral Parameters Fuzz

In this case we fuzz collateral parameters (function fuzzCollateral(debtAmount, accumulatedRate, safetyPrice, debtCeiling, liquidationPrice)), starting with fuzzing all of them, then focusing on sore spots, or parameters that could be the largest in real world scenarios.

```
assertion in liquidateSAFE: failed!💥
  Call sequence:
    fuzzCollateral(450992486657743016140264857026696769110506126496,1163589619993600885897239347144712372885483871469250752242,141717857058841484220302860016620462197477603704226775,0,0)
liquidateSAFE("",0x0)
```

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

-   getSystemCoinCeilingDeviatedPrice(116616512653811068243793757584434900370453896993835906454488): Overflows with a redemptionPrice of 116616512653811.068243793757584434900370453896993835906454488
-   getDiscountedCollateralPrice(29047792149950914941998691223,22820851174,1,4476306840354875696171)
-   getFinalBaseCollateralPrice(110376586915668636906989437976525516029949870719869704441644,22363478170431731215097728616756635465877599049678556111609)
-   getSystemCoinFloorDeviatedPrice(116038250365304167291688789558538801178441247388656827831822)
-   116038250365304.167291688789558538801178441247388656827831822

### Conclusion: Bounds are reasonable considering ETH as a collateral and the RAI starting price of 3.14

### Fuzz Bids

In this case we setup an auction and let echidna fuzz the whole contract with three users. Users have an unlimited balance, and will basically settle the auction in multiple ways.

Here we are not looking for bounds, but instead checking the properties that either should remain constant, or that move as the auction evolves:

-   auctionDeadline
-   raisedAmount
-   soldAmount
-   Coins removed from auction on liquidationEngine
-   amountToRaise
-   amountToSell
-   collateralType
-   minimumBid
-   lastReadRedemptionPrice
-   lowerSystemCoinMedianDeviation
-   upperSystemCoinMedianDeviation
-   lowerCollateralMedianDeviation
-   upperCollateralMedianDeviation
-   discount
-   minSystemCoinMedianDeviation

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

-   colateralType
-   lastReadRedemptionPrice
-   raisedAmount
-   soldAmount

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
```

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

In taxCollector's context, rpow is used to multiply globalStabilityFee + collateralStabilityFee and the delta between now and the last update for the collateral.

-   stabilityFee (ray%): 1000.000000000000000000000001
-   time since last update (seconds): 1000000000000000000000000001, 10055109076 years

We also tested how different are the results, and determined it affects the last 15 digits of the result. (results in RAY, contract Rpow).

#### Conclusion: As seen, implementations slightly differ in the results. This is due to the rounding scheme implemented in the assembly version (results in slightly lower results). This affects only precision after the last 15 digits of the result (result in RAY, so just a minor practical difference). Conclusion is we should maintain the current implementation, due to it being battletested on MCD and 1inch contracts.

#### Update: We updated the Solidity function to implement the same rounding scheme as the one used in the production assembly version, and got the same exact results (contract Rpow).

#### SignedMath

We checked the other signed math functions in the contract:

```
assertion in fuzzSignedSubtract: passed! 🎉
assertion in fuzzSignedAddition: passed! 🎉
assertion in fuzzSignedMultiply: failed!💥
  Call sequence:
    fuzz_rpow(-1,-57896044618658097711785492504343953926634992332820282019728792003956564819968)
```

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

debtAmount (wad): 24156297535047651174.260027428945694198
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

## StabilityFeeTreasury

### 1. Plain code fuzz

Goal: Check for simple math boundaries by changing the math section of the code to include assertions instead of requires and by removing some of the allowances requirements. The systemCoin was modified to give funds to whoever is trying to transfer. Run with checkAsserts turned on.

Results:

```
assertion in pullFunds: failed!💥
  Call sequence:
    pullFunds(0x0,0x0,115892221849904978660692512477189912638156806741322)
```

#### Conclusion

The boundary is around 10e35 system coins, which is nearly impossible to ever exist, therefore this failure isn't concerning.

Overall, this fuzzing wasn't that much helpful, since most of the operations with large number will end up reverting on the SafeEngine contract, which remained unmodified. We can get more revealing results by fuzzing the SafeEngine itself.

### 2. Allowance Fuzz

In this setting, we'll fuzz the public functions of the stability fee treasury plus the functions to set allowances, so the fuzzer has more room to work with. Additionally, two functions were added to transfer coins to the contract itself. The contract used can be found on `StabilityFeeTreasuryFuzz:AllowanceFuzz`

We will still check assertions on this run, however, it's unlikely to reach any additional overflow.

Results:

```
echidna_always_has_minimumFundsRequired: passed! 🎉
echidna_systemCoin_is_never_null: passed! 🎉
echidna_inited: passed! 🎉
echidna_contract_is_enabled: passed! 🎉
echidna_extraSurplusReceiver_is_never_null: passed! 🎉
echidna_surplus_transfer_interval_is_always_respected: passed! 🎉
echidna_treasury_does_not_have_allowance: passed! 🎉
assertion in pullFunds: passed! 🎉
assertion in setPerBlockAllowance: passed! 🎉
assertion in setTotalAllowance: passed! 🎉
assertion in transferSurplusFunds: passed! 🎉
assertion in depositCoinToTreasury: passed! 🎉
assertion in depositUnbackedToTreasury: passed! 🎉

Seed: -1390021045754529775
```

#### Conclusion

No useful conclusions can be drawn for this run.

### 3. Full Governance Fuzz

In this third phase, we'll open all governance functions to the fuzzing addresses, allowing it to set the parameters to any value. It's expected that some of the previous existing assertions will fail.

Results:

```
echidna_always_has_minimumFundsRequired: failed!💥
  Call sequence:
    modifyTreasuryCapacity(100932278458766812330236041672749364716347500281)
    modifyMinimumFundsRequired(100196248315583705946035902871048561839458627834)

echidna_systemCoin_is_never_null: passed! 🎉
echidna_inited: passed! 🎉
echidna_contract_is_enabled: passed! 🎉
echidna_extraSurplusReceiver_is_never_null: passed! 🎉
echidna_surplus_transfer_interval_is_always_respected: failed!💥
  Call sequence:
    modifySurplusTransferDelay(1528037010)

echidna_treasury_does_not_have_allowance: passed! 🎉

Seed: -5419963541718201980

```

This failures highlights some possible issues with governance. For example, if the `MinimumFundsRequired` is modified to a value below the current existing funds, the contract will enter an undesired state. Although there aren't that many consequences, we might want to fix this edge case be adding a requirement statement in the `modifyParameters` function.

A similar effect, although not discovered by fuzzing, could be done by modifying the `treasuryCapacity` to a value smaller than the current calculated capacity, possibly changing slightly the behavior of `transferSurplusFunds`

#### Conclusion

This run highlights some scenarios where the contract might enter an undesired state through governance actions.

## DebtAuctionHouse

### 1. Plain code fuzz

Goal: Check for simple math boundaries by changing the math section of the code to include assertions instead of requires and by removing some of the allowances requirements. Run with checkAsserts turned on.

Results:

```
assertion in AUCTION_HOUSE_TYPE: passed! 🎉
assertion in protocolToken: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in settleAuction: failed!💥
  Call sequence:
    settleAuction(0)

assertion in addAuthorization: passed! 🎉
assertion in contractEnabled: passed! 🎉
assertion in bids: passed! 🎉
assertion in auctionsStarted: passed! 🎉
assertion in startAuction: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in safeEngine: passed! 🎉
assertion in totalAuctionLength: passed! 🎉
assertion in amountSoldIncrease: passed! 🎉
assertion in activeDebtAuctions: passed! 🎉
assertion in disableContract: passed! 🎉
assertion in terminateAuctionPrematurely: passed! 🎉
assertion in removeAuthorization: passed! 🎉
assertion in accountingEngine: passed! 🎉
assertion in restartAuction: failed!💥
  Call sequence:
    startAuction(0x0,77734681540746035813401975242459757532797326125725959483038,0) from: 0x0000000000000000000000000000000000010000
    *wait* Time delay: 174115 seconds Block delay: 2642
    restartAuction(1) from: 0x0000000000000000000000000000000000010000

assertion in bidDuration: passed! 🎉
assertion in bidDecrease: passed! 🎉
assertion in startAuctionUnprotected: failed!💥
  Call sequence:
    modifyParameters("totalAuctionLength\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL",115792089237316195423570985008687907853269984665640564039457584007913129639935)
    startAuctionUnprotected(0x0,0,0)

assertion in modifyParameters: passed! 🎉
assertion in decreaseSoldAmount: failed!💥
  Call sequence:
    startAuction(0x0,115906825127440241515393496365484292651770739579030225903390,0)
    startAuctionUnprotected(0x0,0,0)
    decreaseSoldAmount(1,0,0)


Seed: 4128948578005944261
```

#### Conclusion

This run does shine some light on the mathematical boundaries accepted by the contract. Let's go through each one:

-   assertion in settleAuction: failed!
    A simple case when you try to subtract the active auction counter, it would underflow(0-1);

-   assertion in restartAuction: failed
    For this error to happen, the amount to sell would need to be in the magnitude of 10e65, which very unlikely to happen.

-   assertion in startAuctionUnprotected
    This modifies the length of the auction to the magnitude of 1e50 years, which is a very confortable margin.

-   decreaseSoldAmount
    A requirement would be to have 1e29 wei of assests on sale, which is also a quite unlikely margin.

### 2. StateFull Fuzz

In this run, we create the basics infrastructure for interacting with the auction house, disabling the `check asserts` option.

This will make the fuzzer find its way into creating, bidding and settling auctions.

Results:

```
echidna_account_engine: passed! 🎉
echidna_activeAuctions: passed! 🎉
echidna_amountSoldIncrease: passed! 🎉
echidna_sanity: passed! 🎉
echidna_safe_engine: passed! 🎉
echidna_bidDuration: passed! 🎉
echidna_contract_is_enabled: passed! 🎉
echidna_restardedOnlyStarted: failed!💥
  Call sequence:
    restartAuction(0)

echidna_totalAuctionLength: passed! 🎉
echidna_bidDecrease: passed! 🎉
echidna_protocolToken: passed! 🎉
echidna_started_auctions_arent_null: passed! 🎉

Seed: 4303483714758132403

```

#### Conclusion

The fuzzer found an issue that you can restart the bid 0, even though it was never started and the first valid bid would have id 1. Although this puts the contract in an unexpected state, it doesn't seem to have any security consequences in the contract.

### 2. Governance Fuzz

On this run, the fuzzer is allowed to perform some governance actions, to see what are the possible effects of badly set parameters.

Results:

```
HouseFuzz.sol:GovernanceFuzz
echidna_account_engine: passed! 🎉
echidna_activeAuctions: passed! 🎉
echidna_amountSoldIncrease: passed! 🎉
echidna_sanity: passed! 🎉
echidna_safe_engine: passed! 🎉
echidna_bidDuration: passed! 🎉
echidna_contract_is_enabled: passed! 🎉
echidna_restardedOnlyStarted: passed! 🎉
echidna_totalAuctionLength: passed! 🎉
echidna_bidDecrease: passed! 🎉
echidna_protocolToken: passed! 🎉
echidna_started_auctions_arent_null: passed! 🎉

Seed: 1698267665994827084
```

#### Conclusion

No further insights were gained from this run.

## Surplus Auction Houses

In this section, we'll batch the three surplus auction houses(`BurningSurplusAuctionHouse`, `RecyclingSurplusAuctionHouse`, `PostSettlementSurplusAuctionHouse`) together because they share a lot of the same architecture.

### 1. Plain code fuzz

-   Burning Surplus Auction

```
assertion in bidIncrease: passed! 🎉
assertion in AUCTION_HOUSE_TYPE: passed! 🎉
assertion in protocolToken: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in settleAuction: passed! 🎉
assertion in addAuthorization: passed! 🎉
assertion in contractEnabled: passed! 🎉
assertion in bids: passed! 🎉
assertion in startAuction: passed! 🎉
assertion in auctionsStarted: passed! 🎉
assertion in increaseBidSize: failed!💥
  Call sequence:
    startAuction(0,0)
    increaseBidSize(1,11,118657721143608488720758714298571044685221186723258702512074)

assertion in SURPLUS_AUCTION_TYPE: passed! 🎉
assertion in safeEngine: passed! 🎉
assertion in totalAuctionLength: passed! 🎉
assertion in setUp: passed! 🎉
assertion in disableContract: passed! 🎉
assertion in terminateAuctionPrematurely: passed! 🎉
assertion in removeAuthorization: passed! 🎉
assertion in restartAuction: passed! 🎉
assertion in bidDuration: passed! 🎉

Seed: -5729121038517305206

```

-   Recycling Surplus Auction

```
assertion in bidIncrease: passed! 🎉
assertion in AUCTION_HOUSE_TYPE: passed! 🎉
assertion in protocolToken: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in settleAuction: passed! 🎉
assertion in addAuthorization: passed! 🎉
assertion in contractEnabled: passed! 🎉
assertion in bids: passed! 🎉
assertion in startAuction: passed! 🎉
assertion in auctionsStarted: passed! 🎉
assertion in increaseBidSize: passed! 🎉
assertion in SURPLUS_AUCTION_TYPE: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in safeEngine: passed! 🎉
assertion in totalAuctionLength: passed! 🎉
assertion in setUp: passed! 🎉
assertion in disableContract: passed! 🎉
assertion in terminateAuctionPrematurely: passed! 🎉
assertion in removeAuthorization: passed! 🎉
assertion in restartAuction: failed!💥
  Call sequence:
    modifyParameters("totalAuctionLength\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL",115792089237316195423570985008687907853269984665640564039457584007913129639935)
    restartAuction(0)

assertion in protocolTokenBidReceiver: passed! 🎉
assertion in bidDuration: passed! 🎉
assertion in modifyParameters: passed! 🎉

Seed: 4747728837205116181
```

```
assertion in bidIncrease: passed! 🎉
assertion in AUCTION_HOUSE_TYPE: passed! 🎉
assertion in protocolToken: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in settleAuction: passed! 🎉
assertion in addAuthorization: passed! 🎉
assertion in bids: passed! 🎉
assertion in startAuction: failed!💥
  Call sequence:
    modifyParameters("totalAuctionLength\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL",115792089237316195423570985008687907853269984665640564039457584007913129639935)
    startAuction(0,0)

assertion in auctionsStarted: passed! 🎉
assertion in increaseBidSize: failed!💥
  Call sequence:
    startAuction(0,0)
    increaseBidSize(1,18278669769997,116058827562717934193141055380986954127848981061841538165663)

assertion in safeEngine: passed! 🎉
assertion in totalAuctionLength: passed! 🎉
assertion in setUp: passed! 🎉
assertion in removeAuthorization: passed! 🎉
assertion in restartAuction: failed!💥
  Call sequence:
    modifyParameters("totalAuctionLength\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL",115792089237316195423570985008687907853269984665640564039457584007913129639935)
    restartAuction(0)

assertion in bidDuration: passed! 🎉
assertion in modifyParameters: passed! 🎉

Seed: 3424067764475950047

```

#### Conclusion

Analysing the results we can derive what are the boundaries of all of the surplus contracts.

The largest possible bid increase seems to be in the order of 10e55, which is more than enough and it's quite unlikely that it'll ever reach this limit.

Similarly, there's a limit length close to 2^256 seconds, which should never be used. It might be appropriate to put a hard limit on this value to disallow the governance to create endless auctions.

### 2. Stateful Fuzz

Fuzzing each contract individually, allowing the fuzzer to perform every possible action, except the governance protected ones. Echidna is allowed to create and bid on auctions, as well settle them.

Results:

-   Burning Fuzz

```
echidna_sanity: passed! 🎉
echidna_safe_engine: passed! 🎉
echidna_bidDuration: passed! 🎉
echidna_contract_is_enabled: passed! 🎉
echidna_restardedOnlyStarted: failed!💥
  Call sequence:
    restartAuction(0)

echidna_totalAuctionLength: passed! 🎉
echidna_bidIncrease: passed! 🎉
echidna_protocolToken: passed! 🎉
echidna_started_auctions_arent_null: passed! 🎉

Seed: 3429254500745831879

```

-   Burning Fuzz

```
echidna_sanity: passed! 🎉
echidna_safe_engine: passed! 🎉
echidna_bidDuration: passed! 🎉
echidna_contract_is_enabled: passed! 🎉
echidna_restardedOnlyStarted: failed!💥
  Call sequence:
    restartAuction(0)

echidna_totalAuctionLength: passed! 🎉
echidna_bidIncrease: passed! 🎉
echidna_protocolToken: passed! 🎉
echidna_started_auctions_arent_null: passed! 🎉

Seed: -3805287122352836403

```

-   PostSettlement Fuzz

```
echidna_sanity: passed! 🎉
echidna_safe_engine: passed! 🎉
echidna_bidDuration: passed! 🎉
echidna_contract_is_enabled: failed with no transactions made ⁉️
echidna_restardedOnlyStarted: failed!💥
  Call sequence:
    restartAuction(0)

echidna_totalAuctionLength: passed! 🎉
echidna_bidIncrease: passed! 🎉
echidna_protocolToken: passed! 🎉
echidna_started_auctions_arent_null: passed! 🎉

Seed: 6968832900734577861

```

#### Conclusion

All the fuzzed contracts returned similar results to the Debt Auction House, raising attention only to the possibility of restarting a non-started auction weith id `0`. Otherwise, no more insights can be derived from this run, as most of the logic is the same as the other auction houses.

As another note, the test `echidna_contract_is_enabled` on `PostSettlement Fuzz` failed because this specific contract does not have a `contractEnabled` variable, therefore it always returns false.

### 2. Governance Fuzz

In this run, we give the fuzzer the possibility of performing a few of the governance actions.

Results:

-   Burning Governance

```
echidna_sanity: passed! 🎉
echidna_safe_engine: passed! 🎉
echidna_bidDuration: failed!💥
  Call sequence:
    restartAuction(0)
    modifyBidDuration(0)

echidna_contract_is_enabled: passed! 🎉
echidna_restardedOnlyStarted: failed!💥
  Call sequence:
    restartAuction(0)

echidna_totalAuctionLength: failed!💥
  Call sequence:
    restartAuction(0)
    modifyTotalAuctionLength(0)

echidna_bidIncrease: passed! 🎉
echidna_protocolToken: passed! 🎉
echidna_started_auctions_arent_null: passed! 🎉

Seed: -337846313838681555
```

-   Recycling Governance Fuzz

```
echidna_sanity: passed! 🎉
echidna_safe_engine: passed! 🎉
echidna_bidDuration: failed!💥
  Call sequence:
    restartAuction(0)
    modifyBidDuration(0)

echidna_contract_is_enabled: passed! 🎉
echidna_restardedOnlyStarted: failed!💥
  Call sequence:
    restartAuction(0)

echidna_totalAuctionLength: failed!💥
  Call sequence:
    restartAuction(0)
    modifyTotalAuctionLength(0)

echidna_bidIncrease: passed! 🎉
echidna_protocolToken: passed! 🎉
echidna_started_auctions_arent_null: passed! 🎉

Seed: 4971600650093521888
```

-   PostStellement Governance Fuzz

```
ionHouseFuzz.sol:PostSettlementGovernanceFuzz
echidna_sanity: passed! 🎉
echidna_safe_engine: passed! 🎉
echidna_bidDuration: failed!💥
  Call sequence:
    restartAuction(0)
    modifyBidDuration(0)

echidna_contract_is_enabled: failed with no transactions made ⁉️
echidna_restardedOnlyStarted: failed!💥
  Call sequence:
    restartAuction(0)

echidna_totalAuctionLength: failed!💥
  Call sequence:
    restartAuction(0)
    modifyTotalAuctionLength(0)

echidna_bidIncrease: passed! 🎉
echidna_protocolToken: passed! 🎉
echidna_started_auctions_arent_null: passed! 🎉

Seed: 7015492352463702073

```

#### Conclusion

This fuzzing yielded the expected results, affecting only the tests scenarios in which the governance has the power to change.

A interesting note is that there's no bound to which values are allowed to be modified, making it possible to change the duration of a bid to either `0` or to a extremely large number, making auction never effectively start or un-finishable. A proposed adjustment is to define reasonable boundaries and limit the governance changes.
