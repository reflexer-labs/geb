pragma solidity 0.6.7;

import "ds-test/test.sol";
import "ds-token/delegate.sol";

import {DSTest} from "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";
import {UniswapV2Pair} from "./uniswapv2mock/core/contracts/UniswapV2Pair.sol";
import {UniswapV2Factory} from "./uniswapv2mock/core/contracts/UniswapV2Factory.sol";

contract User {
    UniswapV2Pair pair;

    constructor(UniswapV2Pair _pair) public {
      pair = _pair;
    }

    receive() payable external {}

    // Transfer trading tokens to the pair
    function push(DSToken token, uint amount) public {
      token.push(address(pair), amount);
    }

    // Transfer liquidity tokens to the pair
    function push(uint amount) public {
      pair.transfer(address(pair), amount);
    }

    function mint() public {
      pair.mint(address(this));
    }

    function burn() public {
      pair.burn(address(this));
    }

    function swap(uint amount0Out, uint amount1Out, address to, bytes memory data) public {
      pair.swap(amount0Out, amount1Out, to, data);
    }

}

contract Callee0 {

    function uniswapV2Call(address, uint, uint, bytes calldata) external {
      UniswapV2Pair pair = UniswapV2Pair(msg.sender);
      address token0 = pair.token0();
      DSToken(token0).push(address(pair), 1 ether);
    }

}

contract Callee1 {

    function uniswapV2Call(address, uint amount0, uint amount1, bytes calldata) external {
      UniswapV2Pair(msg.sender).swap(amount0, amount1, address(this), '');
    }

}

contract PairTest is DSTest {
    UniswapV2Pair    pair;
    UniswapV2Factory factory;
    DSToken          token0;
    DSToken          token1;
    User             user;
    Callee0          callee0;
    Callee1          callee1;

    function setUp() public {
        DSToken tokenA = new DSToken("TST-0", "TST-0");
        DSToken tokenB = new DSToken("TST-1", "TST-1");
        factory = new UniswapV2Factory(address(this));
        pair    = UniswapV2Pair(factory.createPair(address(tokenA), address(tokenB)));
        token0  = DSToken(pair.token0());
        token1  = DSToken(pair.token1());
        user    = new User(pair);
        callee0 = new Callee0();
        callee1 = new Callee1();
    }

    function giftSome() internal {
        token0.mint(address(user), 10 ether);
        token1.mint(address(user), 10 ether);
        token0.mint(address(callee0), 10 ether);
        token0.mint(address(callee1), 10 ether);
    }

    // Transfer trading tokens and join
    function addLiquidity(uint amount0, uint amount1) internal {
        user.push(token0, amount0);
        user.push(token1, amount1);
        user.mint();
    }

    // Transfer liquidity tokens and exit
    function removeLiquidity(uint amount) internal {
        user.push(amount);
        user.burn();
    }

    function test_initial_join() public {
        giftSome();
        addLiquidity(1000, 4000);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(uint(reserve0), 1000);
        assertEq(uint(reserve1), 4000);
        assertEq(token0.balanceOf(address(pair)), 1000);
        assertEq(token1.balanceOf(address(pair)), 4000);
        assertEq(pair.balanceOf(address(user)), 1000);
        assertEq(pair.totalSupply(), 2000);
        assertEq(pair.balanceOf(address(pair)), 0);
    }

    function test_exit() public {
        giftSome();
        addLiquidity(1000, 4000);
        assertEq(pair.balanceOf(address(user)), 1000);
        removeLiquidity(1000);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(uint(reserve0), 500);
        assertEq(uint(reserve1), 2000);

        assertEq(token0.balanceOf(address(pair)), 500);
        assertEq(token1.balanceOf(address(pair)), 2000);
        assertEq(pair.balanceOf(address(user)), 0);
        assertEq(pair.totalSupply(), 1000);
        assertEq(pair.balanceOf(address(pair)), 0);
    }

    function setupSwap() public {
        giftSome();
        addLiquidity(5 ether, 10 ether);
    }


    //token0 in -> token1 out
    function test_swap0() public {
        setupSwap();
        user.push(token0, 1 ether);
        user.swap(0, 1.662497915624478906 ether, address(user), '');

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(uint(reserve0), 6 ether);
        assertEq(uint(reserve1), 10 ether - 1.662497915624478906 ether);

        assertEq(token0.balanceOf(address(pair)), 6 ether);
        assertEq(token1.balanceOf(address(pair)), 10 ether - 1.662497915624478906 ether);

        assertEq(token0.balanceOf(address(user)), 4 ether);
        assertEq(token1.balanceOf(address(user)), 1.662497915624478906 ether);
    }

    //token1 in -> token0 out
    function test_swap1() public {
        setupSwap();
        token1.mint(address(user), 1 ether);
        user.push(token1, 1 ether);
        user.swap(0.045330544694007456 ether, 0, address(user), '');

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(uint(reserve0), 5 ether - 0.045330544694007456 ether);
        assertEq(uint(reserve1), 11 ether);

        assertEq(token0.balanceOf(address(pair)), 5 ether - 0.045330544694007456 ether);
        assertEq(token1.balanceOf(address(pair)), 11 ether);

        assertEq(token0.balanceOf(address(user)), 5 ether + 0.045330544694007456 ether);
        assertEq(token1.balanceOf(address(user)), 0);
    }
}

contract StubString {
    string public name;
    constructor() public {
        name = "Uniswap V2";
    }
}

contract SubStringTest is DSTest {
    StubString stubstring;
    function setUp() public {
        stubstring = new StubString();
    }

    function test_checkName() public {
        string memory name = stubstring.name();
        bytes32 name32;
        assembly {
            name32 := mload(add(name, 0x20))
        }
        assertEq(name32, "Uniswap V2");
    }
}
