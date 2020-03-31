/// bin.sol -- Aggregator of DEXs

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

import "./lib.sol";
import {ERC20} from "./dex/kyber.sol";

contract UniOneLike {
    function tokenToTokenInputRate(
        address sell,
        address buy,
        uint256 wad
    ) external view returns (uint256, uint256);
    function tokenToTokenOutputRate(
        address sell,
        address buy,
        uint256 wad
    ) external view returns (uint256, uint256);
    function tokenToTokenTransferInput(
        address sold_token,
        uint256 tokens_sold,
        uint256 min_tokens_bought,
        uint256 min_eth_bought,
        uint256 deadline,
        address recipient,
        address bought_token) external returns (uint256);
    function tokenToExchangeTransferOutput(
        address sold_token,
        uint256 tokens_bought,
        uint256 max_tokens_sold,
        uint256 max_eth_sold,
        uint256 deadline,
        address recipient,
        address bought_token) external returns (uint256);
}

contract KyberLike {
    function calcDestAmount(ERC20 src, ERC20 dest, uint srcAmount, uint rate) public view returns (uint);
    function calcSrcAmount(ERC20 src, ERC20 dest, uint destAmount, uint rate) public view returns (uint);
    function getExpectedRate(ERC20 src, ERC20 dest, uint srcQty)
        public view
        returns(uint expectedRate, uint slippageRate);
    function trade(
        ERC20 src,
        uint srcAmount,
        ERC20 dest,
        address destAddress,
        uint maxDestAmount,
        uint minConversionRate,
        address walletId
    )
        public
        payable
        returns(uint);
    function swapTokenToToken(
        ERC20 src,
        uint srcAmount,
        ERC20 dest,
        uint minConversionRate
    )
        public
        returns(uint);
}

contract Bin is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Bin/not-authorized");
        _;
    }

    KyberLike   public kyber;
    UniOneLike     public uni;

    uint256 public slip;
    uint256 public live;

    string public constant KYBER   = "kyber";
    string public constant UNISWAP = "uniswap";

    constructor(
      address uni_,
      address kyber_
    ) public {
        uni = UniOneLike(uni_);
        kyber = KyberLike(kyber_);
        live = 1;
    }

    // --- Administration ---
    function file(bytes32 what, address addr) external note auth {
        require(live == 1, "Bin/not-live");
        require(addr != address(0), "Bin/null-addr");
        if (what == "uni") uni = UniOneLike(addr);
        else if (what == "kyber") kyber = KyberLike(addr);
        else revert("Bin/file-unrecognized-param");
    }
    function cage() external note auth {
        live = 0;
    }

    // --- Conversion ---
    function best(
        address src,
        address dst,
        uint256 wad
    ) internal view returns (uint, uint, string memory) {
        uint k; uint u; uint kr; uint core;
        if (address(kyber) != address(0)) {
          (kr, ) = kyber.getExpectedRate(ERC20(src), ERC20(dst), wad);
          k = kyber.calcDestAmount(ERC20(src), ERC20(dst), wad, kr);
        }
        if (address(uni) != address(0)) {
          (core, u) = uni.tokenToTokenInputRate(src, dst, wad);
        }
        if (k >= u) {
          return (k, kr, KYBER);
        } else if (u > 0) {
          return (u, core, UNISWAP);
        }
        return (0, 0, "");
    }
    function buy(
        address src,
        address dst,
        uint256 wad,
        uint win,
        uint fine,
        string memory dex
    ) internal {
        if (keccak256(abi.encode(dex)) == keccak256(abi.encode(""))) return;

        if (keccak256(abi.encode(dex)) == keccak256(abi.encode(KYBER))) {
          kyber.trade(
            ERC20(src),
            wad,
            ERC20(dst),
            msg.sender,
            uint(-1),
            fine,
            address(0)
          );
        } else {
          uni.tokenToTokenTransferInput(
            src,
            wad,
            win,
            fine,
            now,
            msg.sender,
            dst
          );
        }
    }
    function swap(
        address src,
        address dst,
        uint256 wad
    ) external note {
        (uint win, uint fine, string memory dex) = best(src, dst, wad);
        buy(src, dst, wad, win, fine, dex);
    }
}
