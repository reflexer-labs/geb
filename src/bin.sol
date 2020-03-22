/// bin.sol -- Aggregator of DEXs for Flapper

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
import {IERC20} from "./dex/kyber.sol";

contract UniLike {
    function tokenToTokenInputRate(
        address sell,
        address buy,
        uint256 wad
    ) external returns (uint256, uint256);
    function tokenToTokenOutputRate(
        address sell,
        address buy,
        uint256 wad
    ) external returns (uint256, uint256);
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
    function getExpectedRate(IERC20 _srcToken, IERC20 _destToken, uint256 _srcAmount)
      public view returns(uint256 expectedRate, uint256 slippageRate);
    function convert(
        IERC20 _srcToken,
        IERC20 _destToken,
        uint256 _srcAmount,
        uint256 _destAmount,
        address walletId
    ) external returns (uint256);
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
    UniLike     public uni;

    uint256 public live;

    constructor(
      address uni_,
      address kyber_,
      address src_,
      address dst_
    ) public {
        uni = UniLike(uni_);
        kyber = KyberLike(kyber_);
        live = 1;
    }

    function file(bytes32 what, address addr) external note auth {
        require(live == 1, "Bin/not-live");
        require(addr != address(0), "Bin/null-addr");
        if (what == "uni") uni = UniLike(addr);
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
    ) internal view returns (uint, uint) {
        uint k; uint u;
        if (address(kyber) != address(0)) {
          (k, ) = kyber.getExpectedRate(IERC20(src), IERC20(dst), wad);
        }
        if (address(uni) != address(0)) {
          (, u) = uni.tokenToTokenInputRate(src, dst, wad);
        }

    }
    function buy(
        address src,
        address dst,
        uint256 wad
    ) external {

    }
}
