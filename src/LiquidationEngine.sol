/// LiquidationEngine.sol

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
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

pragma solidity ^0.6.7;

abstract contract CollateralAuctionHouseLike {
    function startAuction(
      address forgoneCollateralReceiver,
      address initialBidder,
      uint amountToRaise,
      uint collateralToSell,
      uint initialBid
    ) virtual public returns (uint);
}
abstract contract CDPSaviourLike {
    function saveCDP(address,bytes32,address) virtual external returns (bool,uint256,uint256);
}
abstract contract CDPEngineLike {
    function collateralTypes(bytes32) virtual public view returns (
        uint256 debtAmount,        // [wad]
        uint256 accumulatedRate,   // [ray]
        uint256 safetyPrice,       // [ray]
        uint256 debtCeiling,       // [rad]
        uint256 debtFloor,         // [rad]
        uint256 liquidationPrice   // [ray]
    );
    function cdps(bytes32,address) virtual public view returns (
        uint256 lockedCollateral,  // [wad]
        uint256 generatedDebt      // [wad]
    );
    function confiscateCDPCollateralAndDebt(bytes32,address,address,address,int,int) virtual external;
    function canModifyCDP(address, address) virtual public view returns (bool);
    function approveCDPModification(address) virtual external;
    function denyCDPModification(address) virtual external;
}
abstract contract AccountingEngineLike {
    function pushDebtToQueue(uint) virtual external;
}

