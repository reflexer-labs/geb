pragma solidity ^0.5.15;

import "../lib.sol";

contract UniOneLike {
    // Get Prices
    function getEthToTokenInputPrice(uint256 eth_sold) external view returns (uint256 tokens_bought);
    function getEthToTokenOutputPrice(uint256 tokens_bought) external view returns (uint256 eth_sold);
    function getTokenToEthInputPrice(uint256 tokens_sold) external view returns (uint256 eth_bought);
    function getTokenToEthOutputPrice(uint256 eth_bought) external view returns (uint256 tokens_sold);
    // Trade ERC20 to ERC20
    function tokenToTokenSwapInput(uint256 tokens_sold, uint256 min_tokens_bought, uint256 min_eth_bought, uint256 deadline, address token_addr) external returns (uint256  tokens_bought);
    function tokenToTokenTransferInput(uint256 tokens_sold, uint256 min_tokens_bought, uint256 min_eth_bought, uint256 deadline, address recipient, address token_addr) external returns (uint256  tokens_bought);
    function tokenToTokenSwapOutput(uint256 tokens_bought, uint256 max_tokens_sold, uint256 max_eth_sold, uint256 deadline, address token_addr) external returns (uint256  tokens_sold);
    function tokenToTokenTransferOutput(uint256 tokens_bought, uint256 max_tokens_sold, uint256 max_eth_sold, uint256 deadline, address recipient, address token_addr) external returns (uint256  tokens_sold);
}

contract UniOne is LibNote {
    // --- Swapping ---
    function tokenToTokenInputRate(
        address sell,
        address buy,
        uint256 wad
    ) external view returns (uint256, uint256) {
        uint core = UniOneLike(sell).getTokenToEthInputPrice(wad);
        uint gem = UniOneLike(buy).getEthToTokenInputPrice(core);
        return (core, gem);
    }

    function tokenToTokenOutputRate(
        address sell,
        address buy,
        uint256 wad
    ) external view returns (uint256, uint256) {
        uint core = UniOneLike(buy).getTokenToEthInputPrice(wad);
        uint gem = UniOneLike(sell).getEthToTokenInputPrice(core);
        return (core, gem);
    }

    function tokenToTokenTransferInput(
        address sold_token,
        uint256 tokens_sold,
        uint256 min_tokens_bought,
        uint256 min_eth_bought,
        uint256 deadline,
        address recipient,
        address bought_token) external returns (uint256) {
        UniOneLike(sold_token).tokenToTokenTransferInput(
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
        UniOneLike(sold_token).tokenToTokenTransferInput(
          tokens_bought,
          max_tokens_sold,
          max_eth_sold,
          deadline,
          recipient,
          bought_token
        );
    }
}
