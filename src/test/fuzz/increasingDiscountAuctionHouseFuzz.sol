pragma solidity ^0.6.7;

import "./CollateralAuctionHouseMock.sol";
// import "ds-test/test.sol";

contract SAFEEngineMock {
    mapping (address => uint) public receivedCoin;
    mapping (address => uint) public sentCollateral;

    function addUint256(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function transferInternalCoins(address,address to,uint256 val) public {
        receivedCoin[to] = addUint256(val, receivedCoin[to]);
    }
    function transferCollateral(bytes32,address from,address,uint256 val) public {
        sentCollateral[from] = addUint256(val, sentCollateral[from]);
    }
}
contract OracleRelayerMock {
    function redemptionPrice() public returns (uint256) {
        return 3.14 ether;
    }
}
contract LiquidationEngineMock {
    function addUint256(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    uint public removedCoinsFromAuction;
    function removeCoinsFromAuction(uint256 val) public {
        removedCoinsFromAuction = addUint256(val,removedCoinsFromAuction);
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

// @notice Fuzz the whole thing, failures will show bounds (run with checkAsserts: on)
contract FuzzBounds is IncreasingDiscountCollateralAuctionHouseMock {
    address auctionIncomeRecipient = address(0xfab);
    address _forgoneCollateralReceiver = address(0xacab);
    uint _amountToRaise = 50 * 10 ** 45;
    uint _amountToSell = 100 ether;    

    constructor() public IncreasingDiscountCollateralAuctionHouseMock(
            address(new SAFEEngineMock()),
            address(new LiquidationEngineMock()),
            "ETH-A" 
        ) {
            setUp();
        }

    function setUp() public {
            // creating feeds
            collateralFSM = OracleLike(address(new Feed(bytes32(uint256(3.14 ether)), true)));
            oracleRelayer = OracleRelayerLike(address(new OracleRelayerMock()));

            // config increasing discount
            modifyParameters("perSecondDiscountUpdateRate", 999998607628240588157433861); // -0.5% per hour
            modifyParameters("maxDiscount", 0.50E18); // 50%
            modifyParameters("maxDiscountUpdateRateTimeline", 50 weeks);

            // starting an auction
            startAuction({ amountToSell: 100 ether
                                , amountToRaise: _amountToRaise
                                , forgoneCollateralReceiver: _forgoneCollateralReceiver
                                , auctionIncomeRecipient: auctionIncomeRecipient
                                , initialBid: 0
                                });

            // auction initiated
            assert(bids[1].amountToRaise == _amountToRaise);

    }
}

// @notice Will create an auction, to enable fuzzing the bidding function (fuzz with checkAsserts: off)
contract FuzzBids is IncreasingDiscountCollateralAuctionHouseMock{
    address auctionIncomeRecipient = address(0xfab);
    address _forgoneCollateralReceiver = address(0xacab);
    uint _amountToRaise = uint(50 * 10 ** 45);
    uint _amountToSell = uint(100 ether);

    constructor() public IncreasingDiscountCollateralAuctionHouseMock(
            address(new SAFEEngineMock()),
            address(new LiquidationEngineMock()),
            "ETH-A" 
        ) {
            setUp();
        }

    function setUp() public
       {
            // creating feeds
            collateralFSM = OracleLike(address(new Feed(bytes32(uint256(3.14 ether)), true)));
            oracleRelayer = OracleRelayerLike(address(new OracleRelayerMock()));

            // config increasing discount
            modifyParameters("perSecondDiscountUpdateRate", 999998607628240588157433861); // -0.5% per hour
            modifyParameters("maxDiscount", 0.90E18); // 10%

            // starting an auction
            startAuction(_forgoneCollateralReceiver, auctionIncomeRecipient, _amountToRaise, _amountToSell, 0);

            // auction initiated
            assert(bids[1].amountToRaise == _amountToRaise);

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
        return minDiscount == 0.95E18;
    }

    function echidna_maxDiscount() public returns (bool) { 
        return maxDiscount == 0.90E18;
    }

    function echidna_perSecondDiscountUpdateRate() public returns (bool) { 
        return perSecondDiscountUpdateRate == 999998607628240588157433861;
    }

    function echidna_maxDiscountUpdateRateTimeline() public returns (bool) { 
        return maxDiscountUpdateRateTimeline == 1 hours;
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

    // auxiliary structure to track auction initial data
    struct AuctionData {
        uint initialAmountToRaise;
        uint initialAmountToSell;
    }

    mapping (uint256 => AuctionData) internal auctions;

    function startAuction(
        address, address,
        uint256 amountToRaise,
        uint256 amountToSell,
        uint256 initialBid
    ) public override returns (uint256 id) {
        id = super.startAuction(
            _forgoneCollateralReceiver,
            auctionIncomeRecipient,
            amountToRaise,
            amountToSell,
            initialBid
        );

        auctions[id] = AuctionData(amountToRaise, amountToSell);
    }    

    function echidna_bids() public returns (bool) { 

        // auction settled, auctionHouse deletes the bid
        if (bids[1].latestDiscountUpdateTime == 0) return true;

        if (_amountToRaise - bids[1].amountToRaise != SAFEEngineMock(address(safeEngine)).receivedCoin(auctionIncomeRecipient)) return false; // rad
        if (_amountToSell - bids[1].amountToSell != SAFEEngineMock(address(safeEngine)).sentCollateral(address(this))) return false;
        if (_amountToRaise - bids[1].amountToRaise != LiquidationEngineMock(address(liquidationEngine)).removedCoinsFromAuction()) return false;
        if (bids[1].forgoneCollateralReceiver != _forgoneCollateralReceiver) return false;
        if (bids[1].auctionIncomeRecipient != auctionIncomeRecipient) return false;

        if (bids[1].currentDiscount > 0.95E18 || bids[1].currentDiscount < 0.90E18) return false;
        if (bids[1].maxDiscount != 0.90E18) return false;
        if (bids[1].perSecondDiscountUpdateRate != 999998607628240588157433861) return false;

        if (auctions[1].initialAmountToSell - bids[1].amountToSell != SAFEEngineMock(address(safeEngine)).sentCollateral(address(this))) return false; 
        if (SAFEEngineMock(address(safeEngine)).receivedCoin(auctionIncomeRecipient) != LiquidationEngineMock(address(liquidationEngine)).removedCoinsFromAuction()) return false;
        if (SAFEEngineMock(address(safeEngine)).receivedCoin(auctionIncomeRecipient) != auctions[1].initialAmountToRaise - bids[1].amountToRaise) return false;

        return true;
    }

    // adding a directed bidding function
    // we trust the fuzzer will find it's way to the active auction (it does), but here we're forcing valid bids to make we make the most of the runs.
    // (the buyCollateral function is also fuzzed)
    // setting it's visibility to internal will prevent it to be called by echidna
    function bid(uint val) public {
        if (bids[1].latestDiscountUpdateTime != 0)
            buyCollateral(1, val %  bids[1].amountToSell);
    }
}

// @notice Will allow echidna accounts to create auctions and bid
contract FuzzAuctionsAndBids is IncreasingDiscountCollateralAuctionHouseMock {

    address auctionIncomeRecipient = address(0xfab);
    address _forgoneCollateralReceiver = address(0xacab);
    uint _amountToRaise = 50 * 10 ** 45;
    uint _amountToSell = 100 ether;    

    constructor() public IncreasingDiscountCollateralAuctionHouseMock(
            address(new SAFEEngineMock()),
            address(new LiquidationEngineMock()),
            "ETH-A" 
        ) {
            setUp();
        }

    function setUp() public {
            // creating feeds
            collateralFSM = OracleLike(address(new Feed(bytes32(uint256(200 ether)), true)));
            oracleRelayer = OracleRelayerLike(address(new OracleRelayerMock()));

            // config increasing discount
            modifyParameters("perSecondDiscountUpdateRate", 999998607628240588157433861); // -0.5% per hour
            modifyParameters("maxDiscount", 0.50E18); // 50%
            modifyParameters("maxDiscountUpdateRateTimeline", 50 weeks);

            // authing accounts, authing them will also allow to modify parameters
            authorizedAccounts[address(0x10000)] = 1;
            authorizedAccounts[address(0x20000)] = 1;
            authorizedAccounts[address(0xabc00)] = 1;
    }

    // properties

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
        return minDiscount == 0.95E18;
    }

    function echidna_maxDiscount() public returns (bool) { 
        return maxDiscount == 0.50E18;
    }

    function echidna_perSecondDiscountUpdateRate() public returns (bool) { 
        return perSecondDiscountUpdateRate == 999998607628240588157433861;
    }

    function echidna_maxDiscountUpdateRateTimeline() public returns (bool) { 
        return maxDiscountUpdateRateTimeline == 50 weeks;
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

    // auxiliary structure to track auction initial data
    struct AuctionData {
        uint initialAmountToRaise;
        uint initialAmountToSell;
    }

    mapping (uint256 => AuctionData) internal auctions;

    function startAuction(
        address, address,
        uint256 amountToRaise,
        uint256 amountToSell,
        uint256 initialBid
    ) public override returns (uint256 id) {
        id = super.startAuction(
            _forgoneCollateralReceiver,
            auctionIncomeRecipient,
            amountToRaise,
            amountToSell,
            initialBid
        );

        auctions[id] = AuctionData(amountToRaise, amountToSell);
    }

    function echidna_bids() public returns (bool) { 
        if (auctionsStarted == 0) return true;

        uint pendingAmountToRaise;
        uint pendingAmountToSell;
        uint totalAmountToRaise;
        uint totalAmountToSell;

        for (uint i = 1; i <= auctionsStarted; i++) {
            totalAmountToRaise += auctions[i].initialAmountToRaise;
            totalAmountToSell += auctions[i].initialAmountToSell;
            pendingAmountToRaise += bids[i].amountToRaise;
            pendingAmountToSell += bids[i].amountToSell;

            if (bids[i].forgoneCollateralReceiver != address(0)) { // auction not yet settled
                if (bids[i].currentDiscount > 0.95E18 || bids[i].currentDiscount < 0.50E18) return false;
                if (bids[i].maxDiscount != 0.50E18) return false;
                if (bids[i].perSecondDiscountUpdateRate != 999998607628240588157433861) return false;
            }

        }

        if (totalAmountToSell - pendingAmountToSell != SAFEEngineMock(address(safeEngine)).sentCollateral(address(this))) return false;
        if (SAFEEngineMock(address(safeEngine)).receivedCoin(auctionIncomeRecipient) != LiquidationEngineMock(address(liquidationEngine)).removedCoinsFromAuction()) return false;
        if (SAFEEngineMock(address(safeEngine)).receivedCoin(auctionIncomeRecipient) != totalAmountToRaise - pendingAmountToRaise) return false;

        return true;
    }

    // adding a directed bidding function
    // we trust the fuzzer will find it's way to the active auction (it does), but here we're forcing valid bids to make we make the most of the runs.
    // (the buyCollateral function is also fuzzed)
    // setting it's visibility to internal will prevent it to be called by echidna
    function bid(uint campaign, uint val) internal {
        buyCollateral(campaign % auctionsStarted, val %  bids[campaign % auctionsStarted].amountToSell);
    }
}
