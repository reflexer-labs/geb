# Mai Reflex-Bond System

This repository contains the core smart contract code for Mai Reflex-Bond System.

# What is a Reflex-Bond?

A reflex-bond is a low volatility proxy for the underlying collateral that supports its value. The _future_ price change for a reflex-bond depends on the market price deviation from its _current_ price.

It __is not__ meant to keep a peg to a certain value but rather float at fairly predictable rates. It __is__ meant to be used as trustless collateral with minimum or even no admin control and as infrastructure for other synthetic assets to be built on top.

# Technical Differences Compared to Dai

- Reintroduction of the TRFM which replaces the savings account
- Apart from 'spot', we added 'risk'. CDP creators use spot when creating Mai but get liquidated at risk. An incentive mechanism for keeping CDPs above spot is still being designed
- The Flapper no longer allows auctions but directly buys governance tokens from DEXs and burns them
- A CDP holder can specify a trigger for when their CDP gets bitten. The trigger can, for example, sell a position in another protocol and add more collateral in the CDP, thus saving it from liquidation
