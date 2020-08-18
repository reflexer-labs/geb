# GEB

This repository contains the core smart contract code for GEB. GEB is the abbreviation of [Gödel, Escher and Bach](https://en.wikipedia.org/wiki/G%C3%B6del,_Escher,_Bach) as well as the name of an [Egyptian god](https://en.wikipedia.org/wiki/Geb).

While we intend to use the "GEB" terminology when we discuss about core architecture, the actual instrument issued by the protocol is called a reflex bond.

# What is a Reflex Bond?

A reflex bond is an asset that mirrors the price movements of its collateral in a dampened way (and with lags between the underlying changing its value and the reflex bond system reacting to that). The _future_ redemption price of a reflex bond depends on the market price deviation from its _current_ redemption price. For more details, check the [whitepaper](https://github.com/reflexer-labs/whitepapers/blob/master/rai.pdf).

Check out the more in-depth [documentation](https://docs.reflexer.finance/).
