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

1. Writing assertions and/or turning "requires" into "asserts" within the smart contract itself. This will cause echidna to fail fuzzing, and upon failures echidna finds the lowest value that causes the assertion to fail. This is useful to test bounds of functions (i.e.: modifying safeMath functions to assertions will cause echidna to fail on overflows, giving insight on the bounds acceptable). This is useful to find out when these functions revert. Although reverting will not impact the contract's state, it could cause a denial of service (or the contract not updating state when necessary and getting stuck). We check the found bounds against the expected usage of the system.
2. For contracts that have state (i.e.: the auction house below), we also force the contract into common states and fuzz common actions like bidding, or starting auctions (and then bidding the hell out of them).

Echidna will generate random values and call all functions failing either for violated assertions, or for properties (functions starting with echidna_) that return false. Sequence of calls is limited by seqLen in the config file. Calls are also spaced over time (both block number and timestamp) in random ways. Once the fuzzer finds a new execution path, it will explore it by trying execution with values close to the ones that opened the new path.

# Results

### 1. Fuzzing for overflows (FuzzBounds)

In this test we want failures, as they will show us what are the bounds in which the contract operates safely.

This will fuzz the contract with one auction open, we then fuzz all functions (including bidding and eventually settling the auction). This test should be run with a shorter seqLen (50 or so) to increase effectiveness, as once the auction is settled there is nothing more to test.

Failures flag where overflows happen, and should be compared to expected inputs (to avoid overflows frm causing DoS). Only Failures are listed below:

```
assertion in getCollateralBought: failed!💥  
  Call sequence:
    getCollateralBought(1,115852260170229704215502635069507091454611135704393)
```
Overflows for bids over 115,852,260,170,229,704,215,502,635,069,507.091

```
assertion in getAdjustedBid: failed!💥  
  Call sequence:
    getAdjustedBid(1,115912523233099390183511836132301081086018558778472)
```
Overflows for bids over 115,912,523,233,099,390,183,511,836,132,301.081
```
assertion in getSystemCoinCeilingDeviatedPrice: failed!💥  
  Call sequence:
    getSystemCoinCeilingDeviatedPrice(116031928971255834253007017460483589268099940875272393200583)
```
Overflows for redemptionPrice over 116,031,928,971,255.834
```
assertion in buyCollateral: failed!💥  
  Call sequence:
    buyCollateral(1,116041609248999843043660847480715018474496550759127)
```
Overflows for bids over 116,041,609,248,999,843,043,660,847,480,715.018
```
assertion in getDiscountedCollateralPrice: failed!💥  
  Call sequence:
    getDiscountedCollateralPrice(110326256761748006083924545159069305469967989447762913914908,2580406171648308303305981998604934861523273509666816,0,11985351022225703950946569829549902962025125870890)

```
Overflows on:
- collateralFsmPriceFeedValue: 110326256761748006083924545159069305469967989447762913914908
- collateralMedianPriceFeedValue: 2580406171648308303305981998604934861523273509666816
- systemCoinPriceFeedValue: 0
- customDiscount: 11985351022225703950946569829549902962025125870890
```

assertion in getFinalBaseCollateralPrice: failed!💥  
  Call sequence:
    getFinalBaseCollateralPrice(110293879973642189681647237447308730191744191659258543580692,24095652930438913062552306596040710880337422683556178755)
```
Overflows on:
- collateralFsmPriceFeedValue: 110293879973642189681647237,447,308,730,191,744.191659258543580692
- collateralMedianPriceFeedValue: 24095652930438913062552,306,596,040,710,880.337422683556178755
```
assertion in getSystemCoinFloorDeviatedPrice: failed!💥  
  Call sequence:
    getSystemCoinFloorDeviatedPrice(115861504975155156346320912989201343490028490736260447925529)
```
Overflows with 115861504975155156346320912989201343490028490736260447925529

#### Conclusion: No issues noted, bounds are plentiful even on the most extreme expected scenarios.


### Fuzz (FuzzBids)

In this case we setup an auction and let echidna fuzz the whole contract with three users. Users have an unlimited balance, and will basically settle the auction in multiple ways. Run it with checkAsserts: false, to prevent overflows from flagging the same issues we highlighted in the previous tests. Also use a lowish seqLen (to prevent the fuzzer from trying to explore long after the auction is settled).

