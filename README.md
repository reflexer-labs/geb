# GEB

This repository contains the core smart contract code for Generalized Ethereum Bonds. While we intend to use the "GEB" terminology when we discuss about core architecture, the actual instrument issued by the protocol is called a reflex bond.

# What is a Reflex Bond?

A reflex bond is an asset that mirrors the price movements of its collateral in a dampened way (and with lags between the underlying changing its value and the reflex bond system reacting to that). The _future_ redemption price of a reflex bond depends on the market price deviation from its _current_ redemption. For more details, check the [whitepaper](https://github.com/reflexer-labs/whitepapers/blob/master/rai.pdf).

# Code Differences Compared to Multi Collateral Dai (MCD)

## Insurance for CDPs

GEB creators can allow CDP users to specify "trigger" contracts that protect them against liquidation. A trigger is called when a keeper calls the *liquidateCDP* function (previously *bite*) from LiquidationEngine (previously Cat). The trigger can, for example, sell a short position and add the proceeds to a CDP, thus saving it from the CollateralAuctionHouse (previously Flip/per).

Trigger integrations need to be thoroughly audited because there is the risk that too little collateral is locked in a CollateralJoin adapter (previously GemJoin) and too much is added in the CDPEngine (previously Vat). A bug like this would allow a CDP user to generate GEB that is not covered by enough (or any) collateral.

## Two CDP Ratio Thresholds

CDP users can generate GEB until they hit the *safeCRatio* but they will only get liquidated when the CDP's ratio goes under *liquidationCRatio*. liquidationCRatio must be smaller than or equal to safeCRatio.

## Redemption Rate

The redemption rate is a variable inside Oracle Relayer (previously Spot/ter) that acts similarly to an interest rate which is applied to the redemption price (previously par). As described in our first [whitepaper](https://github.com/reflexer-labs/whitepapers/blob/master/rai.pdf), the redemption rate is the main driving force that changes the incentives of system participants.

## Multi Stability Fee Receivers

The TaxCollector (previously Jug) can now be set up to accrue stability fees in multiple places at once. A receiver is called a "bucket" or "taxBucket". TaxCollector is guaranteed to always offer some stability fees to the AccountingEngine.

## Stability Fee Treasury

The [treasury](https://github.com/reflexer-labs/geb/blob/master/src/StabilityFeeTreasury.sol) is in charge with paying for oracle calls, paying collateral onboarding teams (in some GEB versions) and providing funds for on-chain market making. It can be set up to transfer some of its funds into the AccountingEngine (previously Vow) in case the predicted costs for maintaining the system in the next *P* seconds are lower than the currently available treasury surplus.

## Settlement Surplus Auctioner

This contract auctions all the remaining surplus after GlobalSettlement (previously End) shuts down the system and the AccountingEngine settles as much debt as possible.

We are looking at alternative ways to drain the extra surplus without giving CDP users, GEB or protocol token holders any advantage when the system settles.

## Debt Auction Monitoring

AccountingEngine (previously Vow) has a mapping and an accumulator that keep track of active debt auctions. These additions are useful for creating a Restricted Migration Module (see the [whitepaper](https://github.com/reflexer-labs/whitepapers/blob/master/rai.pdf)) that makes sure it cannot withdraw the ability of a system to print tokens while debt auctions are still ongoing.

## Debt Auction Bid Target

Governance can set a variable called *debtAuctionBidTarget* which can be used to autonomously determine how much debt is auctioned in a debt auction and also the initial proposed protocol token bid.

## Variable Names You Can Actually Understand :astonished:

The following tables show the before and after variable names of all core MCD contracts (excluding the new ones we added)

| Vat | CDPEngine |                                     
| --- | --- |                                  
| wards | authorizedAccounts |                                  
| rely | addAuthorization |                
| deny | removeAuthorization |            
| auth | isAuthorized |
| can | cdpRights |                                     
| hope | approveCDPModification |
| nope | denyCDPModification |
| wish | canModifyCDP |
| Ilk | CollateralType |
| Ilk.Art | CollateralType.debtAmount |
| Ilk.rate | CollateralType.accumulatedRates |
| Ilk.spot | CollateralType.safetyPrice |
| Ilk.line | CollateralType.debtCeiling |
| Ilk.dust | CollateralType.debtFloor |
| NaN | CollateralType.liquidationPrice (NEW) |
| Urn | CDP |
| Urn.ink | CDP.lockedCollateral |
| Urn.art | CDP.generatedDebt |
| ilks | collateralTypes |
| urns | cdps |
| gem | tokenCollateral |
| dai | coinBalance |
| sin | debtBalance |
| debt | globalDebt |
| vice | globalUnbackedDebt |
| Line | globalDebtCeiling |
| live | contractEnabled |
| note | emitLog |
| init | initializeCollateralType |
| file | modifyParameters |
| cage | disableContract |
| slip | modifyCollateralBalance |
| flux | transferCollateral |
| move | transferInternalCoins |
| frob | modifyCDPCollateralization |
| NaN | saveCDP (NEW) |
| fork | transferCDPCollateralAndDebt |
| grab | confiscateCDPCollateralAndDebt |
| heal | settleDebt |
| suck | createUnbackedDebt |
| fold | updateAccumulatedRate |

| Vow | AccountingEngine |
| --- | --- |
| wards | authorizedAccounts |                                  
| rely | addAuthorization |                
| deny | removeAuthorization |            
| auth | isAuthorized |
| vat | cdpEngine |
| flapper | surplusAuctionHouse |
| flopper | debtAuctionHouse |
| NaN | settlementSurplusAuctioner (NEW) |
| sin | debtQueue |
| NaN | activeDebtAuctions |
| Sin | totalQueuedDebt |
| Ash | totalOnAuctionDebt |
| NaN | activeDebtAuctionsAccumulator (NEW) |
| NaN | lastSurplusAuctionTime (NEW) |
| NaN | surplusAuctionDelay (NEW) |
| wait | popDebtDelay |
| dump | initialDebtAuctionAmount |
| sump | debtAuctionBidSize |
| NaN | debtAuctionBidTarget |
| bump | surplusAuctionAmountToSell |
| hump | surplusBuffer |
| live | contractEnabled |
| file | modifyParameters |
| fess | pushDebtToQueue |
| flog | popDebtFromQueue |
| heal | settleDebt |
| kiss | cancelAuctionedDebtWithSurplus |
| flop | auctionDebt |
| NaN | settleDebtAuction (NEW) |
| flap | auctionSurplus |
| cage | disableContract |

| Flap/per | SurplusAuctionHouse |
| --- | --- |
| wards | authorizedAccounts |                                  
| rely | addAuthorization |                
| deny | removeAuthorization |            
| auth | isAuthorized |
| Bid | Bid |
| Bid.bid | Bid.bidAmount |
| Bid.lot | Bid.amountToSell |
| Bid.guy | Bid.highBidder |
| Bid.tic | Bid.bidExpiry |
| Bid.end | Bid.auctionDeadline |
| Kick | StartAuction |
| bids | bids |
| vat | cdpEngine |
| gem | protocolToken |
| beg | bidIncrease |
| ttl | bidDuration |
| tau | totalAuctionLength |
| kicks | auctionsStarted |
| live | contractEnabled |
| file | modifyParameters |
| kick | startAuction |
| tick | restartAuction |
| tend | increaseBidSize |
| deal | settleAuction |
| cage | disableContract |
| yank | terminateAuctionPrematurely |

| Flop/per | DebtAuctionHouse |
| --- | --- |
| wards | authorizedAccounts |                                  
| rely | addAuthorization |                
| deny | removeAuthorization |            
| auth | isAuthorized |
| Bid | Bid |
| Bid.bid | Bid.bidAmount |
| Bid.lot | Bid.amountToSell |
| Bid.guy | Bid.highBidder |
| Bid.tic | Bid.bidExpiry |
| Bid.end | Bid.auctionDeadline |
| Kick | StartAuction |
| bids | bids |
| vat | cdpEngine |
| vow | accountingEngine |
| gem | protocolToken |
| beg | bidIncrease |
| pad | amountSoldIncrease |
| ttl | bidDuration |
| tau | totalAuctionLength |
| kicks | auctionsStarted |
| live | contractEnabled |
| file | modifyParameters |
| kick | startAuction |
| tick | restartAuction |
| dent | decreaseSoldAmount |
| deal | settleAuction |
| cage | disableContract |
| yank | terminateAuctionPrematurely |

| Flip/per | CollateralAuctionHouse |
| --- | --- |
| wards | authorizedAccounts |                                  
| rely | addAuthorization |                
| deny | removeAuthorization |            
| auth | isAuthorized |
| Bid | Bid |
| Bid.bid | Bid.bidAmount |
| Bid.lot | Bid.amountToSell |
| Bid.guy | Bid.highBidder |
| Bid.tic | Bid.bidExpiry |
| Bid.end | Bid.auctionDeadline |
| Bid.usr | Bid.forgoneCollateralReceiver |
| Bid.gal | Bid.auctionIncomeRecipient |
| Bid.tab | Bid.amountToRaise |
| Kick | StartAuction |
| bids | bids |
| vat | cdpEngine |
| ilk | collateralType |
| beg | bidIncrease |
| ttl | bidDuration |
| tau | totalAuctionLength |
| kicks | auctionsStarted |
| cut | bidToMarketPriceRatio |
| spot | oracleRelayer |
| pip | orcl |
| Kick | StartAuction |
| live | contractEnabled |
| file | modifyParameters |
| kick | startAuction |
| tick | restartAuction |
| tend | increaseBidSize |
| dent | decreaseSoldAmount |
| deal | settleAuction |
| yank | terminateAuctionPrematurely |

| Join | BasicTokenAdapters |
| --- | --- |
| wards | authorizedAccounts |                                  
| rely | addAuthorization |                
| deny | removeAuthorization |            
| auth | isAuthorized |
| GemLike | CollateralLike |
| GemJoin | CollateralJoin |
| vat | cdpEngine |
| ilk | collateralType |
| gem | collateral |
| dec | decimals |
| live | contractEnabled |
| cage | disableContract |
| join | join |
| exit | exit |
| ETHJoin | ETHJoin |
| DaiJoin | CoinJoin |
| dai | systemCoin |

| Cat | LiquidationEngine |
| --- | --- |
| wards | authorizedAccounts |                                  
| rely | addAuthorization |                
| deny | removeAuthorization |            
| auth | isAuthorized |
| NaN | cdpSaviours (NEW) |
| NaN | connectCDPSaviour (NEW) |
| NaN | disconnectCDPSaviour (NEW) |
| Ilk | CollateralType |
| Ilk.flip | CollateralType.collateralAuctionHouse |
| Ilk.chop | CollateralType.liquidationPenalty |
| Ilk.lump | CollateralType.collateralToSell |
| ilks | collateralTypes |
| NaN | chosenCDPSaviour (NEW) |
| NaN | mutex (NEW) |
| live | contractEnabled |
| vat | cdpEngine |
| vow | accountingEngine |
| file | modifyParameters |
| file | modifyParameters |
| flip | collateralAuctionHouse |
| cage | disableContract |
| NaN | protectCDP (NEW) |
| bite | liquidateCDP |
| urn | cdp |
| rate | accumulatedRates |
| ink | cdpCollateral |
| art | cdpDebt |
| lot | collateralToSell |
| grab | confiscateCDPCollateralAndDebt |
| fess | pushDebtToQueue |
| gal | initialBidder |
| tab | amountToRaise |
| bid | initialBid |
| Bite | Liquidate |

| Spot/ter | OracleRelayer |
| --- | --- |
| wards | authorizedAccounts |                                  
| rely | addAuthorization |                
| deny | removeAuthorization |            
| auth | isAuthorized |
| Ilk | CollateralType |
| Ilk.pip | CollateralType.orcl |
| Ilk.mat | CollateralType.safetyCRatio |
| NaN | CollateralType.liquidationCRatio (NEW) |
| ilks | collateralTypes |
| vat | cdpEngine |
| par | redemptionPrice |
| NaN | redemptionPriceUpdateTime (NEW) |
| live | contractEnabled |
| Poke | UpdateCollateralPrice |
| file | modifyParameters |
| NaN | updateRedemptionPrice (NEW) |
| poke | updateCollateralPrice |
| cage | disableContract |

| Jug | TaxCollector |
| --- | --- |
| wards | authorizedAccounts |                                  
| rely | addAuthorization |                
| deny | removeAuthorization |            
| auth | isAuthorized |
| Ilk | CollateralType |
| Ilk.duty | CollateralType.stabilityFee |
| Ilk.rho | CollateralType.updateTime |
| NaN | TaxBucket (NEW) |
| NaN | TaxBucket.canTakeBackTax (NEW) |
| NaN | TaxBucket.taxPercentage (NEW) |
| ilks | collateralTypes |
| NaN | bucketTaxCut (NEW) |
| NaN | usedBucket (NEW) |
| NaN | bucketAccounts (NEW) |
| NaN | bucketRevenueSources (NEW) |
| NaN | buckets (NEW) |
| vat | cdpEngine |
| vow | accountingEngine |
| base | globalStabilityFee |
| NaN | bucketNonce (NEW) |
| NaN | maxBuckets (NEW) |
| NaN | latestBucket (NEW) |
| NaN | collateralList (NEW) |
| NaN | bucketList (NEW) |
| init | initializeCollateralType |
| file | modifyParameters |
| NaN | createBucket (NEW) |
| NaN | fixBucket (NEW) |
| NaN | collectedAllTax (NEW) |
| NaN | nextTaxationOutcome (NEW) |
| NaN | averageTaxationRate (NEW) |
| NaN | bucketListLength (NEW) |
| NaN | isBucket (NEW) |
| NaN | taxationOutcome (NEW) |
| drip | taxAll / taxSingle |

| Pot | CoinSavingsAccount |
| --- | --- |
| wards | authorizedAccounts |                                  
| rely | addAuthorization |                
| deny | removeAuthorization |            
| auth | isAuthorized |
| pie | savings |
| Pie | totalSavings |
| dsr | savingsRate |
| chi | accumulatedRates |
| vat | cdpEngine |
| file | modifyParameters |
| cage | disableContract |
| drip | updateAccumulatedRate |
| NaN | nextAccumulatedRate (NEW) |
| join | deposit |
| exit | withdraw |

| End | GlobalSettlement |
| --- | --- |
| wards | authorizedAccounts |                                  
| rely | addAuthorization |                
| deny | removeAuthorization |            
| auth | isAuthorized |
| vat | cdpEngine |
| cat | liquidationEngine |
| vow | accountingEngine |
| spot | oracleRelayer |
| pot | coinSavingsAccount |
| NaN | rateSetter (NEW) |
| NaN | stabilityFeeTreasury (NEW) |
| live | contractEnabled |
| when | shutdownTime |
| wait | shutdownCooldown |
| debt | outstandingCoinSupply |
| tag | finalCoinPerCollateralPrice |
| gap | collateralShortfall |
| Art | collateralTotalDebt |
| fix | collateralCashPrice |
| bag | coinBag |
| out | coinsUsedToRedeem |
| file | modifyParameters |
| cage | shutdownSystem / freezeCollateralType |
| skip | fastTrackAuction |
| skim | processCDP |
| urn | cdp |
| owe | amountOwed |
| free | freeCollateral |
| thaw | setOutstandingCoinSupply |
| flow | calculateCashPrice |
| pack | prepareCoinsForRedeeming |
| cash | redeemCollateral |

| Dai | Coin |
| --- | --- |
| wards | authorizedAccounts |                                  
| rely | addAuthorization |                
| deny | removeAuthorization |            
| auth | isAuthorized |

| Lib | Logging |
| --- | --- |
| note | emitLog |
