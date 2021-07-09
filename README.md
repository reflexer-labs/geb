# A Capital Efficient Fiat Pegged Rebasing Token for Reflexer Systems

This pull request implements the token as specified at https://gitcoin.co/issue/reflexer-labs/geb/103/100026033. The
implementation can be used for RAI but also any other system coin in the MGL. The token implements a standard ERC20
interface and comes with the constraints of any rebasing token, don't keep mementos of balances.

## Token Implementation

Internal balances are stored in the underlying system coin units while token interfaces use the rebasing tokens units.
Approvals are constant in rebase units and will drift in system coin units. A mixin manages communication with the
OracleRelayer and provides both read only and update methods for the redemption price. The principal that view methods
for apps can access the oracle price through a view method with a cached redemption rate, while state modifying methods
which must use a result which is correct after any redemption rate modifications update the oracle first via the mixins
modifier.

## Capital Efficiency and Stability Pool

The RAI (system coin) collateral must maintain perfect availability for the integrity of the rebasing token, however the
allocated capital presents an opportunity to feed many birds with one seed. The RAI can be used to add additional layers
defending the protocols solvency by acting as a stability pool. Stability pools can have a flaw of making a protocol too
circular but this solution keeps the purpose alive as the rebase tokens are still mobile. A previous attempt at a
liquidation pool for RAI had a weakness to MEV and required complex accounting and provided no additional utility. This
solution removes all MEV, RAI profits go directly into the surplus buffer. This gives the protocol energy to spend
elsewhere such as incentivising rebase token usage to increase pool size and RAI TVL, negative RAI borrow rates, or
buying back FLX. RAI collateral is safe in liquidations as unless a profit is made the stability pool will be
bypassed via a reversion within a try loop so liquidations can proceed via auctions. In the case where the stability
pool is successful the bought system collateral is swapped for system coins to restore the rebase collateral and the
remains are sent to the surplus buffer.

## Testing

Automated tests can be run as usual as part of the GEB suite and focus on the use of the rebasing token. A mock of the
currently incentived protocol for systemCoin-collateral swaps has been created and ported to solidity 0.6.7 to keep
running tests simple and allow running through liquidations.