Here we are not looking for bounds, but instead checking the properties that either should remain constant, or that move as the auction evolves:

- collateralType
- minimumBid
- lowerSystemCoinMedianDeviation
- maxDiscount
- lastRedemptionPrice
- auctionsStarted
- lowerSystemCoinMedianDeviation
- upperSystemCoinMedianDeviation
- lowerCollateralMedianDeviation
- upperCollateralMedianDeviation
- discount (within bounds)
- minSystemCoinMedianDeviation

We also validate the token flows in and out of the auction contract.

These properties are verified in between all calls.

A function to aid the fuzzer to bid in the correct auction was also created (function bid in fuzz contract). It forces a valid bid on the auction. The fuzzer does find it's way to the correct auction/bid amounts, but enabling this function will increase it's effectiveness. To test without the aid function turn it's visibility to internal.

```
Analyzing contract: /Users/fabio/Documents/reflexer/geb/src/test/fuzz/increasingDiscountAuctionHouseFuzz.sol:FuzzBids
echidna_collateralType: passed! 🎉
echidna_minimumBid: passed! 🎉
echidna_lowerSystemCoinMedianDeviation: passed! 🎉
echidna_maxDiscount: passed! 🎉
echidna_lastReadRedemptionPrice: passed! 🎉
echidna_bids: passed! 🎉
echidna_auctionsStarted: passed! 🎉
echidna_upperSystemCoinMedianDeviation: passed! 🎉
echidna_perSecondDiscountUpdateRate: passed! 🎉
echidna_lowerCollateralMedianDeviation: passed! 🎉
echidna_upperCollateralMedianDeviation: passed! 🎉
echidna_discount: passed! 🎉
echidna_maxDiscountUpdateRateTimeline: passed! 🎉
echidna_minSystemCoinMedianDeviation: passed! 🎉

Seed: -8237748390916735651
```

#### Conclusion: One exception found

Due to the different way the funcion ```buyCollateral``` removes coins from auction when the auction is settled, a minor difference occurs between the coins removed from auction (on liquidationEngine) and the amount sent to ```auctionIncomeRecipient``` (on safeEngine). Example below:

```
log_named_uint("auctionIncomeRecipient balance", 60980538147000000000000000000000000000)
log_named_uint("removed coins on liq engine",    60980538146327134580274291843636852893)
```

The function on the mock contract was fixed, to prevent the difference from happening.


### Auctions and bids (FuzzAuctionsAndBids)

In this case we auth the fuzzer users, and let them both create auctions and bid on them. In this case there is also an aid function (bid) that will bid in one of the created auctions (settled or unsettled).

A high seqLen is recommended, 1500 was used for this run. (This means that for every instance of the contract the fuzzer will try a sequence of 1500 txs). This will allow for many auctions to be created, bidded on and settled in haphazard ways.

Turn the modifyParameters(bytes32,address) to internal to run this case (as it will prevent the fuzzer to change oracle and accountingEngine addresses), and do the same with terminateAuctionPrematurely, or the fuzzer will terminate auctions randomly (to taste).

We set the following properties for this case:
- dicsound bounds
- maxDiscount
- perSecondDiascountUpdateRate
- Amounts settled and token flows

We also check if the token flows are acceptable.
```
Analyzing contract: /Users/fabio/Documents/reflexer/geb/src/test/fuzz/increasingDiscountAuctionHouseFuzz.sol:FuzzAuctionsAndBids
echidna_collateralType: passed! 🎉
echidna_minimumBid: passed! 🎉
echidna_lowerSystemCoinMedianDeviation: passed! 🎉
echidna_maxDiscount: passed! 🎉
echidna_lastReadRedemptionPrice: passed! 🎉
echidna_bids: passed! 🎉
echidna_upperSystemCoinMedianDeviation: passed! 🎉
echidna_perSecondDiscountUpdateRate: passed! 🎉
echidna_lowerCollateralMedianDeviation: passed! 🎉
echidna_upperCollateralMedianDeviation: passed! 🎉
echidna_discount: passed! 🎉
echidna_maxDiscountUpdateRateTimeline: passed! 🎉
echidna_minSystemCoinMedianDeviation: passed! 🎉

Seed: -7178401117171357020
```

#### Conclusion: No exceptions found.

