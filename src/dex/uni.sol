pragma solidity ^0.5.15;

import "../lib.sol";

contract Uni is LibNote {
    // --- Swapping ---
    function tokenToTokenInputRate(
        address sell,
        address buy,
        uint256 wad
    ) external returns (uint256, uint256) {
        uint eth = UniLike(sell).getTokenToEthInputPrice(wad);
        uint gem = UniLike(buy).getEthToTokenInputPrice(eth);
        return (eth, gem);
    }

    function tokenToTokenOutputRate(
        address sell,
        address buy,
        uint256 wad
    ) external returns (uint256, uint256) {
        uint eth = UniLike(buy).getTokenToEthInputPrice(wad);
        uint gem = UniLike(sell).getEthToTokenInputPrice(eth);
        return (eth, gem);
    }

    function tokenToTokenTransferInput(
        address sold_token,
        uint256 tokens_sold,
        uint256 min_tokens_bought,
        uint256 min_eth_bought,
        uint256 deadline,
        address recipient,
        address bought_token) external returns (uint256) {
        UniLike(sold_token).tokenToTokenTransferInput(
          tokens_sold,
          min_tokens_bought,
          min_eth_bought,
          deadline,
          recipient,
          bought_token
        );
    }

    function tokenToExchangeTransferOutput(
        address sold_token,
        uint256 tokens_bought,
        uint256 max_tokens_sold,
        uint256 max_eth_sold,
        uint256 deadline,
        address recipient,
        address bought_token) external returns (uint256) {
        UniLike(sold_token).tokenToTokenTransferInput(
          tokens_bought,
          max_tokens_sold,
          max_eth_sold,
          deadline,
          recipient,
          bought_token
        );
    }
}
