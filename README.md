# Mai Reflex-Bond System

This repository contains the core smart contract code for Mai Reflex-Bond System.

# Differences Compared to Dai

- Reintroduction of the TRFM
- Apart from 'spot', we added 'risk'. CDP creators use spot when creating Mai but get liquidated at risk
- The Flapper no longer allows auctions but directly buys governance tokens from DEXs and burns them
- A CDP holder can specify a trigger for when their CDP gets bitten. The trigger can, for example, sell a position in another protocol and add more collateral in the CDP, thus saving it from liquidation
