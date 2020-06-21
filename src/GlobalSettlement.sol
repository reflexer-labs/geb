/// GlobalSettlement.sol

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
// Copyright (C) 2018 Lev Livnev <lev@liv.nev.org.uk>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.5.15;

import "./Logging.sol";

contract CDPEngineLike {
    function coinBalance(address) external view returns (uint256);
    function collateralTypes(bytes32) external view returns (
        uint256 debtAmount,        // wad
        uint256 accumulatedRates,  // ray
        uint256 safetyPrice,       // ray
        uint256 debtCeiling,       // rad
        uint256 debtFloor,         // rad
        uint256 liquidationPrice   // ray
    );
    function cdps(bytes32,address) external view returns (
        uint256 lockedCollateral, // wad
        uint256 generatedDebt     // wad
    );
    function globalDebt() external returns (uint256);
    function transferInternalCoins(address src, address dst, uint256 rad) external;
    function approveCDPModification(address) external;
    function transferCollateral(bytes32 collateralType, address src, address dst, uint256 wad) external;
    function confiscateCDPCollateralAndDebt(bytes32 collateralType, address cdp, address collateralSource, address debtDestination, int256 deltaCollateral, int256 deltaDebt) external;
    function createUnbackedDebt(address debtDestination, address coinDestination, uint256 rad) external;
    function disableContract() external;
}
contract LiquidationEngineLike {
    function collateralTypes(bytes32) external returns (
        address collateralAuctionHouse,
        uint256 liquidationPenalty, // [ray]
        uint256 collateralToSel     // [wad]
    );
    function disableContract() external;
}
contract StabilityFeeTreasuryLike {
    function disableContract() external;
}
contract AccountingEngineLike {
    function disableContract() external;
}
contract CoinSavingsAccountLike {
    function disableContract() external;
}
contract RateSetterLike {
    function disableContract() external;
}
contract CollateralAuctionHouseLike {
    function bids(uint auctionId) external view returns (
        uint256 bidAmount,
        uint256 collateralToSell,
        address highBidder,
        uint48  bidExpiry,
        uint48  auctionDeadline,
        address forgoneCollateralReceiver,
        address auctionIncomeRecipient,
        uint256 amountToRaise
    );
    function terminateAuctionPrematurely(uint auctionId) external;
}
contract OracleLike {
    function read() external view returns (bytes32);
}
contract OracleRelayerLike {
    function redemptionPrice() external view returns (uint256);
    function collateralTypes(bytes32) external view returns (
        OracleLike orcl,
        uint256 safetyCRatio
    );
    function disableContract() external;
}

