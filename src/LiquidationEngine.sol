/// LiquidationEngine.sol

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
// Copyright (C) 2020 Stefan C. Ionescu <stefanionescu@protonmail.com>
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

contract CollateralAuctionHouseLike {
    function startAuction(
      address cdp,
      address initialBidder,
      uint amountToRaise,
      uint collateralToSell,
      uint initialBid
    ) public returns (uint);
}
contract CDPSaviourLike {
    function saveCDP(address,bytes32,address) external returns (bool,uint256);
}
contract CDPEngineLike {
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
    function transferDebtAndCollateral(bytes32,address,address,address,int,int) external;
    function canModifyCDP(address, address) external view returns (bool);
    function allowCDPModification(address) external;
    function disallowCDPModification(address) external;
}
contract AccountingEngineLike {
    function addDebtInQueue(uint) external;
}

contract LiquidationEngine is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "LiquidationEngine/account-not-authorized");
        _;
    }
    // --- CDP Saviours ---
    mapping (address => uint) public cdpSaviours;
    function connectCDPSaviour(address saviour) external emitLog isAuthorized { cdpSaviours[saviour] = 1; }
    function disconnectCDPSaviour(address saviour) external emitLog isAuthorized { cdpSaviours[saviour] = 0; }

    // --- Data ---
    struct CollateralType {
        address collateralAuctionHouse;
        uint256 liquidationPenalty; // [ray]
        uint256 collateralToSell;   // [wad]
    }

    mapping (bytes32 => CollateralType)              public collateralTypes;
    mapping (bytes32 => mapping(address => address)) public chosenCDPSaviour;
    mapping (bytes32 => mapping(address => uint8))   public mutex;

    uint256 public contractEnabled;

    CDPEngineLike        public cdpEngine;
    AccountingEngineLike public accountingEngine;

    // --- Events ---
    event Liquidated(
      bytes32 indexed collateralType,
      address indexed cdp,
      uint256 collateralAmount,
      uint256 debtAmount,
      uint256 amountToRaise,
      address collateralAuctioner,
      uint256 auctionId
    );
    event SavedCDP(
      bytes32 indexed collateralType,
      address indexed cdp,
      uint256 collateralAdded
    );

    // --- Init ---
    constructor(address cdpEngine_) public {
        authorizedAccounts[msg.sender] = 1;
        cdpEngine = CDPEngineLike(cdpEngine_);
        contractEnabled = 1;
    }

    // --- Math ---
    uint constant RAY = 10 ** 27;

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, y) / RAY;
    }
    function min(uint x, uint y) internal pure returns (uint z) {
        if (x > y) { z = y; } else { z = x; }
    }

    // --- Utils ---
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, address data) external emitLog isAuthorized {
        if (parameter == "accountingEngine") accountingEngine = AccountingEngineLike(data);
        else revert("LiquidationEngine/modify-unrecognized-param");
    }
    function modifyParameters(bytes32 collateralType, bytes32 parameter, uint data) external emitLog isAuthorized {
        if (parameter == "liquidationPenalty") collateralTypes[collateralType].liquidationPenalty = data;
        else if (parameter == "collateralToSell") collateralTypes[collateralType].collateralToSell = data;
        else revert("LiquidationEngine/modify-unrecognized-param");
    }
    function modifyParameters(bytes32 collateralType, bytes32 parameter, address data) external emitLog isAuthorized {
        if (what == "collateralAuctionHouse") {
            cdpEngine.nope(collateralTypes[collateralType].collateralAuctionHouse);
            collateralType[collateralType].collateralAuctionHouse = data;
            cdpEngine.hope(data);
        }
        else revert("LiquidationEngine/modify-unrecognized-param");
    }
    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
    }

    // --- CDP Liquidation ---
    function protectCDP(bytes32 collateralType, address cdp, address saviour) external emitLog {
        require(cdpEngine.canModifyCDP(cdp, msg.sender), "LiquidationEngine/cannot-modify-this-cdp");
        require(saviour == address(0) || cdpSaviours[saviour] == 1, "LiquidationEngine/saviour-not-authorized");
        cdpSaviours[collateralType][cdp] = saviour;
    }
    function liquidateCDP(bytes32 collateralType, address cdp) external returns (uint auctionId) {
        require(mutex[collateralType][cdp] == 0, "LiquidationEngine/non-null-mutex");
        mutex[collateralType][cdp] = 1;

        (, uint accumulatedRates, , , , uint liquidationPrice) = cdpEngine.collateralTypes(collateralType);
        (uint cdpCollateral, uint cdpDebt) = cdpEngine.cdps(collateralType, cdp);

        require(contractEnabled == 1, "LiquidationEngine/contract-not-enabled");
        require(both(liquidationPrice > 0, mul(cdpCollateral, liquidationPrice) < mul(cdpDebt, accumulatedRates)), "LiquidationEngine/cdp-not-unsafe");

        //TODO: try/catch the cdp saviour call
        if (tasks[collateralType][cdp] != address(0) && jobs[tasks[collateralType][cdp]] == 1) {
          (bool ok, uint collateralAdded) = CDPSaviourLike(tasks[collateralType][urn]).help(msg.sender, collateralType, cdp);
          if (both(ok, collateralAdded > 0)) {
            emit SavedCDP(collateralType, cdp, collateralAdded);
          }
        }

        (, rate, , , , ) = vat.ilks(ilk);
        (ink, art)       = vat.urns(ilk, urn);

        if (both(liquidationPrice > 0, mul(cdpCollateral, liquidationPrice) < mul(cdpDebt, accumulatedRates))) {
          uint collateralToSell = min(cdpCollateral, collateralTypes[collateralType].lump);
          cdpDebt               = min(cdpDebt, mul(collateralToSell, cdpDebt) / cdpCollateral);

          require(collateralToSell <= 2**255 && cdpDebt <= 2**255, "LiquidationEngine/overflow");
          cdpEngine.transferDebtAndCollateral(collateralType, cdp, address(this), address(accountingEngine), -int(collateralToSell), -int(cdpDebt));

          accountingEngine.addDebtToQueue(mul(cdpDebt, accumulatedRates));

          auctionId = CollateralAuctionHouseLike(collateralTypes[collateralType].collateralAuctionHouse).startAuction(
            { cdp: cdp
            , initialBidder: address(accountingEngine)
            , amountToRaise: rmul(mul(cdpDebt, accumulatedRates), collateralTypes[collateralType].liquidationPenalty)
            , collateralToSell: collateralToSell
            , initialBid: 0
           });

          emit Liquidated(collateralType, cdp, collateralToSell, cdpDebt, mul(cdpDebt, accumulatedRates), collateralTypes[collateralType].collateralAuctionHouse, auctionId);
        }

        mutex[collateralType][cdp] = 0;
    }
}
