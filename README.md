# Mai Reflex-Bond System

This repository contains the core smart contract code for Mai Reflex-Bond System.

# Differences Compared to Dai

- Reintroduction of the TRFM
- Apart from 'spot', we added 'risk'. CDP creators use spot when creating Mai but get liquidated at risk
- A guard against flash CDPs. CDP creators need to wait for the span of one block since they open a CDP in order to close it
- The Flapper no longer allows auctions but directly buys governance tokens from DEXs and burns them
- Cat and Flipper can 'ping' an insurance contract about the outcome of debt auctions. If an auction penalizes a CDP more than a certain threshold, the CDP creator can automatically get reimbursed
- A CDP holder can specify a trigger for when their CDP gets bitten. The trigger can, for example, sell a position in another protocol and add more collateral in the CDP, thus saving it from liquidation

## LICENSE

Copyright (C) 2016-2020 Maker Ecosystem Growth Holdings, Inc

Copyright (C) 2017-2020 DappHub, LLC

Copyright (C) 2020      Stefan C. Ionescu <stefanionescu@protonmail.com>

This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License along with this program. If not, see https://www.gnu.org/licenses/.