/*
    This is the Global Settlement module. It is an
    involved, stateful process that takes place over nine steps.
    First we freeze the system and lock the prices for each collateral type.
    1. `shutdownSystem()`:
        - freezes user entrypoints
        - cancels collateral/surplus auctions
        - starts cooldown period
    2. `freezeCollateralType(collateralType)`:
       - set the final price for each collateralType, reading off the price feed
    We must process some system state before it is possible to calculate
    the final coin / collateral price. In particular, we need to determine:
      a. `collateralShortfall` (considers under-collateralised CDPs)
      b. `outstandingCoinSupply` (after including system surplus / deficit)
    We determine (a) by processing all under-collateralised CDPs with
    `processRiskyCDP`:
    3. `processCDP(collateralType, cdp)`:
       - cancels CDP debt
       - any excess collateral remains
       - backing collateral taken
    We determine (b) by processing ongoing coin generating processes,
    i.e. auctions. We need to ensure that auctions will not generate any
    further coin income. In the two-way auction model this occurs when
    all auctions are in the reverse (`reduceAuctionedAmount`) phase. There are two ways
    of ensuring this:
    4.  i) `shutdownCooldown`: set the cooldown period to be at least as long as the
           longest auction duration, which needs to be determined by the
           shutdown administrator.
           This takes a fairly predictable time to occur but with altered
           auction dynamics due to the now varying price of coin.
       ii) `fastTrackAuction`: cancel all ongoing auctions and seize the collateral.
           This allows for faster processing at the expense of more
           processing calls. This option allows coin holders to retrieve
           their collateral faster.
           `fastTrackAuction(collateralType, auctionId)`:
            - cancel individual flip auctions in the `tend` (forward) phase
            - retrieves collateral and returns coin to bidder
            - `reduceAuctionedAmount` (reverse) phase auctions can continue normally
    Option (i), `shutdownCooldown`, is sufficient for processing the system
    settlement but option (ii), `fastTrackAuction`, will speed it up. Both options
    are available in this implementation, with `fastTrackAuction` being enabled on a
    per-auction basis.
    When a CDP has been processed and has no debt remaining, the
    remaining collateral can be removed.
    5. `freeCollateral(collateralType)`:
        - remove collateral from the caller's CDP
        - owner can call as needed
    After the processing period has elapsed, we enable calculation of
    the final price for each collateral type.
    6. `setOutstandingCoinSupply()`:
       - only callable after processing time period elapsed
       - assumption that all under-collateralised CDPs are processed
       - fixes the total outstanding supply of coin
       - may also require extra CDP processing to cover system surplus
    7. `calculateCashPrice(collateralType)`:
        - calculate `collateralCashPrice`
        - adjusts `collateralCashPrice` in the case of deficit / surplus
    At this point we have computed the final price for each collateral
    type and coin holders can now turn their coin into collateral. Each
    unit coin can claim a fixed basket of collateral.
    Coin holders must first `prepareCoinsForRedeeming` into a `coinBag`. Once prepared,
    coins cannot be transferred out of the bag. More coin can be added to a bag later.
    8. `prepareCoinsForRedeeming(coinAmount)`:
        - put some coin into a bag in preparation for `redeemCollateral`
    Finally, collateral can be obtained with `redeemCollateral`. The bigger the bag,
    the more collateral can be released.
    9. `redeemCollateral(collateralType, collateralAmount)`:
        - exchange some coin from your bag for gems from a specific collateral type
        - the amount of collateral available to redeem is limited by how big your bag is
*/

