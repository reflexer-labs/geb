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
      address forgoneCollateralReceiver,
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
    function confiscateCDPCollateralAndDebt(bytes32,address,address,address,int,int) external;
    function canModifyCDP(address, address) external view returns (bool);
    function approveCDPModification(address) external;
    function denyCDPModification(address) external;
}
contract AccountingEngineLike {
    function pushDebtToQueue(uint) external;
}

contract LiquidationEngine is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "LiquidationEngine/account-not-authorized");
        _;
    }
    // --- CDP Saviours ---
    // Contracts that can save CDPs from liquidation
    mapping (address => uint) public cdpSaviours;
    // Governance used function to add contracts that can save CDPs from liquidation
    function connectCDPSaviour(address saviour) external emitLog isAuthorized { cdpSaviours[saviour] = 1; }
    // Governance used function to remove contracts that can save CDPs from liquidation
    function disconnectCDPSaviour(address saviour) external emitLog isAuthorized { cdpSaviours[saviour] = 0; }

    // --- Data ---
    struct CollateralType {
        address collateralAuctionHouse;
        uint256 liquidationPenalty; // [ray]
        uint256 collateralToSell;   // [wad]
    }

    // Collateral types included in the system
    mapping (bytes32 => CollateralType)              public collateralTypes;
    // Saviour contract chosed for each CDP by its creator
    mapping (bytes32 => mapping(address => address)) public chosenCDPSaviour;
    // Mutex used to block against re-entrancy when 'liquidateCDP' passes execution to a saviour
    mapping (bytes32 => mapping(address => uint8))   public mutex;

    // Whether this contract is enabled
    uint256 public contractEnabled;

    CDPEngineLike        public cdpEngine;
    AccountingEngineLike public accountingEngine;

    // --- Events ---
    event Liquidate(
      bytes32 indexed collateralType,
      address indexed cdp,
      uint256 collateralAmount,
      uint256 debtAmount,
      uint256 amountToRaise,
      address collateralAuctioneer,
      uint256 auctionId
    );
    event SaveCDP(
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
    /**
     * @notice Modify contract integrations
     * @param parameter The name of the parameter modified
     * @param data New address for the parameter
     */
    function modifyParameters(bytes32 parameter, address data) external emitLog isAuthorized {
        if (parameter == "accountingEngine") accountingEngine = AccountingEngineLike(data);
        else revert("LiquidationEngine/modify-unrecognized-param");
    }
    /**
     * @notice Modify liquidation params
     * @param collateralType The collateral type we change parameters for
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(
        bytes32 collateralType,
        bytes32 parameter,
        uint data
    ) external emitLog isAuthorized {
        if (parameter == "liquidationPenalty") collateralTypes[collateralType].liquidationPenalty = data;
        else if (parameter == "collateralToSell") collateralTypes[collateralType].collateralToSell = data;
        else revert("LiquidationEngine/modify-unrecognized-param");
    }
    /**
     * @notice Modify collateral auction integration
     * @param collateralType The collateral type we change parameters for
     * @param parameter The name of the integration modified
     * @param data New address for the integration contract
     */
    function modifyParameters(
        bytes32 collateralType,
        bytes32 parameter,
        address data
    ) external emitLog isAuthorized {
        if (parameter == "collateralAuctionHouse") {
            cdpEngine.denyCDPModification(collateralTypes[collateralType].collateralAuctionHouse);
            collateralTypes[collateralType].collateralAuctionHouse = data;
            cdpEngine.approveCDPModification(data);
        }
        else revert("LiquidationEngine/modify-unrecognized-param");
    }
    /**
     * @notice Disable this contract (normally called by GlobalSettlement)
     */
    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
    }

    // --- CDP Liquidation ---
    /**
     * @notice Choose a saviour contract for your CDP
     * @param collateralType The CDP's collateral type
     * @param cdp The CDP's address
     * @param saviour The chosen saviour
     */
    function protectCDP(
        bytes32 collateralType,
        address cdp,
        address saviour
    ) external emitLog {
        require(cdpEngine.canModifyCDP(cdp, msg.sender), "LiquidationEngine/cannot-modify-this-cdp");
        require(saviour == address(0) || cdpSaviours[saviour] == 1, "LiquidationEngine/saviour-not-authorized");
        chosenCDPSaviour[collateralType][cdp] = saviour;
    }
    /**
     * @notice Liquidate a CDP
     * @param collateralType The CDP's collateral type
     * @param cdp The CDP's address
     */
    function liquidateCDP(bytes32 collateralType, address cdp) external returns (uint auctionId) {
        require(mutex[collateralType][cdp] == 0, "LiquidationEngine/non-null-mutex");
        mutex[collateralType][cdp] = 1;

        (, uint accumulatedRates, , , , uint liquidationPrice) = cdpEngine.collateralTypes(collateralType);
        (uint cdpCollateral, uint cdpDebt) = cdpEngine.cdps(collateralType, cdp);

        require(contractEnabled == 1, "LiquidationEngine/contract-not-enabled");
        require(both(
          liquidationPrice > 0,
          mul(cdpCollateral, liquidationPrice) < mul(cdpDebt, accumulatedRates)
        ), "LiquidationEngine/cdp-not-unsafe");

        //TODO: try/catch the cdp saviour call
        if (chosenCDPSaviour[collateralType][cdp] != address(0) &&
            cdpSaviours[chosenCDPSaviour[collateralType][cdp]] == 1) {
          (bool ok, uint collateralAdded) =
            CDPSaviourLike(chosenCDPSaviour[collateralType][cdp]).saveCDP(msg.sender, collateralType, cdp);
          if (both(ok, collateralAdded > 0)) {
            emit SaveCDP(collateralType, cdp, collateralAdded);
          }
        }

        (, accumulatedRates, , , , liquidationPrice) = cdpEngine.collateralTypes(collateralType);
        (cdpCollateral, cdpDebt) = cdpEngine.cdps(collateralType, cdp);

        if (both(liquidationPrice > 0, mul(cdpCollateral, liquidationPrice) < mul(cdpDebt, accumulatedRates))) {
          uint collateralToSell = min(cdpCollateral, collateralTypes[collateralType].collateralToSell);
          cdpDebt               = min(cdpDebt, mul(collateralToSell, cdpDebt) / cdpCollateral);

          require(collateralToSell <= 2**255 && cdpDebt <= 2**255, "LiquidationEngine/overflow");
          cdpEngine.confiscateCDPCollateralAndDebt(
            collateralType, cdp, address(this), address(accountingEngine), -int(collateralToSell), -int(cdpDebt)
          );

          accountingEngine.pushDebtToQueue(mul(cdpDebt, accumulatedRates));

          auctionId = CollateralAuctionHouseLike(collateralTypes[collateralType].collateralAuctionHouse).startAuction(
            { forgoneCollateralReceiver: cdp
            , initialBidder: address(accountingEngine)
            , amountToRaise: rmul(mul(cdpDebt, accumulatedRates), collateralTypes[collateralType].liquidationPenalty)
            , collateralToSell: collateralToSell
            , initialBid: 0
           });

          emit Liquidate(collateralType, cdp, collateralToSell, cdpDebt, mul(cdpDebt, accumulatedRates), collateralTypes[collateralType].collateralAuctionHouse, auctionId);
        }

        mutex[collateralType][cdp] = 0;
    }
}
