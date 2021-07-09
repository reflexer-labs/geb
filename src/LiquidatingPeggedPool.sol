/// LiquidatingPeggedPool.sol

// Copyright (C) 2021 stobiewan
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

import {Coin} from './Coin.sol';

abstract contract SAFEEngineLike {
    function tokenCollateral(bytes32, address) virtual external view returns (uint256);
    function transferCollateral(bytes32 collateralType, address src, address dst, uint256 wad) virtual external;
}
abstract contract CoinJoinLike {
    function systemCoin() virtual public view returns (address);
    function safeEngine() virtual public view returns (address);
    function join(address, uint256) virtual external;
}
abstract contract CollateralJoinLike {
    function collateralType() virtual public view returns (bytes32);
    function collateral() virtual public view returns (address);
    function exit(address, uint256) virtual external;
}
abstract contract SystemCoinLike {
    function approve(address, uint256) virtual public returns (uint256);
    function balanceOf(address) virtual public view returns (uint256);
    function transfer(address,uint256) virtual public returns (bool);
    function transferFrom(address,address,uint256) virtual public returns (bool);
}
abstract contract CollateralCoinLike {
    function approve(address, uint256) virtual public returns (uint256);
    function balanceOf(address) virtual public view returns (uint256);
    function transfer(address,uint256) virtual public returns (bool);
    function transferFrom(address,address,uint256) virtual public returns (bool);
}
abstract contract OracleRelayerLike {
    function redemptionPrice() virtual public returns (uint256);
    function redemptionRate() virtual public view returns (uint256);
}
abstract contract SwapRouterLike {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) virtual external returns (uint[] memory amounts);
}

/**
 * @notice A mixin for reading the redemption price from the OracleRelayer's public method which writes state. To allow
 * apps to read it with a view method a cache is used here to provide an equivalent interface.
 * The principal for using this mixin is any method which modifies state and reads the price should first perform an
 * update, while view methods may use the read only variant. This is enshrined with the updatesRedemptionPrice modifier.
 */
contract RedemptionPriceReader {
    // Oracle source set by derived contracts
    OracleRelayerLike public oracleRelayer;
    uint256 public redemptionPrice;
    uint256 public redemptionPriceUpdateTime;

    // --- Math ---
    uint256 constant RAY = 10 ** 27;

    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x - y;
        require(z <= x, "OracleRelayer/sub-underflow");
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "LiquidatingPeggedPool/mul-overflow");
    }
    function rmultiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        // always rounds down
        z = multiply(x, y) / RAY;
    }
    function rpower(uint256 x, uint256 n, uint256 base) internal pure returns (uint256 z) {
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

    modifier updatesRedemptionPrice {
        redemptionPrice = oracleRelayer.redemptionPrice();
        redemptionPriceUpdateTime = now;
        _;
    }

    /**
     * @dev In the case that the real redemptionRate has been updated after the last update of this contracts cache
     * the result returned here will be incorrect. Any state changing method in a derived contract must perform an
     * update first.
     */
    function readRedemptionPrice() public view returns (uint256) {
        if (now == redemptionPriceUpdateTime) return redemptionPrice;
        uint256 tempRedemptionPrice = rmultiply(rpower(oracleRelayer.redemptionRate(),
            subtract(now, redemptionPriceUpdateTime), RAY), redemptionPrice);
        if (tempRedemptionPrice == 0) tempRedemptionPrice = 1;
        return tempRedemptionPrice;
    }
}

/**
 * @notice This contract implements a rebasing token with stable coin collateral. Internal balance uses units of system
 * coin and to interact as standardly as it can all interfaces expect rebase units. Does not inherit from Coin.sol
 * as balance vs allowance checks etc must always translate units. The collateral doubles as a zero risk stability pool
 * capable of generating profit for the protocol.
 */
