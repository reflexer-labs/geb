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

## MixedSurplusAuctionHouse

### Plain code fuzz
```
Analyzing contract: /geb/src/test/single/fuzz/MixedSurplusAuctionHouseFuzz.sol:GeneralFuzz
assertion in bidIncrease: passed! 🎉
assertion in AUCTION_HOUSE_TYPE: passed! 🎉
assertion in protocolToken: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in settleAuction: passed! 🎉
assertion in addAuthorization: passed! 🎉
assertion in contractEnabled: passed! 🎉
assertion in bids: passed! 🎉
assertion in bid: failed!💥
  Call sequence:
    bid(116101972641952233700501493460459085256926114673135731799257)

assertion in startAuction: passed! 🎉
assertion in auctionsStarted: passed! 🎉
assertion in increaseBidSize: passed! 🎉
assertion in SURPLUS_AUCTION_TYPE: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in safeEngine: passed! 🎉
assertion in totalAuctionLength: passed! 🎉
assertion in disableContract: passed! 🎉
assertion in terminateAuctionPrematurely: passed! 🎉
assertion in removeAuthorization: passed! 🎉
assertion in settleAuction: passed! 🎉
assertion in FIFTY: passed! 🎉
assertion in restartAuction: passed! 🎉
assertion in protocolTokenBidReceiver: passed! 🎉
assertion in bidDuration: passed! 🎉
assertion in HUNDRED: passed! 🎉
assertion in modifyParameters: passed! 🎉

Seed: 7117536309673329615
```

One failure above. Bids upwards from 116101972641952233700501493460459085256926.114673135731799257 will overflow. Bounds are plentiful.

### Conclusion: No exceptions noted

### Fuzz Bids

In this case we setup an auction and let echidna fuzz the whole contract with three users. Users have an unlimited balance, and will basically settle the auction in multiple ways.

Here we are not looking for bounds, but instead checking the properties that either should remain constant, or that move as the auction evolves:

- auctionsStarted
- bidIncrease
- bidDuration
- totalAuctionLength
- bid values / transitions
- tokens received by the auction contract
- token split / flow on auction settlement

We also validate the token flows in and out of the auction contract.

These properties are verified in between all calls.

A function to aid the fuzzer to bid in the correct auction was also created (functions bid and settleAuction in fuzz contract). The fuzzer does find it's way to the correct auction/bid amounts, but enabling this function will increase it's effectiveness. To test without the aid function turn it's visibility to internal.

```
Analyzing contract: /geb/src/test/single/fuzz/MixedSurplusAuctionHouseFuzz.sol:FuzzBids
echidna_bids: passed! 🎉
echidna_auctionsStarted: passed! 🎉
echidna_bidDuration: passed! 🎉
echidna_totalAuctionLength: passed! 🎉
echidna_bidIncrease: passed! 🎉

Seed: 7092706279483604568
```


#### Conclusion: No exceptions found.