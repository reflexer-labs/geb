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

## IncreasingDiscountCollateralAuctionHouse

### Plain code fuzz
```
Analyzing contract: /Users/fabio/Documents/reflexer/geb/src/test/fuzz/IncreasingDiscountAuctionHouseFuzz.sol:GeneralFuzz
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
    getSystemCoinCeilingDeviatedPrice(115773487417254907197205030519895214769828909652918663033805)

assertion in oracleRelayer: passed! 🎉
assertion in buyCollateral: passed! 🎉
assertion in auctionsStarted: passed! 🎉
assertion in amountToRaise: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in safeEngine: passed! 🎉
assertion in totalAuctionLength: passed! 🎉
assertion in raisedAmount: passed! 🎉
assertion in getDiscountedCollateralPrice: failed!💥
  Call sequence:
    getDiscountedCollateralPrice(5388163427799223052413,13643974492853,1,27020250256798911626998570259)

assertion in getApproximateCollateralBought: passed! 🎉
assertion in terminateAuctionPrematurely: passed! 🎉
assertion in removeAuthorization: passed! 🎉
assertion in minDiscount: passed! 🎉
assertion in minSystemCoinMedianDeviation: passed! 🎉
assertion in getNextCurrentDiscount: passed! 🎉
assertion in getCollateralFSMAndFinalSystemCoinPrices: passed! 🎉
assertion in maxDiscount: passed! 🎉
assertion in getFinalBaseCollateralPrice: failed!💥
  Call sequence:
    getFinalBaseCollateralPrice(110936035490933793969012534002241903946603916752181329467260,0)

assertion in minimumBid: passed! 🎉
assertion in systemCoinOracle: passed! 🎉
assertion in collateralType: passed! 🎉
assertion in maxDiscountUpdateRateTimeline: passed! 🎉
assertion in remainingAmountToSell: passed! 🎉
assertion in collateralFSM: passed! 🎉
assertion in perSecondDiscountUpdateRate: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in getSystemCoinFloorDeviatedPrice: failed!💥
  Call sequence:
    getSystemCoinFloorDeviatedPrice(115818244939214921101383206796313185809555746423712078809288)


Seed: 8178425613958164039
```

Some of the getters overflow, as follows:

assertion in getSystemCoinCeilingDeviatedPrice: failed!💥
  Call sequence:
    getSystemCoinCeilingDeviatedPrice(115773487417254907197205030519895214769828909652918663033805)

Will overflow for a redempetion price larger than approx. 115,773,487,417,254.907197205030519895214769828909652918663033805 (RAD)

assertion in getDiscountedCollateralPrice: failed!💥
  Call sequence:
    getDiscountedCollateralPrice(5388163427799223052413,13643974492853,1,27020250256798911626998570259)

    Will overflow for:
    uint256 collateralFsmPriceFeedValue: 5388.163427799223052413
    uint256 collateralMedianPriceFeedValue: .000013643974492853
    uint256 systemCoinPriceFeedValue: 1
    uint256 customDiscount: 27020250256.798911626998570259

assertion in getFinalBaseCollateralPrice: failed!💥
  Call sequence:
    getFinalBaseCollateralPrice(110936035490933793969012534002241903946603916752181329467260,0)

Will overflow for a collateralFsmPriceFeedValue larger than approx. 110936035490933793969012534002241903946603916752181329467260 (RAD), value needs to diverge considerably from medianPriceFeedValue.

assertion in getSystemCoinFloorDeviatedPrice: failed!💥
  Call sequence:
    getSystemCoinFloorDeviatedPrice(115818244939214921101383206796313185809555746423712078809288)

Will overflow for a redempetion price larger than approx. 115,818,244,939,214.921101383206796313185809555746423712078809288 (RAD)

### Conclusion: Bounds are reasonable considering ETH as a collateral and the RAI current redemption price of ~3usd

### Fuzz Bids

In this case we setup an auction and let echidna fuzz the whole contract with three users. Users have an unlimited balance, and will basically settle the auction in multiple ways.

Here we are not looking for bounds, but instead checking the properties that either should remain constant, or that move as the auction evolves:

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
- discount bounds
- minSystemCoinMedianDeviation

We also validate the token flows in and out of the auction contract.

These properties are verified in between all calls.

A function to aid the fuzzer to bid in the correct auction was also created (function bid in fuzz contract). It forces a valid bid on the auction. The fuzzer does find it's way to the correct auction/bid amounts, but enabling this function will increase it's effectiveness. To test without the aid function turn it's visibility to internal.

```
Analyzing contract: /Users/fabio/Documents/reflexer/geb/src/test/fuzz/IncreasingDiscountAuctionHouseFuzz.sol:FuzzBids
echidna_collateralType: passed! 🎉
echidna_minimumBid: passed! 🎉
echidna_lowerSystemCoinMedianDeviation: passed! 🎉
echidna_lastReadRedemptionPrice: passed! 🎉
echidna_bids: passed! 🎉
echidna_auctionsStarted: passed! 🎉
echidna_upperSystemCoinMedianDeviation: passed! 🎉
echidna_lowerCollateralMedianDeviation: passed! 🎉
echidna_upperCollateralMedianDeviation: passed! 🎉
echidna_minSystemCoinMedianDeviation: passed! 🎉

Seed: 1789934444307498959
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
Analyzing contract: /Users/fabio/Documents/reflexer/geb/src/test/fuzz/IncreasingDiscountAuctionHouseFuzz.sol:FuzzAuctionsAndBids
echidna_collateralType: passed! 🎉
echidna_lastReadRedemptionPrice: passed! 🎉
echidna_bids: passed! 🎉

Seed: -4370295641948008034
```

#### Conclusion: No exceptions found.

