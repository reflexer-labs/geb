# GEB

This repository contains the core smart contract code for Generalized Ethereum Bonds. While we intend to use the "GEB" terminology when we discuss about core architecture, the actual instrument issued by the protocol is called a reflex bond.

# What is a Reflex Bond?

A reflex-bond is an asset that mirrors the price movements of its collateral in a dampened way (and with lags between the underlying changing its value and the reflex bond system reacting to that). The _future_ redemption price of a reflex bond depends on the market price deviation from its _current_ redemption. For more details, check the [whitepaper](https://github.com/reflexer-labs/whitepapers/blob/master/rai.pdf).

# Differences Compared to Multi Collateral Dai (MCD)

## Insurance for CDPs

GEB creators can allow CDP users to specify "trigger" contracts that protect them against liquidation. A trigger is called when a keeper calls the *liquidateCDP* function (previously *bite*) from LiquidationEngine (previously Cat). The trigger can, for example, sell a short position and add the proceeds to a CDP, thus saving it from the CollateralAuctionHouse (previously Flip/per).

Trigger integrations need to be thoroughly audited because there is the risk that too little collateral is locked in a CollateralJoin adapter (previously GemJoin) and too much is added in the CDPEngine (previously Vat). A bug like this would allow a CDP user to generate GEB that is not covered by enough (or any) collateral.

## Two CDP Ratio Thresholds

CDP users can generate GEB until they hit the *safeCRatio* but they will only get liquidated when the CDP's ratio goes under *liquidationCRatio*. liquidationCRatio must be smaller than or equal to safeCRatio.

## Redemption Rate

The redemption rate is a variable inside Oracle Relayer (previously Spot/ter) that acts similarly to an interest rate which is applied to the redemption price (previously par). As described in our first [whitepaper](https://github.com/reflexer-labs/whitepapers/blob/master/rai.pdf), the redemption rate is the main driving force that changes the incentives of system participants.

## Stability Fee Treasury

The [treasury](https://github.com/reflexer-labs/geb/blob/master/src/StabilityFeeTreasury.sol) is in charge with paying for oracle calls, paying collateral onboarding teams (in some GEB versions) and providing funds for on-chain market making. It can be set up to transfer some of its funds into the AccountingEngine (previously Vow) in case the predicted costs for maintaining the system in the next *P* seconds are lower than the currently available treasury surplus.

## Settlement Surplus Auctioner

This contract auctions all the remaining surplus after GlobalSettlement (previously End) shuts down the system and the AccountingEngine settles as much debt as possible.

We are looking at alternative ways to drain the extra surplus without giving CDP users, GEB or protocol token holders any advantage when the system settles.

## Debt Auction Bid Target

Governance can set a variable called *debtAuctionBidTarget* which can be used to autonomously determine how much debt is auctioned in a debt auction and also the initial proposed protocol token bid.

## Variable Names You Can Actually Understand :astonished:

The following tables show the before and after variable names

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