contract GlobalSettlement is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 1;
    }
    function removeAuthorization(address account) external emitLog isAuthorized {
      authorizedAccounts[account] = 0;
    }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "GlobalSettlement/account-not-authorized");
        _;
    }

    // --- Data ---
    CDPEngineLike            public cdpEngine;
    LiquidationEngineLike    public liquidationEngine;
    AccountingEngineLike     public accountingEngine;
    OracleRelayerLike        public oracleRelayer;
    CoinSavingsAccountLike   public coinSavingsAccount;
    RateSetterLike           public rateSetter;
    StabilityFeeTreasuryLike public stabilityFeeTreasury;

    uint256  public contractEnabled;
    uint256  public shutdownTime;
    uint256  public shutdownCooldown;
    uint256  public outstandingCoinSupply; // [rad]

    mapping (bytes32 => uint256) public finalCoinPerCollateralPrice;   // [ray]
    mapping (bytes32 => uint256) public collateralShortfall;    // [wad]
    mapping (bytes32 => uint256) public collateralTotalDebt;    // [wad]
    mapping (bytes32 => uint256) public collateralCashPrice;    // [ray]

    mapping (address => uint256)                      public coinBag;           // [wad]
    mapping (bytes32 => mapping (address => uint256)) public coinsUsedToRedeem; // [wad]

    // --- Init ---
    constructor() public {
        authorizedAccounts[msg.sender] = 1;
        contractEnabled = 1;
    }

    // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        z = x + y;
        require(z >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function min(uint x, uint y) internal pure returns (uint z) {
        return x <= y ? x : y;
    }
    uint constant WAD = 10 ** 18;
    uint constant RAY = 10 ** 27;
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, y) / RAY;
    }
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, RAY) / y;
    }
    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, WAD) / y;
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, address data) external emitLog isAuthorized {
        require(contractEnabled == 1, "GlobalSettlement/contract-not-enabled");
        if (parameter == "cdpEngine") cdpEngine = CDPEngineLike(data);
        else if (parameter == "liquidationEngine") liquidationEngine = LiquidationEngineLike(data);
        else if (parameter == "accountingEngine") accountingEngine = AccountingEngineLike(data);
        else if (parameter == "oracleRelayer") oracleRelayer = OracleRelayerLike(data);
        else if (parameter == "coinSavingsAccount") coinSavingsAccount = CoinSavingsAccountLike(data);
        else if (parameter == "rateSetter") rateSetter = RateSetterLike(data);
        else if (parameter == "stabilityFeeTreasury") stabilityFeeTreasury = StabilityFeeTreasuryLike(data);
        else revert("GlobalSettlement/modify-unrecognized-parameter");
    }
    function modifyParameters(bytes32 parameter, uint256 data) external emitLog isAuthorized {
        require(contractEnabled == 1, "GlobalSettlement/contract-not-enabled");
        if (parameter == "shutdownCooldown") shutdownCooldown = data;
        else revert("GlobalSettlement/modify-unrecognized-parameter");
    }

    // --- Settlement ---
    function shutdownSystem() external emitLog isAuthorized {
        require(contractEnabled == 1, "GlobalSettlement/contract-not-enabled");
        contractEnabled = 0;
        shutdownTime = now;
        cdpEngine.disableContract();
        liquidationEngine.disableContract();
        // Treasury must be disabled before accounting engine so all surplus is gathered in one place
        if (address(stabilityFeeTreasury) != address(0)) {
          stabilityFeeTreasury.disableContract();
        }
        accountingEngine.disableContract();
        oracleRelayer.disableContract();
        if (address(rateSetter) != address(0)) {
          rateSetter.disableContract();
        }
        if (address(coinSavingsAccount) != address(0)) {
          coinSavingsAccount.disableContract();
        }
    }

    function freezeCollateralType(bytes32 collateralType) external emitLog {
        require(contractEnabled == 0, "GlobalSettlement/contract-still-enabled");
        require(finalCoinPerCollateralPrice[collateralType] == 0, "GlobalSettlement/final-collateral-price-already-defined");
        (collateralTotalDebt[collateralType],,,,,) = cdpEngine.collateralTypes(collateralType);
        (OracleLike orcl,) = oracleRelayer.collateralTypes(collateralType);
        // redemptionPrice is a ray, orcl returns a wad
        finalCoinPerCollateralPrice[collateralType] = wdiv(oracleRelayer.redemptionPrice(), uint(orcl.read()));
    }
    function fastTrackAuction(bytes32 collateralType, uint256 auctionId) external emitLog {
        require(finalCoinPerCollateralPrice[collateralType] != 0, "GlobalSettlement/final-collateral-price-not-defined");

        (address auctionHouse_,,) = liquidationEngine.collateralTypes(collateralType);
        CollateralAuctionHouseLike collateralAuctionHouse = CollateralAuctionHouseLike(auctionHouse_);
        (, uint accumulatedRates,,,,) = cdpEngine.collateralTypes(collateralType);
        (uint bidAmount, uint collateralToSell,,,, address forgoneCollateralReceiver,, uint amountToRaise) = collateralAuctionHouse.bids(auctionId);

        cdpEngine.createUnbackedDebt(address(accountingEngine), address(accountingEngine), amountToRaise);
        cdpEngine.createUnbackedDebt(address(accountingEngine), address(this), bidAmount);
        cdpEngine.approveCDPModification(address(collateralAuctionHouse));
        collateralAuctionHouse.terminateAuctionPrematurely(auctionId);

        uint debt_ = amountToRaise / accumulatedRates;
        collateralTotalDebt[collateralType] = add(collateralTotalDebt[collateralType], debt_);
        require(int(collateralToSell) >= 0 && int(debt_) >= 0, "GlobalSettlement/overflow");
        cdpEngine.confiscateCDPCollateralAndDebt(collateralType, forgoneCollateralReceiver, address(this), address(accountingEngine), int(collateralToSell), int(debt_));
    }
    function processCDP(bytes32 collateralType, address cdp) external emitLog {
        require(finalCoinPerCollateralPrice[collateralType] != 0, "GlobalSettlement/final-collateral-price-not-defined");
        (, uint accumulatedRates,,,,) = cdpEngine.collateralTypes(collateralType);
        (uint cdpCollateral, uint cdpDebt) = cdpEngine.cdps(collateralType, cdp);

        uint amountOwed = rmul(rmul(cdpDebt, accumulatedRates), finalCoinPerCollateralPrice[collateralType]);
        uint minCollateral = min(cdpCollateral, amountOwed);
        collateralShortfall[collateralType] = add(
            collateralShortfall[collateralType],
            sub(amountOwed, minCollateral)
        );

        require(minCollateral <= 2**255 && cdpDebt <= 2**255, "GlobalSettlement/overflow");
        cdpEngine.confiscateCDPCollateralAndDebt(
            collateralType,
            cdp,
            address(this),
            address(accountingEngine),
            -int(minCollateral),
            -int(cdpDebt)
        );
    }
    function freeCollateral(bytes32 collateralType) external emitLog {
        require(contractEnabled == 0, "GlobalSettlement/contract-still-enabled");
        (uint cdpCollateral, uint cdpDebt) = cdpEngine.cdps(collateralType, msg.sender);
        require(cdpDebt == 0, "GlobalSettlement/art-not-zero");
        require(cdpCollateral <= 2**255, "GlobalSettlement/overflow");
        cdpEngine.confiscateCDPCollateralAndDebt(
          collateralType,
          msg.sender,
          msg.sender,
          address(accountingEngine),
          -int(cdpCollateral),
          0
        );
    }
    function setOutstandingCoinSupply() external emitLog {
        require(contractEnabled == 0, "GlobalSettlement/contract-still-enabled");
        require(outstandingCoinSupply == 0, "GlobalSettlement/outstanding-coin-supply-not-zero");
        require(cdpEngine.coinBalance(address(accountingEngine)) == 0, "GlobalSettlement/surplus-not-zero");
        require(now >= add(shutdownTime, shutdownCooldown), "GlobalSettlement/shutdown-cooldown-not-finished");
        outstandingCoinSupply = cdpEngine.globalDebt();
    }
    function calculateCashPrice(bytes32 collateralType) external emitLog {
        require(outstandingCoinSupply != 0, "GlobalSettlement/outstanding-coin-supply-zero");
        require(collateralCashPrice[collateralType] == 0, "GlobalSettlement/collateral-cash-price-already-defined");

        (, uint accumulatedRates,,,,) = cdpEngine.collateralTypes(collateralType);
        uint256 redemptionAdjustedDebt = rmul(
          rmul(collateralTotalDebt[collateralType], accumulatedRates), finalCoinPerCollateralPrice[collateralType]
        );
        collateralCashPrice[collateralType] = rdiv(
          mul(sub(redemptionAdjustedDebt, collateralShortfall[collateralType]), RAY), outstandingCoinSupply
        );
    }
    function prepareCoinsForRedeeming(uint256 coinAmount) external emitLog {
        require(outstandingCoinSupply != 0, "GlobalSettlement/outstanding-coin-supply-zero");
        cdpEngine.transferInternalCoins(msg.sender, address(accountingEngine), mul(coinAmount, RAY));
        coinBag[msg.sender] = add(coinBag[msg.sender], coinAmount);
    }
    function redeemCollateral(bytes32 collateralType, uint coinsAmount) external emitLog {
        require(collateralCashPrice[collateralType] != 0, "GlobalSettlement/collateral-cash-price-not-defined");
        cdpEngine.transferCollateral(
          collateralType,
          address(this),
          msg.sender,
          rmul(coinsAmount, collateralCashPrice[collateralType])
        );
        coinsUsedToRedeem[collateralType][msg.sender] = add(coinsUsedToRedeem[collateralType][msg.sender], coinsAmount);
        require(coinsUsedToRedeem[collateralType][msg.sender] <= coinBag[msg.sender], "GlobalSettlement/insufficient-bag-balance");
    }
}