contract LiquidatingPeggedPool is RedemptionPriceReader {
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

    // --- ERC20 Data ---
    // The name of this coin
    string  public name;
    // The symbol of this coin
    string  public symbol;
    // The version of this Coin contract
    string  public version = "1";
    // The number of decimals that this coin has
    uint8   public constant decimals = 18;
    // The id of the chain where this coin was deployed
    uint256 public chainId;
    // The total supply of this coin
    uint256 public totalSupplyInSystemCoin;
    // Mapping of coin balances
    mapping (address => uint256)                      public balanceOfSystemCoin;
    // Mapping of allowances
    mapping (address => mapping (address => uint256)) public allowance;
    // Mapping of nonces used for permits
    mapping (address => uint256)                      public nonces;

    // --- Liquidation Pool Data ---
    // Address of contract to swap collateral for system coins
    SwapRouterLike public swapRouter;
    // SAFE database
    SAFEEngineLike public safeEngine;
    // The ERC20 system coin
    SystemCoinLike public systemCoin;
    // The collateral coin
    CollateralCoinLike public collateral;
    // The system coin join contract
    CoinJoinLike public coinJoin;
    // The system coin join contract
    CollateralJoinLike public collateralJoin;
    // Swaps trade swapPath[0] for swapPath[1]
    address[2] swapPath;
    // Address of internal sys coins surplus buffer
    address accountingEngineAddress;
    // Whether this contract is enabled or not
    uint256 public contractEnabled;
    // Collateral type used by this pool
    bytes32 collateralType;

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event ModifyParameters(bytes32 parameter, address data);
    event DisableContract();
    event Approval(address indexed src, address indexed guy, uint256 amount);
    event Transfer(address indexed src, address indexed dst, uint256 amount);
    event PoolLiquidatedSafe(uint256 systemProfit);

    // --- Math ---
    uint256 constant WAD = 10 ** 18;
    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "LiquidatingPeggedPool/add-overflow");
    }
    function wdivide(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0, "LiquidatingPeggedPool/wdiv-by-zero");
        z = multiply(x, WAD) / y;
    }
    function wmultiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = multiply(x, y) / WAD;
    }
    function rdivide(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0, "GlobalSettlement/rdiv-by-zero");
        z = multiply(x, RAY) / y;
    }

    // --- EIP712 niceties ---
    bytes32 public DOMAIN_SEPARATOR;
    // bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)");
    bytes32 public constant PERMIT_TYPEHASH = 0xea2aa0a1be11a07ed86d755c93467f4f82362b452371d1ba94d1715123511acb;

    // --- Init ---
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 chainId_,
        address coinJoin_,
        address collateralJoin_
    ) public {
        authorizedAccounts[msg.sender] = 1;
        name = name_;
        symbol = symbol_;
        chainId = chainId_;
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256(bytes(version)),
            chainId_,
            address(this)
        ));
        collateralJoin = CollateralJoinLike(collateralJoin_);
        collateralType = collateralJoin.collateralType();
        collateral = CollateralCoinLike(collateralJoin.collateral());
        coinJoin = CoinJoinLike(coinJoin_);
        systemCoin = SystemCoinLike(coinJoin.systemCoin());
        safeEngine = SAFEEngineLike(coinJoin.safeEngine());
        systemCoin.approve(address(coinJoin), uint256(-1));
        swapPath[0] = address(collateral);
        swapPath[1] = address(systemCoin);
        contractEnabled = 1;
        emit AddAuthorization(msg.sender);
    }

    /**
     * @notice Modify contract integrations.
     * @param parameter The name of the parameter modified
     * @param data New address for the parameter
     */
    function modifyParameters(bytes32 parameter, address data) external isAuthorized {
        if (parameter == "swapRouter") {
            swapRouter = SwapRouterLike(data);
            collateral.approve(address(swapRouter), uint256(-1));
        }
        else if (parameter == "accountingEngineAddress") {
            accountingEngineAddress = data;
            systemCoin.approve(accountingEngineAddress, uint256(-1));
        }
        else if (parameter == "oracleRelayer") oracleRelayer = OracleRelayerLike(data);
        else revert("LiquidatingPeggedPool/modify-unrecognized-param");
        emit ModifyParameters(parameter, data);
    }

    /**
     * @notice Disable this contract (usually called by Global Settlement)
     */
    function disableContract() external isAuthorized {
        contractEnabled = 0;
        emit DisableContract();
    }

    // --- Rebase token---
    function systemCoinToRebaseToken(uint256 amount) public view returns (uint256) {
        return rmultiply(redemptionPrice, amount);
    }
    function rebaseTokenToSystemCoin(uint256 amount) public view returns (uint256) {
        return rdivide(amount, redemptionPrice);
    }
    /*
    * @notice Transfer coins to another address
    * @param dst The address to transfer coins to
    * @param amount The amount of coins to transfer
    */
    function transfer(address dst, uint256 amount) external returns (bool) {
        return transferFrom(msg.sender, dst, amount);
    }
    /*
     * @notice Transfer coins from a source address to a destination address (if allowed)
     * @dev Note balanceOfSystemCoin must be compared with systemCoinAmount and allowance must be compared
            with amount. Only overriding the balance modification section wouldn't work.
     * @param src The address from which to transfer coins
     * @param dst The address that will receive the coins
     * @param amount The amount of rebase coins to transfer
     */
    function transferFrom(address src, address dst, uint256 amount) public updatesRedemptionPrice returns (bool)
    {
        // write new redemptionPrice so next calls are cheap.
        uint256 systemCoinAmount = rebaseTokenToSystemCoin(amount);
        require(dst != address(0), "Coin/null-dst");
        require(dst != address(this), "Coin/dst-cannot-be-this-contract");
        require(balanceOfSystemCoin[src] >= systemCoinAmount, "Coin/insufficient-balance");
        if (src != msg.sender && allowance[src][msg.sender] != uint256(-1)) {
            require(allowance[src][msg.sender] >= amount, "Coin/insufficient-allowance");
            allowance[src][msg.sender] = subtract(allowance[src][msg.sender], amount);
        }
        balanceOfSystemCoin[src] = subtract(balanceOfSystemCoin[src], systemCoinAmount);
        balanceOfSystemCoin[dst] = addition(balanceOfSystemCoin[dst], systemCoinAmount);
        emit Transfer(src, dst, amount);
        return true;
    }

    /**
     * @notice Deposit system coins to generate rebasing pegged tokens
     * @param systemCoinAmount Amount of system coins to deposit (expressed as an 18 decimal number).
     * @param beneficiary Account to recieve rebase coins
     */
    function deposit(address beneficiary, uint256 systemCoinAmount) public updatesRedemptionPrice {
        systemCoin.transferFrom(msg.sender, address(this), systemCoinAmount);
        balanceOfSystemCoin[beneficiary] = addition(balanceOfSystemCoin[beneficiary], systemCoinAmount);
        totalSupplyInSystemCoin = addition(totalSupplyInSystemCoin, systemCoinAmount);
        emit Transfer(address(0), beneficiary, systemCoinToRebaseToken(systemCoinAmount));
    }

    /**
     * @notice Burn rebase coins to reclaim system coins
     * @param systemCoinAmount Amount of system coins to withdraw (expressed as an 18 decimal number). System coin used
     * rather than rebasing pegged token as quantity is fixed so withdrawing 100% is simple and this is not a standard
     * method which should support rebase units.
     * @param beneficiary Account to receive system coins. msg.sender will have rebase coins burned so no need for
     * allowance check.
     */
    function withdraw(address beneficiary, uint256 systemCoinAmount) public updatesRedemptionPrice {
        balanceOfSystemCoin[msg.sender] = subtract(balanceOfSystemCoin[msg.sender], systemCoinAmount);
        totalSupplyInSystemCoin = subtract(totalSupplyInSystemCoin, systemCoinAmount);
        systemCoin.transfer(beneficiary, systemCoinAmount);
        emit Transfer(beneficiary, address(0), systemCoinToRebaseToken(systemCoinAmount));
    }

    /*
    * @notice Change the rebase token transfer allowance that another address has on your behalf. Value will be constant
    * in rebase units and vary in system coin units.
    * @param usr The address whose allowance is changed
    * @param amount The new total allowance for the usr in rebase token
    */
    function approve(address usr, uint256 amount) public returns (bool) {
        allowance[msg.sender][usr] = amount;
        emit Approval(msg.sender, usr, amount);
        return true;
    }

    /**
     * @param account The address to query.
     * @return The rebase token balance of the specified address.
     */
    function balanceOf(address account) public view returns (uint256) {
        return systemCoinToRebaseToken(balanceOfSystemCoin[account]);
    }

    function balanceInSystemCoin(address account) public view returns (uint256) {
        return balanceOfSystemCoin[account];
    }

    /**
     * @return total supply of rebase tokens
     */
    function totalSupply() public view returns (uint256) {
        return systemCoinToRebaseToken(totalSupplyInSystemCoin);
    }

    // --- Alias ---
    /*
    * @notice Send coins to another address
    * @param usr The address to send tokens to
    * @param amount The amount of coins to send
    */
    function push(address usr, uint256 amount) external {
        transferFrom(msg.sender, usr, amount);
    }
    /*
    * @notice Transfer coins from another address to your address
    * @param usr The address to take coins from
    * @param amount The amount of coins to take from the usr
    */
    function pull(address usr, uint256 amount) external {
        transferFrom(usr, msg.sender, amount);
    }
    /*
    * @notice Transfer coins from another address to a destination address (if allowed)
    * @param src The address to transfer coins from
    * @param dst The address to transfer coins to
    * @param amount The amount of coins to transfer
    */
    function move(address src, address dst, uint256 amount) external {
        transferFrom(src, dst, amount);
    }
    function mint(address beneficiary, uint256 amount) external {
        deposit(beneficiary, amount);
    }
    function burn(address beneficiary, uint256 amount) external {
        withdraw(beneficiary, amount);
    }
    function mint(uint256 amount) external {
        deposit(msg.sender, amount);
    }
    function burn(uint256 amount) external {
        withdraw(msg.sender, amount);
    }
    function approve(address usr) public returns (bool) {
        return approve(usr, uint256(-1));
    }

    // --- Approve by signature ---
    /*
    * @notice Submit a signed message that modifies an allowance for a specific address
    */
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external
    {
        bytes32 digest =
            keccak256(abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH,
                                     holder,
                                     spender,
                                     nonce,
                                     expiry,
                                     allowed))
        ));

        require(holder != address(0), "Coin/invalid-address-0");
        require(holder == ecrecover(digest, v, r, s), "Coin/invalid-permit");
        require(expiry == 0 || now <= expiry, "Coin/permit-expired");
        require(nonce == nonces[holder]++, "Coin/invalid-nonce");
        uint256 wad = allowed ? uint256(-1) : 0;
        allowance[holder][spender] = wad;
        emit Approval(holder, spender, wad);
    }

    // --- Liquidation pool---
    /**
     * @notice When pooled system coins can cover the confiscated debt, destroy them in return for collateral.
     * Trade the collateral for system coins to make the pool whole and give profit to system surplus buffer.
     * Designed to be called in a try block and revert all actions if result is undesirable.
     * @param radSysCoinsToPay Amount of confiscated debt balance in RAD
     * @param collateralSource Address to take confiscated collateral from.
     * @param collateralToSell Amount of confiscated debt balance in RAD
     */
    function liquidateSafe(uint256 radSysCoinsToPay, address collateralSource, uint256 collateralToSell) external isAuthorized {
        require(contractEnabled == 1, "LiquidatingPeggedPool/pool-liquidations-disabled");
        uint256 initialSysCoinBalance = systemCoin.balanceOf(address(this));
        uint256 sysCoinsToPay = radSysCoinsToPay / RAY;
        safeEngine.transferCollateral(collateralType, collateralSource, address(this), collateralToSell);
        collateralJoin.exit(address(this), collateralToSell);
        address[] memory tokens = new address[](2);
        tokens[0] = address(collateral); tokens[1] = address(systemCoin);
        // TODO after incentives move to uni v3 this becomes exactInputSingle() in v3 router01. Only using mock for now
        // and not extensively testing because this would likely need to be reimplemented soon.
        swapRouter.swapExactTokensForTokens(collateralToSell, 0, tokens, address(this), uint(-1));
        coinJoin.join(address(this), sysCoinsToPay);
        // unless the liquidation and trade has returned a profit this subtraction will revert the pools
        // actions and the LiquidationEngine will continue creating an auction. This protects from bad
        // swap outcomes due to front running or poor liquidity etc.
        uint256 profit = subtract(systemCoin.balanceOf(address(this)), initialSysCoinBalance);
        // Pay excess profit to surplus buffer to give system energy to spend on negative borrow rate or
        // incentivise the rebase token etc.
        coinJoin.join(accountingEngineAddress, profit);
        emit PoolLiquidatedSafe(profit);
    }
}
