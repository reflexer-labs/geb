/// OracleRelayer.sol

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
    function modifyParameters(bytes32, bytes32, uint) external;
}

contract OracleLike {
    function getPriceWithValidity() external returns (bytes32, bool);
}

contract OracleRelayer is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "OracleRelayer/account-not-authorized");
        _;
    }

    // --- Data ---
    struct CollateralType {
        OracleLike orcl;
        uint256 safetyCRatio;
        uint256 liquidationCRatio;
    }

    mapping (bytes32 => CollateralType) public collateralTypes;

    CDPEngineLike public cdpEngine;
    uint256 public redemptionRate;
    uint256 public redemptionPriceUpdateTime;
    uint256 public contractEnabled;

    uint256 internal _redemptionPrice; // virtual redemption price

    // --- Events ---
    event UpdateCollateralPrice(
      bytes32 collateralType,
      bytes32 priceFeed,
      uint256 safetyPrice,
      uint256 liquidationPrice
    );

    // --- Init ---
    constructor(address cdpEngine_) public {
        authorizedAccounts[msg.sender] = 1;
        cdpEngine  = CDPEngineLike(cdpEngine_);
        _redemptionPrice = RAY;
        redemptionRate   = RAY;
        redemptionPriceUpdateTime  = now;
        contractEnabled = 1;
    }

    // --- Math ---
    uint constant RAY = 10 ** 27;

    function sub(uint x, uint y) internal pure returns (uint z) {
        z = x - y;
        require(z <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        // alsites rounds down
        z = mul(x, y) / RAY;
    }
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, RAY) / y;
    }
    function rpow(uint x, uint n, uint base) internal pure returns (uint z) {
        assembly {
            switch x case 0 {switch n case 0 {z := base} default {z := 0}}
            default {
                switch mod(n, 2) case 0 { z := base } default { z := x }
                let half := div(base, 2)  // for rounding.
                for { n := div(n, 2) } n { n := div(n,2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0,0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0,0) }
                    x := div(xxRound, base)
                    if mod(n,2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0,0) }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }

    // --- Administration ---
    function modifyParameters(bytes32 collateralType, bytes32 parameter, address orcl_) external emitLog isAuthorized {
        require(contractEnabled == 1, "OracleRelayer/contract-not-enabled");
        if (parameter == "orcl") collateralTypes[collateralType].orcl = OracleLike(orcl_);
        else revert("OracleRelayer/modify-unrecognized-param");
    }
    function modifyParameters(bytes32 parameter, uint data) external emitLog isAuthorized {
        require(contractEnabled == 1, "OracleRelayer/contract-not-enabled");
        require(data > 0, "OracleRelayer/null-data");
        if (parameter == "redemptionPrice") _redemptionPrice = data;
        else if (parameter == "redemptionRate") {
          require(now == redemptionPriceUpdateTime, "OracleRelayer/redemption-price-not-updated");
          redemptionRate = data;
        }
        else revert("OracleRelayer/modify-unrecognized-param");
    }
    function modifyParameters(bytes32 collateralType, bytes32 parameter, uint data) external emitLog isAuthorized {
        require(contractEnabled == 1, "OracleRelayer/contract-not-enabled");
        if (parameter == "safetyCRatio") {
          require(data <= collateralTypes[collateralType].liquidationCRatio, "OracleRelayer/mat-lower-than-tam");
          collateralTypes[collateralType].safetyCRatio = data;
        }
        else if (parameter == "liquidationCRatio") {
          require(data >= collateralTypes[collateralType].safetyCRatio, "OracleRelayer/tam-bigger-than-mat");
          collateralTypes[collateralType].liquidationCRatio = data;
        }
        else revert("OracleRelayer/modify-unrecognized-param");
    }

    // --- Redemption Price Update ---
    function updateRedemptionPrice() public emitLog returns (uint) {
        // Update redemption price
        _redemptionPrice = rmul(rpow(redemptionRate, sub(now, redemptionPriceUpdateTime), RAY), _redemptionPrice);
        redemptionPriceUpdateTime = now;
        // Return updated redemption price
        return _redemptionPrice;
    }
    function redemptionPrice() public returns (uint) {
        if (now > redemptionPriceUpdateTime) return updateRedemptionPrice();
        return _redemptionPrice;
    }

    // --- Update value ---
    function updateCollateralPrice(bytes32 collateralType) external {
        (bytes32 priceFeedValue, bool hasValidValue) = collateralTypes[collateralType].orcl.getPriceWithValidity();
        uint redemptionPrice_ = redemptionPrice();
        uint256 safetyPrice_ = hasValidValue ? rdiv(rdiv(mul(uint(priceFeedValue), 10 ** 9), redemptionPrice_), collateralTypes[collateralType].safetyCRatio) : 0;
        uint256 liquidationPrice_ = (hasValidValue && collateralTypes[collateralType].liquidationCRatio > 0) ? rdiv(rdiv(mul(uint(priceFeedValue), 10 ** 9), redemptionPrice_), collateralTypes[collateralType].liquidationCRatio) : 0;
        cdpEngine.modifyParameters(collateralType, "safetyPrice", safetyPrice_);
        cdpEngine.modifyParameters(collateralType, "liquidationPrice", liquidationPrice_);
        emit UpdateCollateralPrice(collateralType, priceFeedValue, safetyPrice_, liquidationPrice_);
    }

    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
    }

    function safetyCRatio(bytes32 collateralType) public view returns (uint256) {
        return collateralTypes[collateralType].safetyCRatio;
    }

    function liquidationCRatio(bytes32 collateralType) public view returns (uint256) {
        return collateralTypes[collateralType].liquidationCRatio;
    }

    function orcl(bytes32 collateralType) public view returns (address) {
        return address(collateralTypes[collateralType].orcl);
    }
}
