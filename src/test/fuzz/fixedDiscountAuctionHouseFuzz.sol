pragma solidity ^0.6.7;

import "./mocks/CollateralAuctionHouseMock.sol";

contract SAFEEngineMock {
    function transferInternalCoins(address,address,uint256) public {
        
    }
    function transferCollateral(bytes32,address,address,uint256) public {
        
    }
}
contract OracleRelayerMock {
    function redemptionPrice() public returns (uint256) {
        return 3.14 ether;
    }
}
contract LiquidationEngineMock {
    uint public removedCoinsFromAfuction;
    function removeCoinsFromAuction(uint256 val) public {
        removedCoinsFromAfuction += val;
    }
}

contract Feed {
    address public priceSource;
    uint256 public priceFeedValue;
    bool public hasValidValue;
    constructor(bytes32 initPrice, bool initHas) public {
        priceFeedValue = uint(initPrice);
        hasValidValue = initHas;
    }
    function set_val(uint newPrice) external {
        priceFeedValue = newPrice;
    }
    function set_price_source(address priceSource_) external {
        priceSource = priceSource_;
    }
    function set_has(bool newHas) external {
        hasValidValue = newHas;
    }
    function getResultWithValidity() external returns (uint256, bool) {
        return (priceFeedValue, hasValidValue);
    }
}

// @notice Fuzz the whole thing, assess the results to see if failures make sense
contract GeneralFuzz is FixedDiscountCollateralAuctionHouseMock {

    constructor() public
        FixedDiscountCollateralAuctionHouseMock(
            address(0x1),
            address(0x2),
            "ETH-A"
        ){}

    
}

// @notice Will create an auction, to enable fuzzing the bidding function
contract FuzzBids is FixedDiscountCollateralAuctionHouseMock {
    constructor() public
        FixedDiscountCollateralAuctionHouseMock(
            address(new SAFEEngineMock()),
            address(new LiquidationEngineMock()),
            "ETH-A"
        ){
            // creating feeds
            collateralFSM = OracleLike(address(new Feed(bytes32(uint256(3.14 ether)), true)));
            oracleRelayer = OracleRelayerLike(address(new OracleRelayerMock()));

            // starting an auction
            startAuction({ amountToSell: 100 ether
                                        , amountToRaise: 50 * 10 ** 45
                                        , forgoneCollateralReceiver: address(0xacab)
                                        , auctionIncomeRecipient: address(0xfab)
                                        , initialBid: 0
                                        });

        }

    // properties   
    function echidna_auctionsStarted() public returns (bool) { 
        return auctionsStarted == 1;
    }

    function echidna_collateralType() public returns (bool) { 
        return collateralType == "ETH-A";
    }

    function echidna_minimumBid() public returns (bool) { 
        return minimumBid == 5* 10**18;
    }

    function echidna_lastReadRedemptionPrice() public returns (bool) { 
        return lastReadRedemptionPrice == 0 || lastReadRedemptionPrice == 3.14 ether;
    }

    function echidna_discount() public returns (bool) { 
        return discount == 0.95E18;
    }

    function echidna_lowerCollateralMedianDeviation() public returns (bool) { 
        return lowerCollateralMedianDeviation == 0.90E18;
    }

    function echidna_upperCollateralMedianDeviation() public returns (bool) { 
        return upperCollateralMedianDeviation == 0.95E18;
    }

    function echidna_lowerSystemCoinMedianDeviation() public returns (bool) { 
        return lowerSystemCoinMedianDeviation == 10 ** 18;
    }

    function echidna_upperSystemCoinMedianDeviation() public returns (bool) { 
        return upperSystemCoinMedianDeviation == 10 ** 18;
    }

    function echidna_minSystemCoinMedianDeviation() public returns (bool) { 
        return minSystemCoinMedianDeviation == 0.999E18;
    }

    function echidna_bid() public returns (bool) { 
        if (bids[1].raisedAmount != 0) return false; // failing, test against token flows

        return true;
    }


    // adding a directed bidding function
    // we trust the fuzzer will find it's way to the active auction, but here we're forcing valid bids to make sure.
    // (the original buyCOllateral function is also fuzzed)

    function bid(uint val) public {
        buyCollateral(1, val %  bids[1].amountToSell);
    }


}

// @notice Will allow echidna accounts to create auctions and bid
contract FuzzAuctionsAndBids is FixedDiscountCollateralAuctionHouseMock {
    constructor() public
        FixedDiscountCollateralAuctionHouseMock(
            address(new SAFEEngineMock()),
            address(new LiquidationEngineMock()),
            "ETH-A"
        ){
            // creating feeds
            collateralFSM = OracleLike(address(new Feed(bytes32(uint256(3.14 ether)), true)));
            oracleRelayer = OracleRelayerLike(address(new OracleRelayerMock()));

            // authing accounts
            authorizedAccounts[address(0x1)] = 1;
            authorizedAccounts[address(0x2)] = 1;
            authorizedAccounts[address(0xabc)] = 1;


        }

        // properties
    function echidna_auctionsStarted() public returns (bool) { 
        return auctionsStarted == 0; // should fail
    }
}