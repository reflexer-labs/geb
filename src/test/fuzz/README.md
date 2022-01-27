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

## Safe Engine

### 1. Fuzzing for overflows (FuzzBounds)

This contract is very state dependent, so results here are limited to expected overflows dua to lack of balances :

```
Analyzing contract: src/test/fuzz/SAFEEngineFuzz.sol:FuzzBounds
assertion in safeRights: passed! 🎉
assertion in setUp: passed! 🎉
assertion in updateAccumulatedRate: passed! 🎉
assertion in debtBalance: passed! 🎉
assertion in createUnbackedDebt: passed! 🎉
assertion in globalUnbackedDebt: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in settleDebt: failed!💥
  Call sequence:
    settleDebt(1)

assertion in globalDebtCeiling: passed! 🎉
assertion in addAuthorization: passed! 🎉
assertion in safes: passed! 🎉
assertion in contractEnabled: passed! 🎉
assertion in transferSAFECollateralAndDebt: failed!💥
  Call sequence:
    transferSAFECollateralAndDebt("\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL",0x0,0x0,1,0)

assertion in modifyCollateralBalance: passed! 🎉
assertion in confiscateSAFECollateralAndDebt: passed! 🎉
assertion in transferCollateral: failed!💥
  Call sequence:
    transferCollateral("\221\162\185\143\137\132\195bL\153\144Ku\211\195\168\170,\178\DC3\200\&2\137\GSM\177\153\174h\177\144\171",0x10000,0xd07b3980559481050f4abe0f4fa8bd83ed4d24bd,104865307180199114566940150977522581834252447423671437387622600163274029655525)

assertion in canModifySAFE: passed! 🎉
assertion in initializeCollateralType: passed! 🎉
assertion in tokenCollateral: passed! 🎉
assertion in globalDebt: passed! 🎉
assertion in disableContract: passed! 🎉
assertion in removeAuthorization: passed! 🎉
assertion in modifySAFECollateralization: passed! 🎉
assertion in collateralTypes: passed! 🎉
assertion in denySAFEModification: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in approveSAFEModification: passed! 🎉
assertion in transferInternalCoins: failed!💥
  Call sequence:
    transferInternalCoins(0x10000,0xa329c0648769a73afac7f9381e08fb43dbea72,96713722106098848221190451832526082073971617248180315067258712285640862681803)

assertion in coinBalance: passed! 🎉
assertion in safeDebtCeiling: passed! 🎉
assertion in modifyParameters: passed! 🎉

Seed: -935848132829649197
```

#### Conclusion: No exceptions noted


### Fuzz (FuzzSafes)

In this case we setup safeEngine, taxCollector and both the collateral and coin Joins and let echidna fuzz the whole contract with three users (adjust echidna.yaml to include more users). The users will perform the following actions:

- Join with collateral or coin
- Exit collateral or coin
- Transfer collateral
- Transfer internal coins
- Modify safe collateralization

For each of these actions the main state changes are checked through assertions (turn on checkAsserts on echidna.yaml to check these for every call).

Properties are verified in between all calls:
- collateral debtAmount equals sum of all debts in all safes created
- collateral debtAmount always matches globalDebt (we're testing with one collateral)
- collateral debtAmount is lower than collateral debtCeiling
- globalDebt is lower than globalDebtCeiling
- All safe debts are greater than collateral debtFloor
- Collateral Join collateral balance equals sum of all collateral balances of users / safes
- Coin totalSupply matches coinJoin's internal coin balance
- Unbacked debt == 0 (no transactions should affect it in this test)

```
Analyzing contract: /src/test/fuzz/SAFEEngineFuzz.sol:FuzzSafes
echidna_join_collateral_balance: passed! 🎉
echidna_global_debt_ceiling: passed! 🎉
echidna_collateral_and_global_debt_match: passed! 🎉
echidna_collateral_debt_vs_safes: passed! 🎉
echidna_collateral_debt_ceiling: passed! 🎉
echidna_safe_debt_floor: passed! 🎉
echidna_coin_internal_balance: passed! 🎉
echidna_unbacked_debt: passed! 🎉
assertion in transferInternalCoins: passed! 🎉
assertion in join: passed! 🎉
assertion in transferCollateral: passed! 🎉
assertion in exit: passed! 🎉
assertion in modifySAFECollateralization: passed! 🎉

Seed: 8590206274387643523
```

#### Conclusion: No issues noted.