contract LiquidationEngine {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 1;
        emit AddAuthorization(account);
    }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(address account) external isAuthorized {
        authorizedAccounts[account] = 0;
        emit RemoveAuthorization(account);
    }
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
    /**
    * @notice Authed function to add contracts that can save CDPs from liquidation
    * @param saviour CDP saviour contract to be whitelisted
    **/
    function connectCDPSaviour(address saviour) external isAuthorized {
        (bool ok, uint256 collateralAdded, uint256 liquidatorReward) =
          CDPSaviourLike(saviour).saveCDP(address(this), "", address(0));
        require(ok, "LiquidationEngine/saviour-not-ok");
        require(both(collateralAdded == uint(-1), liquidatorReward == uint(-1)), "LiquidationEngine/invalid-amounts");
        cdpSaviours[saviour] = 1;
        emit ConnectCDPSaviour(saviour);
    }
    /**
    * @notice Governance used function to remove contracts that can save CDPs from liquidation
    * @param saviour CDP saviour contract to be removed
    **/
    function disconnectCDPSaviour(address saviour) external isAuthorized {
        cdpSaviours[saviour] = 0;
        emit DisconnectCDPSaviour(saviour);
    }

    // --- Data ---
    struct CollateralType {
        // Address of the collateral auction house handling liquidations for this collateral type
        address collateralAuctionHouse;
        // Penalty applied to every liquidation involving this collateral type. Discourages CDP users from bidding on their own CDPs
        uint256 liquidationPenalty;                                                                                                   // [ray]
        // Max amount of collateral to sell in one auction
        uint256 collateralToSell;                                                                                                     // [wad]
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
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event ConnectCDPSaviour(address saviour);
    event DisconnectCDPSaviour(address saviour);
    event ModifyParameters(bytes32 parameter, address data);
    event ModifyParameters(
      bytes32 collateralType,
      bytes32 parameter,
      uint data
    );
    event ModifyParameters(
      bytes32 collateralType,
      bytes32 parameter,
      address data
    );
    event DisableContract();
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
    event FailedCDPSave(bytes failReason);
    event ProtectCDP(
      bytes32 collateralType,
      address cdp,
      address saviour
    );

    // --- Init ---
    constructor(address cdpEngine_) public {
        authorizedAccounts[msg.sender] = 1;
        cdpEngine = CDPEngineLike(cdpEngine_);
        contractEnabled = 1;
        emit AddAuthorization(msg.sender);
    }

    // --- Math ---
    uint constant RAY = 10 ** 27;

    function multiply(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rmultiply(uint x, uint y) internal pure returns (uint z) {
        z = multiply(x, y) / RAY;
    }
    function minimum(uint x, uint y) internal pure returns (uint z) {
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
    function modifyParameters(bytes32 parameter, address data) external isAuthorized {
        if (parameter == "accountingEngine") accountingEngine = AccountingEngineLike(data);
        else revert("LiquidationEngine/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
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
    ) external isAuthorized {
        if (parameter == "liquidationPenalty") collateralTypes[collateralType].liquidationPenalty = data;
        else if (parameter == "collateralToSell") collateralTypes[collateralType].collateralToSell = data;
        else revert("LiquidationEngine/modify-unrecognized-param");
        emit ModifyParameters(
          collateralType,
          parameter,
          data
        );
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
    ) external isAuthorized {
        if (parameter == "collateralAuctionHouse") {
            cdpEngine.denyCDPModification(collateralTypes[collateralType].collateralAuctionHouse);
            collateralTypes[collateralType].collateralAuctionHouse = data;
            cdpEngine.approveCDPModification(data);
        }
        else revert("LiquidationEngine/modify-unrecognized-param");
        emit ModifyParameters(
            collateralType,
            parameter,
            data
        );
    }
    /**
     * @notice Disable this contract (normally called by GlobalSettlement)
     */
    function disableContract() external isAuthorized {
        contractEnabled = 0;
        emit DisableContract();
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
    ) external {
        require(cdpEngine.canModifyCDP(cdp, msg.sender), "LiquidationEngine/cannot-modify-this-cdp");
        require(saviour == address(0) || cdpSaviours[saviour] == 1, "LiquidationEngine/saviour-not-authorized");
        chosenCDPSaviour[collateralType][cdp] = saviour;
        emit ProtectCDP(
            collateralType,
            cdp,
            saviour
        );
    }
    /**
     * @notice Liquidate a CDP
     * @param collateralType The CDP's collateral type
     * @param cdp The CDP's address
     */
    function liquidateCDP(bytes32 collateralType, address cdp) external returns (uint auctionId) {
        require(mutex[collateralType][cdp] == 0, "LiquidationEngine/non-null-mutex");
        mutex[collateralType][cdp] = 1;

        (, uint accumulatedRate, , , , uint liquidationPrice) = cdpEngine.collateralTypes(collateralType);
        (uint cdpCollateral, uint cdpDebt) = cdpEngine.cdps(collateralType, cdp);

        require(contractEnabled == 1, "LiquidationEngine/contract-not-enabled");
        require(both(
          liquidationPrice > 0,
          multiply(cdpCollateral, liquidationPrice) < multiply(cdpDebt, accumulatedRate)
        ), "LiquidationEngine/cdp-not-unsafe");

        if (chosenCDPSaviour[collateralType][cdp] != address(0) &&
            cdpSaviours[chosenCDPSaviour[collateralType][cdp]] == 1) {
          try CDPSaviourLike(chosenCDPSaviour[collateralType][cdp]).saveCDP(msg.sender, collateralType, cdp)
            returns (bool ok, uint256 collateralAdded, uint256) {
            if (both(ok, collateralAdded > 0)) {
              emit SaveCDP(collateralType, cdp, collateralAdded);
            }
          } catch (bytes memory revertReason) {
            emit FailedCDPSave(revertReason);
          }
        }

        (, accumulatedRate, , , , liquidationPrice) = cdpEngine.collateralTypes(collateralType);
        (cdpCollateral, cdpDebt) = cdpEngine.cdps(collateralType, cdp);

        if (both(liquidationPrice > 0, multiply(cdpCollateral, liquidationPrice) < multiply(cdpDebt, accumulatedRate))) {
          uint collateralToSell = minimum(cdpCollateral, collateralTypes[collateralType].collateralToSell);
          cdpDebt               = minimum(cdpDebt, multiply(collateralToSell, cdpDebt) / cdpCollateral);

          require(collateralToSell <= 2**255 && cdpDebt <= 2**255, "LiquidationEngine/overflow");
          cdpEngine.confiscateCDPCollateralAndDebt(
            collateralType, cdp, address(this), address(accountingEngine), -int(collateralToSell), -int(cdpDebt)
          );

          accountingEngine.pushDebtToQueue(multiply(cdpDebt, accumulatedRate));

          auctionId = CollateralAuctionHouseLike(collateralTypes[collateralType].collateralAuctionHouse).startAuction(
            { forgoneCollateralReceiver: cdp
            , initialBidder: address(accountingEngine)
            , amountToRaise: rmultiply(multiply(cdpDebt, accumulatedRate), collateralTypes[collateralType].liquidationPenalty)
            , collateralToSell: collateralToSell
            , initialBid: 0
           });

          emit Liquidate(collateralType, cdp, collateralToSell, cdpDebt, multiply(cdpDebt, accumulatedRate), collateralTypes[collateralType].collateralAuctionHouse, auctionId);
        }

        mutex[collateralType][cdp] = 0;
    }
}
