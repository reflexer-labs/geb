# Reflexer Protocol

This repository contains the core smart contract code for Reflexer Protocol.

# What is a Reflex-Bond?

A reflex-bond is a low volatility proxy for the underlying collateral that supports its value. The _future_ target price of a reflex-bond depends on the market price deviation from its _current_ target price. This means that even if it floats, the future target price of the bond is fairly predictable.

To summarise:

- It __is not__ meant to keep a strong peg to a certain value but rather float at fairly predictable rates
- It __is__ meant to be used as trustless collateral with minimum or even no admin control and as infrastructure for other synthetic assets to be built on top

# Technical Differences Compared to Dai Stablecoin System

- Reintroduction of the TRFM which replaces the savings account
- Multiple flavours of rate setters, some of them focusing on reflex-bonds, others on pegged coins
- Continuous update of spot.par, even when it's read
- Apart from 'spot', we added 'risk'. CDP creators use spot when creating bonds/pegged coins but get liquidated at risk. An incentive mechanism for keeping CDPs above spot is still being designed
- A second Flapper version that buys protocol tokens from DEXs and burns them
- A CDP holder can specify a trigger for when their CDP gets bitten. The trigger can, for example, sell a position in another protocol and add more collateral in the CDP, thus saving it from liquidation
- Jug can drip stability fees in multiple contracts at once
- (TODO) default scenarios for triggering End without the need for ESM (in a separate repo)
