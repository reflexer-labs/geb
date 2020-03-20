pragma solidity ^0.5.15;

import "ds-test/test.sol";

import "./Mai.sol";

contract MaiTest is DSTest {
    Mai mai;

    function setUp() public {
        mai = new Mai();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
