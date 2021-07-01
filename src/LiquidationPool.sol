/// LiquidationPool.sol

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

pragma solidity 0.6.7;

abstract contract SAFEEngineLike {
    function tokenCollateral(bytes32, address) virtual external view returns (uint256);
    function transferCollateral(bytes32 collateralType, address src, address dst, uint256 wad) virtual external;
}
abstract contract CoinJoinLike {
    function systemCoin() virtual public view returns (address);
    function safeEngine() virtual public view returns (address);
    function join(address, uint256) virtual external;
}
abstract contract SystemCoinLike {
    function approve(address, uint256) virtual public returns (uint256);
    function transfer(address,uint256) virtual public returns (bool);
    function transferFrom(address,address,uint256) virtual public returns (bool);
}

contract LiquidationPool {
    // --- Auth ---
    mapping (address => uint256) public authorizedAccounts;
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
        require(authorizedAccounts[msg.sender] == 1, "LiquidationPool/account-not-authorized");
        _;
    }

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event ModifyParameters(bytes32 parameter, address data);
    event DisableContract();
    event Deposit(address usr, uint256 volume);
    event WithdrawSystemCoins(address usr, uint256 volume);
    event WithdrawRewards(address usr, uint256 volume);
    event PoolLiquidatedSafe(uint256 systemCoinsDestoyed);

    // --- Data ---
    // Share of system coins available to each user which determines share of new rewards
    mapping (address => uint256) public sysCoinShares;
    uint256 public totalSysCoinShares;
    uint256 public pooledSystemCoins;

    // Offset of rewards for each user. This allows efficient rewards while also allowing users to join when there are pending rewards for
    // the pool.
    mapping (address => uint256) public negativeRewardOffsets;
    uint256 public totalNegativeOffsets;
    mapping (address => uint256) public positiveRewardOffsets;
    uint256 public totalPositiveOffsets;

    // SAFE database
    SAFEEngineLike public safeEngine;
    // The ERC20 system coin
    SystemCoinLike public systemCoin;
    // The system coin join contract
    CoinJoinLike public coinJoin;
    // Whether this contract is enabled or not
    uint256 public contractEnabled;
    // Collateral type used by this pool
    bytes32 collateralType;

    // --- Init ---
    constructor(address coinJoin_, bytes32 collateralType_) public {
        authorizedAccounts[msg.sender] = 1;
        coinJoin = CoinJoinLike(coinJoin_);
        systemCoin = SystemCoinLike(coinJoin.systemCoin());
        safeEngine = SAFEEngineLike(coinJoin.safeEngine());
        collateralType = collateralType_;
        contractEnabled = 1;
    }

    // --- Math ---
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "LiquidationPool/add-overflow");
    }
    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "LiquidationPool/sub-underflow");
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "LiquidationPool/mul-overflow");
    }
    function wdivide(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0, "LiquidationPool/wdiv-by-zero");
        z = multiply(x, WAD) / y;
    }
    function wmultiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = multiply(x, y) / WAD;
    }

    /**
     * @notice Disable this contract (usually called by Global Settlement)
     */
    function disableContract() external isAuthorized {
        contractEnabled = 0;
        emit DisableContract();
    }

    /**
     * @notice Deposit coins to be used in liquidations
     * @param wad Amount of system coins to deposit (expressed as an 18 decimal number).
     */
    function deposit(uint256 wad) external {
        uint256 newShares = wmultiply(wad, systemCoinsToShares());
        sysCoinShares[msg.sender] = addition(sysCoinShares[msg.sender], newShares);

        uint256 newOffset = virtualCollateral();
        if(totalSysCoinShares > 0) {
            newOffset = wmultiply(wdivide(newShares, totalSysCoinShares), newOffset);
        }
        totalNegativeOffsets = addition(totalNegativeOffsets, newOffset);
        negativeRewardOffsets[msg.sender] = addition(negativeRewardOffsets[msg.sender], newOffset);

        totalSysCoinShares = addition(totalSysCoinShares, newShares);
        pooledSystemCoins = addition(pooledSystemCoins, wad);
        systemCoin.transferFrom(msg.sender, address(this), wad);
        emit Deposit(msg.sender, wad);
    }

    /**
     * @notice Withdraw system coins from liquidation pool
     * @param wad Amount of system coins to withdraw (expressed as an 18 decimal number).
     */
    function withdrawSystemCoin(uint256 wad) external {
        uint256 shares = wmultiply(wad, systemCoinsToShares());
        uint256 rewardsShare = wmultiply(wdivide(shares, totalSysCoinShares), virtualCollateral());
        positiveRewardOffsets[msg.sender] = addition(positiveRewardOffsets[msg.sender], rewardsShare);
        totalPositiveOffsets = addition(totalPositiveOffsets, rewardsShare);
        sysCoinShares[msg.sender] = subtract(sysCoinShares[msg.sender], shares);
        totalSysCoinShares = subtract(totalSysCoinShares, shares);
        pooledSystemCoins = subtract(pooledSystemCoins, wad);
        systemCoin.transferFrom(address(this), msg.sender, wad);
        emit WithdrawSystemCoins(msg.sender, wad);
    }

    /**
     * @notice Claim all available rewards
     */
    function withdrawRewards() external {

        uint256 share = WAD;
        if (totalSysCoinShares > 0) {
            share = wdivide(sysCoinShares[msg.sender], totalSysCoinShares);
        }
        uint256 virtualReward = wmultiply(share, virtualCollateral());
        if (addition(virtualReward, positiveRewardOffsets[msg.sender]) <= negativeRewardOffsets[msg.sender]){return;}
        uint256 reward = subtract(addition(virtualReward, positiveRewardOffsets[msg.sender]), negativeRewardOffsets[msg.sender]);

        negativeRewardOffsets[msg.sender] = addition(negativeRewardOffsets[msg.sender], reward);
        totalNegativeOffsets = addition(totalNegativeOffsets, reward);
        safeEngine.transferCollateral(collateralType, address(this), msg.sender, reward);
        emit WithdrawRewards(msg.sender, reward);
    }

    /**
     * @notice When pooled system coins can cover the confiscated debt, destroy them in return for collateral. An additional wad is added
     * to the quantity check to prevent scale factors overflowing too easily if pooled coins nears zero.
     * @param radSysCoinsToPay Amount of confiscated debt balance in RAD
     */
    function liquidateSafe(uint256 radSysCoinsToPay) external isAuthorized returns (bool success) {
        uint256 sysCoinsToPay = radSysCoinsToPay / RAY;
        if (sysCoinsToPay < (pooledSystemCoins + WAD)) {
            systemCoin.approve(address(coinJoin), sysCoinsToPay);
            coinJoin.join(address(this), sysCoinsToPay);
            pooledSystemCoins = subtract(pooledSystemCoins, sysCoinsToPay);
            success = true;
            emit PoolLiquidatedSafe(sysCoinsToPay);
        }
        else {
            success = false;
        }
    }

    /**
     * @notice Scaling of shares for gas efficient liquidations and rewards
     */
    function systemCoinsToShares() internal view returns (uint256 shares) {
        if (pooledSystemCoins == 0) {
            shares = WAD;
        }
        else{
            shares = wdivide(totalSysCoinShares, pooledSystemCoins);
        }
    }

    /**
     * @notice Effective pool collateral for calculations including offsets
     */
    function virtualCollateral() internal view returns (uint256 collateral) {
        uint256 poolsCollateralBalance = safeEngine.tokenCollateral(collateralType, address(this));
        collateral = subtract(addition(poolsCollateralBalance, totalNegativeOffsets), totalPositiveOffsets);
    }
}
