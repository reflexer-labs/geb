pragma solidity 0.6.7;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";

import {MultiTaxCollector} from "../../multi/MultiTaxCollector.sol";
import {MultiSAFEEngine} from "../../multi/MultiSAFEEngine.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

abstract contract MultiSAFEEngineLike {
    function collateralTypes(bytes32, bytes32) virtual public view returns (
        uint256 debtAmount,
        uint256 accumulatedRate,
        uint256 safetyPrice,
        uint256 debtCeiling,
        uint256 debtFloor,
        uint256 liquidationPrice
    );
}

contract MultiTaxCollectorTest is DSTest {
    Hevm hevm;
    MultiTaxCollector taxCollector;
    MultiSAFEEngine safeEngine;

    function ray(uint wad_) internal pure returns (uint) {
        return wad_ * 10 ** 9;
    }
    function rad(uint wad_) internal pure returns (uint) {
        return wad_ * 10 ** 27;
    }
    function wad(uint rad_) internal pure returns (uint) {
        return rad_ / 10 ** 27;
    }
    function wad(int rad_) internal pure returns (uint) {
        return uint(rad_ / 10 ** 27);
    }
    function updateTime(bytes32 coinName_, bytes32 collateralType) internal view returns (uint) {
        (uint stabilityFee, uint updateTime_) = taxCollector.collateralTypes(coinName_, collateralType); stabilityFee;
        return updateTime_;
    }
    function debtAmount(bytes32 coinName_, bytes32 collateralType) internal view returns (uint debtAmountV) {
        (debtAmountV,,,,,) = MultiSAFEEngineLike(address(safeEngine)).collateralTypes(coinName_, collateralType);
    }
    function accumulatedRate(bytes32 coinName_, bytes32 collateralType) internal view returns (uint accumulatedRateV) {
        (, accumulatedRateV,,,,) = MultiSAFEEngineLike(address(safeEngine)).collateralTypes(coinName_, collateralType);
    }
    function debtCeiling(bytes32 coinName_, bytes32 collateralType) internal view returns (uint debtCeilingV) {
        (,,, debtCeilingV,,) = MultiSAFEEngineLike(address(safeEngine)).collateralTypes(coinName_, collateralType);
    }

    uint256 coreReceiverTaxCut = 10 ** 29 / 5;

    address ali  = address(bytes20("ali"));
    address bob  = address(bytes20("bob"));
    address char = address(bytes20("char"));

    address coreReceiver = address(bytes20("dan"));

    bytes32 coinName = "MAI";
    bytes32 secondCoinName = "BAI";

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine  = new MultiSAFEEngine();
        safeEngine.initializeCoin(coinName, uint(-1));
        safeEngine.initializeCoin(secondCoinName, uint(-1));

        safeEngine.initializeCollateralType(coinName, "i");
        safeEngine.initializeCollateralType(secondCoinName, "i");

        safeEngine.addCollateralJoin("i", address(this));

        taxCollector = new MultiTaxCollector(address(safeEngine), coreReceiver, coreReceiverTaxCut);
        taxCollector.initializeCoin(coinName);
        taxCollector.initializeCoin(secondCoinName);

        taxCollector.initializeCollateralType(coinName, "i");
        taxCollector.initializeCollateralType(secondCoinName, "i");

        safeEngine.addSystemComponent(address(taxCollector));

        draw(coinName, "i", 100 ether);
        draw(secondCoinName, "i", 100 ether);
    }
    function draw(bytes32 coinName_, bytes32 collateralType, uint coin) internal {
        safeEngine.modifyParameters(coinName_, collateralType, "debtCeiling", debtCeiling(coinName_, collateralType) + rad(coin));
        safeEngine.modifyParameters(coinName_, collateralType, "safetyPrice", 10 ** 27 * 10000 ether);

        address self = address(this);

        safeEngine.modifyCollateralBalance(collateralType, self,  10 ** 27 * 1 ether);
        safeEngine.modifySAFECollateralization(coinName_, collateralType, self, self, self, int(1 ether), int(coin));
    }
    function test_collect_tax_setup() public {
        hevm.warp(0);
        assertEq(uint(now), 0);
        hevm.warp(1);
        assertEq(uint(now), 1);
        hevm.warp(2);
        assertEq(uint(now), 2);
        assertEq(debtAmount(coinName, "i"), 100 ether);
        assertEq(debtAmount(secondCoinName, "i"), 100 ether);
    }
    function test_collect_tax_updates_updateTime() public {
        assertEq(updateTime(coinName, "i"), now);
        assertEq(updateTime(secondCoinName, "i"), now);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 10 ** 27);
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 10 ** 27);

        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");
        assertEq(updateTime(coinName, "i"), now);
        assertEq(updateTime(secondCoinName, "i"), now);

        hevm.warp(now + 1);
        assertEq(updateTime(coinName, "i"), now - 1);
        assertEq(updateTime(secondCoinName, "i"), now - 1);
        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");
        assertEq(updateTime(coinName, "i"), now);
        assertEq(updateTime(secondCoinName, "i"), now);

        hevm.warp(now + 1 days);
        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");
        assertEq(updateTime(coinName, "i"), now);
        assertEq(updateTime(secondCoinName, "i"), now);
    }
    function test_collect_tax_modifyParameters() public {
        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 10 ** 27);
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 10 ** 27);
        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");
        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1000000564701133626865910626);  // 5% / day
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1000000564701133626865910626);  // 5% / day
    }
    function test_collect_tax_0d() public {
        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1000000564701133626865910626);  // 5% / day
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1000000564701133626865910626);  // 5% / day

        assertEq(safeEngine.coinBalance(coinName, ali), rad(0 ether));
        assertEq(safeEngine.coinBalance(secondCoinName, ali), rad(0 ether));

        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");
        assertEq(safeEngine.coinBalance(coinName, ali), rad(0 ether));
        assertEq(safeEngine.coinBalance(secondCoinName, ali), rad(0 ether));
    }
    function test_collect_tax_1d() public {
        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1000000564701133626865910626);  // 5% / day
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1000000564701133626865910626);  // 5% / day

        hevm.warp(now + 1 days);
        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 0 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 0 ether);

        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");
        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 4 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 4 ether);

        assertEq(wad(safeEngine.coinBalance(coinName, coreReceiver)), 1 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, coreReceiver)), 1 ether);
    }
    function test_collect_tax_2d() public {
        taxCollector.modifyParameters("primaryTaxReceiver", ali);
        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1000000564701133626865910626);  // 5% / day
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1000000564701133626865910626);  // 5% / day

        hevm.warp(now + 2 days);
        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 0 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 0 ether);

        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");
        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 8.2 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 8.2 ether);

        assertEq(wad(safeEngine.coinBalance(coinName, coreReceiver)), 2.05 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, coreReceiver)), 2.05 ether);
    }
    function test_collect_tax_3d() public {
        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1000000564701133626865910626);  // 5% / day
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1000000564701133626865910626);  // 5% / day

        hevm.warp(now + 3 days);
        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 0 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 0 ether);

        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");

        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 12.61 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 12.61 ether);

        assertEq(wad(safeEngine.coinBalance(coinName, coreReceiver)), 3.1525 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, coreReceiver)), 3.1525 ether);
    }
    function test_collect_tax_negative_3d() public {
        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 999999706969857929985428567);  // -2.5% / day
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 999999706969857929985428567);  // -2.5% / day

        hevm.warp(now + 3 days);
        assertEq(wad(safeEngine.coinBalance(coinName, address(this))), 100 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, address(this))), 100 ether);

        safeEngine.transferInternalCoins(coinName, address(this), ali, rad(50 ether));
        safeEngine.transferInternalCoins(secondCoinName, address(this), ali, rad(50 ether));

        safeEngine.transferInternalCoins(coinName, address(this), coreReceiver, rad(50 ether));
        safeEngine.transferInternalCoins(secondCoinName, address(this), coreReceiver, rad(50 ether));

        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 50 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 50 ether);

        taxCollector.taxSingle(coinName, "i");
        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 42.6859375 ether);
        assertEq(wad(safeEngine.coinBalance(coinName, coreReceiver)), 50 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, coreReceiver)), 50 ether);

        taxCollector.taxSingle(secondCoinName, "i");
        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 42.6859375 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, coreReceiver)), 50 ether);
        assertEq(wad(safeEngine.coinBalance(coinName, coreReceiver)), 50 ether);
    }
    function test_collect_tax_multi() public {
        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1000000564701133626865910626);  // 5% / day
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1000000564701133626865910626);  // 5% / day

        hevm.warp(now + 1 days);
        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");

        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 4 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 4 ether);
        assertEq(wad(safeEngine.coinBalance(coinName, coreReceiver)), 1 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, coreReceiver)), 1 ether);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1000001103127689513476993127);  // 10% / day
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1000001103127689513476993127);  // 10% / day

        hevm.warp(now + 1 days);
        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");

        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 12.4 ether);
        assertEq(wad(safeEngine.coinBalance(coinName, coreReceiver)), 3.1 ether);

        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 12.4 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, coreReceiver)), 3.1 ether);

        assertEq(wad(safeEngine.globalDebt(coinName)), 115.5 ether);
        assertEq(accumulatedRate(coinName, "i") / 10 ** 9, 1.155 ether);

        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 12.4 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, coreReceiver)), 3.1 ether);

        assertEq(wad(safeEngine.globalDebt(secondCoinName)), 115.5 ether);
        assertEq(accumulatedRate(secondCoinName, "i") / 10 ** 9, 1.155 ether);
    }
    function test_collect_tax_global_stability_fee() public {
        safeEngine.initializeCollateralType(coinName, "j");
        safeEngine.initializeCollateralType(secondCoinName, "j");

        safeEngine.addCollateralJoin("j", address(this));

        draw(coinName, "j", 100 ether);
        draw(secondCoinName, "j", 100 ether);

        taxCollector.initializeCollateralType(coinName, "j");
        taxCollector.initializeCollateralType(secondCoinName, "j");

        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1050000000000000000000000000); // 5% / second
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1050000000000000000000000000); // 5% / second

        taxCollector.modifyParameters(coinName, "j", "stabilityFee", 1000000000000000000000000000); // 0% / second
        taxCollector.modifyParameters(secondCoinName, "j", "stabilityFee", 1000000000000000000000000000); // 0% / second

        taxCollector.modifyParameters(coinName, "globalStabilityFee",  uint(50000000000000000000000000)); // 5% / second
        taxCollector.modifyParameters(secondCoinName, "globalStabilityFee",  uint(50000000000000000000000000)); // 5% / second

        hevm.warp(now + 1);

        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");

        taxCollector.taxSingle(coinName, "j");
        taxCollector.taxSingle(secondCoinName, "j");

        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 12 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 12 ether);

        assertEq(wad(safeEngine.coinBalance(coinName, coreReceiver)), 3 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, coreReceiver)), 3 ether);
    }
    function test_collect_tax_all_positive() public {
        safeEngine.initializeCollateralType(coinName, "j");
        safeEngine.initializeCollateralType(secondCoinName, "j");

        safeEngine.addCollateralJoin("j", address(this));

        draw(coinName, "j", 100 ether);
        draw(secondCoinName, "j", 100 ether);

        taxCollector.initializeCollateralType(coinName, "j");
        taxCollector.initializeCollateralType(secondCoinName, "j");

        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1050000000000000000000000000);       // 5% / second
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1050000000000000000000000000); // 5% / second

        taxCollector.modifyParameters(coinName, "j", "stabilityFee", 1030000000000000000000000000);       // 3% / second
        taxCollector.modifyParameters(secondCoinName, "j", "stabilityFee", 1030000000000000000000000000);       // 3% / second

        taxCollector.modifyParameters(coinName, "globalStabilityFee",  uint(50000000000000000000000000));  // 5% / second
        taxCollector.modifyParameters(secondCoinName, "globalStabilityFee",  uint(50000000000000000000000000));  // 5% / second

        hevm.warp(now + 1);
        taxCollector.taxMany(coinName, 0, taxCollector.collateralListLength(coinName) - 1);
        taxCollector.taxMany(secondCoinName, 0, taxCollector.collateralListLength(secondCoinName) - 1);

        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 14.4 ether);
        assertEq(wad(safeEngine.coinBalance(coinName, coreReceiver)), 3.6 ether);

        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 14.4 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, coreReceiver)), 3.6 ether);

        (, uint updatedTime) = taxCollector.collateralTypes(coinName, "i");
        assertEq(updatedTime, now);

        (, updatedTime) = taxCollector.collateralTypes(secondCoinName, "i");
        assertEq(updatedTime, now);

        (, updatedTime) = taxCollector.collateralTypes(coinName, "j");
        assertEq(updatedTime, now);

        (, updatedTime) = taxCollector.collateralTypes(secondCoinName, "j");
        assertEq(updatedTime, now);

        assertTrue(taxCollector.collectedManyTax(coinName, 0, 1));
        assertTrue(taxCollector.collectedManyTax(secondCoinName, 0, 1));
    }
    function test_collect_tax_all_some_negative() public {
        safeEngine.initializeCollateralType(coinName, "j");
        safeEngine.initializeCollateralType(secondCoinName, "j");

        safeEngine.addCollateralJoin("j", address(this));

        draw(coinName, "j", 100 ether);
        draw(secondCoinName, "j", 100 ether);

        taxCollector.initializeCollateralType(coinName, "j");
        taxCollector.initializeCollateralType(secondCoinName, "j");

        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1050000000000000000000000000);
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1050000000000000000000000000);

        taxCollector.modifyParameters(coinName, "j", "stabilityFee", 900000000000000000000000000);
        taxCollector.modifyParameters(secondCoinName, "j", "stabilityFee", 900000000000000000000000000);

        hevm.warp(now + 10);

        assertEq(wad(safeEngine.coinBalance(coinName, coreReceiver)), 0);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, coreReceiver)), 0);

        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(coinName, "j");

        taxCollector.taxSingle(secondCoinName, "i");
        taxCollector.taxSingle(secondCoinName, "j");

        assertEq(safeEngine.coinBalance(coinName, ali), 0);
        assertEq(safeEngine.coinBalance(secondCoinName, ali), 0);

        assertEq(wad(safeEngine.coinBalance(coinName, coreReceiver)), 12577892535548828125);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, coreReceiver)), 12577892535548828125);

        (, uint updatedTime) = taxCollector.collateralTypes(coinName, "i");
        assertEq(updatedTime, now);

        (, updatedTime) = taxCollector.collateralTypes(secondCoinName, "i");
        assertEq(updatedTime, now);

        (, updatedTime) = taxCollector.collateralTypes(coinName, "j");
        assertEq(updatedTime, now);

        (, updatedTime) = taxCollector.collateralTypes(secondCoinName, "j");
        assertEq(updatedTime, now);

        assertTrue(taxCollector.collectedManyTax(coinName, 0, 1));
        assertTrue(taxCollector.collectedManyTax(secondCoinName, 0, 1));
    }
    function testFail_add_same_tax_receiver_twice() public {
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 10);
        taxCollector.modifyParameters(coinName, "i", 1, ray(1 ether), address(this));
        taxCollector.modifyParameters(coinName, "i", 2, ray(1 ether), address(this));
    }
    function testFail_cut_at_hundred() public {
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 10);
        taxCollector.modifyParameters(coinName, "i", 0, ray(100 ether), address(this));
    }
    function testFail_add_over_maxSecondaryReceivers() public {
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 1);
        taxCollector.modifyParameters(coinName, "i", 1, ray(1 ether), address(this));
        taxCollector.modifyParameters(coinName, "i", 2, ray(1 ether), ali);
    }
    function testFail_modify_cut_total_over_hundred() public {
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 1);
        taxCollector.modifyParameters(coinName, "i", 1, ray(1 ether), address(this));
        taxCollector.modifyParameters(coinName, "i", 1, ray(100.1 ether), address(this));
    }
    function testFail_remove_past_node() public {
        // Add
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(coinName, "i", 1, ray(1 ether), address(this));
        // Remove
        taxCollector.modifyParameters(coinName, "i", 1, 0, address(this));
        taxCollector.modifyParameters(coinName, "i", 1, 0, address(this));
    }
    function testFail_tax_receiver_primaryTaxReceiver() public {
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 1);
        taxCollector.modifyParameters("primaryTaxReceiver", ali);
        taxCollector.modifyParameters(coinName, "i", 1, ray(1 ether), ali);
    }
    function testFail_tax_receiver_null() public {
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 1);
        taxCollector.modifyParameters(coinName, "i", 1, ray(1 ether), address(0));
    }
    function test_add_tax_secondaryTaxReceivers() public {
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(coinName, "i", 1, ray(1 ether), address(this));

        taxCollector.modifyParameters(secondCoinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(1 ether), address(this));

        assertEq(taxCollector.secondaryReceiverAllotedTax(coinName, "i"), ray(1 ether));
        assertEq(taxCollector.latestSecondaryReceiver(coinName), 1);
        assertEq(taxCollector.usedSecondaryReceiver(coinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 1), address(this));

        assertEq(taxCollector.secondaryReceiverAllotedTax(secondCoinName, "i"), ray(1 ether));
        assertEq(taxCollector.latestSecondaryReceiver(secondCoinName), 1);
        assertEq(taxCollector.usedSecondaryReceiver(secondCoinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 1), address(this));

        (uint canTakeBackTax, uint taxPercentage) = taxCollector.secondaryTaxReceivers(coinName, "i", 1);
        assertEq(canTakeBackTax, 0);
        assertEq(taxPercentage, ray(1 ether));
        assertEq(taxCollector.latestSecondaryReceiver(coinName), 1);

        (canTakeBackTax, taxPercentage) = taxCollector.secondaryTaxReceivers(secondCoinName, "i", 1);
        assertEq(canTakeBackTax, 0);
        assertEq(taxPercentage, ray(1 ether));
        assertEq(taxCollector.latestSecondaryReceiver(secondCoinName), 1);
    }
    function test_modify_tax_receiver_cut() public {
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 1);
        taxCollector.modifyParameters(coinName, "i", 1, ray(1 ether), address(this));
        taxCollector.modifyParameters(coinName, "i", 1, ray(99.9 ether) - coreReceiverTaxCut, address(this));

        taxCollector.modifyParameters(secondCoinName, "maxSecondaryReceivers", 1);
        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(1 ether), address(this));
        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(98.9 ether) - coreReceiverTaxCut, address(this));

        uint Cut = taxCollector.secondaryReceiverAllotedTax(coinName, "i");
        assertEq(Cut, ray(99.9 ether) - coreReceiverTaxCut);

        Cut = taxCollector.secondaryReceiverAllotedTax(secondCoinName, "i");
        assertEq(Cut, ray(98.9 ether) - coreReceiverTaxCut);

        (,uint cut) = taxCollector.secondaryTaxReceivers(coinName, "i", 1);
        assertEq(cut, ray(99.9 ether) - coreReceiverTaxCut);

        (, cut) = taxCollector.secondaryTaxReceivers(secondCoinName, "i", 1);
        assertEq(cut, ray(98.9 ether) - coreReceiverTaxCut);
    }
    function test_remove_some_tax_secondaryTaxReceivers() public {
        // Add
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(coinName, "i", 1, ray(1 ether), address(this));
        taxCollector.modifyParameters(coinName, "i", 2, ray(98 ether) - coreReceiverTaxCut, ali);

        taxCollector.modifyParameters(secondCoinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(0.5 ether), address(this));
        taxCollector.modifyParameters(secondCoinName, "i", 2, ray(99 ether) - coreReceiverTaxCut, ali);

        assertEq(taxCollector.secondaryReceiverAllotedTax(coinName, "i"), ray(98 ether) - coreReceiverTaxCut + ray(1 ether));
        assertEq(taxCollector.latestSecondaryReceiver(coinName), 2);
        assertEq(taxCollector.usedSecondaryReceiver(coinName, ali), 1);
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, ali), 1);
        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 2), ali);
        assertEq(taxCollector.usedSecondaryReceiver(coinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 1), address(this));

        assertEq(taxCollector.secondaryReceiverAllotedTax(secondCoinName, "i"), ray(99 ether) - coreReceiverTaxCut + ray(0.5 ether));
        assertEq(taxCollector.latestSecondaryReceiver(secondCoinName), 2);
        assertEq(taxCollector.usedSecondaryReceiver(secondCoinName, ali), 1);
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, ali), 1);
        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 2), ali);
        assertEq(taxCollector.usedSecondaryReceiver(secondCoinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 1), address(this));

        (uint take, uint cut) = taxCollector.secondaryTaxReceivers(coinName, "i", 2);
        assertEq(take, 0);
        assertEq(cut, ray(98 ether) - coreReceiverTaxCut);
        assertEq(taxCollector.latestSecondaryReceiver(coinName), 2);

        (take, cut) = taxCollector.secondaryTaxReceivers(secondCoinName, "i", 2);
        assertEq(take, 0);
        assertEq(cut, ray(99 ether) - coreReceiverTaxCut);
        assertEq(taxCollector.latestSecondaryReceiver(secondCoinName), 2);

        // Remove
        taxCollector.modifyParameters(coinName, "i", 1, 0, address(this));
        taxCollector.modifyParameters(secondCoinName, "i", 1, 0, address(this));

        assertEq(taxCollector.secondaryReceiverAllotedTax(coinName, "i"), ray(98 ether) - coreReceiverTaxCut);
        assertEq(taxCollector.usedSecondaryReceiver(coinName, address(this)), 0);
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, address(this)), 0);
        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 1), address(0));

        assertEq(taxCollector.secondaryReceiverAllotedTax(secondCoinName, "i"), ray(99 ether) - coreReceiverTaxCut);
        assertEq(taxCollector.usedSecondaryReceiver(secondCoinName, address(this)), 0);
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, address(this)), 0);
        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 1), address(0));

        (take, cut) = taxCollector.secondaryTaxReceivers(coinName, "i", 1);
        assertEq(take, 0);
        assertEq(cut, 0);
        assertEq(taxCollector.latestSecondaryReceiver(coinName), 2);
        assertEq(taxCollector.usedSecondaryReceiver(coinName, ali), 1);
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, ali), 1);
        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 2), ali);

        (take, cut) = taxCollector.secondaryTaxReceivers(secondCoinName, "i", 1);
        assertEq(take, 0);
        assertEq(cut, 0);
        assertEq(taxCollector.latestSecondaryReceiver(secondCoinName), 2);
        assertEq(taxCollector.usedSecondaryReceiver(secondCoinName, ali), 1);
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, ali), 1);
        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 2), ali);
    }
    function test_remove_all_secondaryTaxReceivers() public {
        // Add
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(coinName, "i", 1, ray(1 ether), address(this));
        taxCollector.modifyParameters(coinName, "i", 2, ray(98 ether) - coreReceiverTaxCut, ali);

        taxCollector.modifyParameters(secondCoinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(1 ether), address(this));
        taxCollector.modifyParameters(secondCoinName, "i", 2, ray(98 ether) - coreReceiverTaxCut, ali);

        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 1), address(this));
        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 2), ali);
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, ali), 1);

        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 1), address(this));
        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 2), ali);
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, ali), 1);

        // Remove
        taxCollector.modifyParameters(coinName, "i", 2, 0, ali);
        taxCollector.modifyParameters(coinName, "i", 1, 0, address(this));

        taxCollector.modifyParameters(secondCoinName, "i", 2, 0, ali);
        taxCollector.modifyParameters(secondCoinName, "i", 1, 0, address(this));

        uint Cut = taxCollector.secondaryReceiverAllotedTax(coinName, "i");
        assertEq(Cut, 0);
        assertEq(taxCollector.usedSecondaryReceiver(coinName, ali), 0);
        assertEq(taxCollector.usedSecondaryReceiver(coinName, address(0)), 0);
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, ali), 0);
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, address(this)), 0);
        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 2), address(0));
        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 1), address(0));

        Cut = taxCollector.secondaryReceiverAllotedTax(secondCoinName, "i");
        assertEq(Cut, 0);
        assertEq(taxCollector.usedSecondaryReceiver(secondCoinName, ali), 0);
        assertEq(taxCollector.usedSecondaryReceiver(secondCoinName, address(0)), 0);
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, ali), 0);
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, address(this)), 0);
        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 2), address(0));
        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 1), address(0));

        (uint take, uint cut) = taxCollector.secondaryTaxReceivers(coinName, "i", 1);
        assertEq(take, 0);
        assertEq(cut, 0);
        assertEq(taxCollector.latestSecondaryReceiver(coinName), 0);

        (take, cut) = taxCollector.secondaryTaxReceivers(secondCoinName, "i", 1);
        assertEq(take, 0);
        assertEq(cut, 0);
        assertEq(taxCollector.latestSecondaryReceiver(secondCoinName), 0);
    }
    function test_add_remove_add_secondaryTaxReceivers() public {
        // Add
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(coinName, "i", 1, ray(1 ether), address(this));
        assertTrue(taxCollector.isSecondaryReceiver(coinName, 1));

        taxCollector.modifyParameters(secondCoinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(1 ether), address(this));
        assertTrue(taxCollector.isSecondaryReceiver(secondCoinName, 1));

        // Remove
        taxCollector.modifyParameters(coinName, "i", 1, 0, address(this));
        assertTrue(!taxCollector.isSecondaryReceiver(coinName, 1));

        taxCollector.modifyParameters(secondCoinName, "i", 1, 0, address(this));
        assertTrue(!taxCollector.isSecondaryReceiver(secondCoinName, 1));

        // Add again
        taxCollector.modifyParameters(coinName, "i", 2, ray(1 ether), address(this));
        assertEq(taxCollector.secondaryReceiverAllotedTax(coinName, "i"), ray(1 ether));
        assertEq(taxCollector.latestSecondaryReceiver(coinName), 2);
        assertEq(taxCollector.usedSecondaryReceiver(coinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 2), address(this));
        assertEq(taxCollector.secondaryReceiversAmount(coinName), 1);
        assertTrue(taxCollector.isSecondaryReceiver(coinName, 2));

        taxCollector.modifyParameters(secondCoinName, "i", 2, ray(1 ether), address(this));
        assertEq(taxCollector.secondaryReceiverAllotedTax(secondCoinName, "i"), ray(1 ether));
        assertEq(taxCollector.latestSecondaryReceiver(secondCoinName), 2);
        assertEq(taxCollector.usedSecondaryReceiver(secondCoinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 2), address(this));
        assertEq(taxCollector.secondaryReceiversAmount(secondCoinName), 1);
        assertTrue(taxCollector.isSecondaryReceiver(secondCoinName, 2));

        (uint take, uint cut) = taxCollector.secondaryTaxReceivers(coinName, "i", 2);
        assertEq(take, 0);
        assertEq(cut, ray(1 ether));

        (take, cut) = taxCollector.secondaryTaxReceivers(secondCoinName, "i", 2);
        assertEq(take, 0);
        assertEq(cut, ray(1 ether));

        // Remove again
        taxCollector.modifyParameters(coinName, "i", 2, 0, address(this));
        assertEq(taxCollector.secondaryReceiverAllotedTax(coinName, "i"), 0);
        assertEq(taxCollector.latestSecondaryReceiver(coinName), 0);
        assertEq(taxCollector.usedSecondaryReceiver(coinName, address(this)), 0);
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, address(this)), 0);
        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 2), address(0));
        assertTrue(!taxCollector.isSecondaryReceiver(coinName, 2));

        taxCollector.modifyParameters(secondCoinName, "i", 2, 0, address(this));
        assertEq(taxCollector.secondaryReceiverAllotedTax(secondCoinName, "i"), 0);
        assertEq(taxCollector.latestSecondaryReceiver(secondCoinName), 0);
        assertEq(taxCollector.usedSecondaryReceiver(secondCoinName, address(this)), 0);
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, address(this)), 0);
        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 2), address(0));
        assertTrue(!taxCollector.isSecondaryReceiver(secondCoinName, 2));

        (take, cut) = taxCollector.secondaryTaxReceivers(coinName, "i", 2);
        assertEq(take, 0);
        assertEq(cut, 0);

        (take, cut) = taxCollector.secondaryTaxReceivers(secondCoinName, "i", 2);
        assertEq(take, 0);
        assertEq(cut, 0);
    }
    function test_multi_collateral_types_receivers() public {
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 1);
        taxCollector.modifyParameters(secondCoinName, "maxSecondaryReceivers", 1);

        safeEngine.initializeCollateralType(coinName, "j");
        safeEngine.initializeCollateralType(secondCoinName, "j");

        safeEngine.addCollateralJoin("j", address(this));

        taxCollector.initializeCollateralType(coinName, "j");
        taxCollector.initializeCollateralType(secondCoinName, "j");

        draw(coinName, "j", 100 ether);
        draw(secondCoinName, "j", 100 ether);

        taxCollector.modifyParameters(coinName, "i", 1, ray(1 ether), address(this));
        taxCollector.modifyParameters(coinName, "j", 1, ray(1 ether), address(0));

        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(1 ether), address(this));
        taxCollector.modifyParameters(secondCoinName, "j", 1, ray(1 ether), address(0));

        assertEq(taxCollector.usedSecondaryReceiver(coinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 1), address(this));
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, address(this)), 2);
        assertEq(taxCollector.latestSecondaryReceiver(coinName), 1);

        assertEq(taxCollector.usedSecondaryReceiver(secondCoinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 1), address(this));
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, address(this)), 2);
        assertEq(taxCollector.latestSecondaryReceiver(secondCoinName), 1);

        taxCollector.modifyParameters(coinName, "i", 1, 0, address(0));
        taxCollector.modifyParameters(secondCoinName, "i", 1, 0, address(0));

        assertEq(taxCollector.usedSecondaryReceiver(coinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 1), address(this));
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, address(this)), 1);
        assertEq(taxCollector.latestSecondaryReceiver(coinName), 1);

        assertEq(taxCollector.usedSecondaryReceiver(secondCoinName, address(this)), 1);
        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 1), address(this));
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, address(this)), 1);
        assertEq(taxCollector.latestSecondaryReceiver(secondCoinName), 1);

        taxCollector.modifyParameters(coinName, "j", 1, 0, address(0));
        taxCollector.modifyParameters(secondCoinName, "j", 1, 0, address(0));

        assertEq(taxCollector.usedSecondaryReceiver(coinName, address(this)), 0);
        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 1), address(0));
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, address(this)), 0);
        assertEq(taxCollector.latestSecondaryReceiver(coinName), 0);

        assertEq(taxCollector.usedSecondaryReceiver(secondCoinName, address(this)), 0);
        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 1), address(0));
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, address(this)), 0);
        assertEq(taxCollector.latestSecondaryReceiver(secondCoinName), 0);
    }
    function test_toggle_receiver_take() public {
        // Add
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(coinName, "i", 1, ray(1 ether), address(this));

        taxCollector.modifyParameters(secondCoinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(1 ether), address(this));

        // Toggle
        taxCollector.modifyParameters(coinName, "i", 1, 1);
        (uint take,) = taxCollector.secondaryTaxReceivers(coinName, "i", 1);
        assertEq(take, 1);

        taxCollector.modifyParameters(secondCoinName, "i", 1, 1);
        (take,) = taxCollector.secondaryTaxReceivers(secondCoinName, "i", 1);
        assertEq(take, 1);

        taxCollector.modifyParameters(coinName, "i", 1, 5);
        (take,) = taxCollector.secondaryTaxReceivers(coinName, "i", 1);
        assertEq(take, 5);

        taxCollector.modifyParameters(secondCoinName, "i", 1, 5);
        (take,) = taxCollector.secondaryTaxReceivers(secondCoinName, "i", 1);
        assertEq(take, 5);

        taxCollector.modifyParameters(coinName, "i", 1, 0);
        (take,) = taxCollector.secondaryTaxReceivers(coinName, "i", 1);
        assertEq(take, 0);

        taxCollector.modifyParameters(secondCoinName, "i", 1, 0);
        (take,) = taxCollector.secondaryTaxReceivers(secondCoinName, "i", 1);
        assertEq(take, 0);
    }
    function test_add_secondaryTaxReceivers_single_collateral_type_collect_tax_positive() public {
        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1050000000000000000000000000);
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1050000000000000000000000000);

        taxCollector.modifyParameters("primaryTaxReceiver", ali);
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(coinName, "i", 1, ray(40 ether) - coreReceiverTaxCut / 2, bob);
        taxCollector.modifyParameters(coinName, "i", 2, ray(45 ether) - coreReceiverTaxCut / 2, char);

        taxCollector.modifyParameters(secondCoinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(40 ether) - coreReceiverTaxCut / 2, bob);
        taxCollector.modifyParameters(secondCoinName, "i", 2, ray(45 ether) - coreReceiverTaxCut / 2, char);

        assertEq(taxCollector.latestSecondaryReceiver(coinName), 2);
        assertEq(taxCollector.latestSecondaryReceiver(secondCoinName), 2);

        hevm.warp(now + 10);
        (, int currentRates) = taxCollector.taxSingleOutcome(coinName, "i");
        taxCollector.taxSingle(coinName, "i");
        assertEq(taxCollector.latestSecondaryReceiver(coinName), 2);

        (, currentRates) = taxCollector.taxSingleOutcome(secondCoinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");
        assertEq(taxCollector.latestSecondaryReceiver(secondCoinName), 2);

        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 9433419401661621093);
        assertEq(wad(safeEngine.coinBalance(coinName, bob)), 18866838803323242187);
        assertEq(wad(safeEngine.coinBalance(coinName, char)), 22011311937210449218);

        assertEq(wad(safeEngine.coinBalance(coinName, ali)) * ray(100 ether) / uint(currentRates), 1499999999999999999880);
        assertEq(wad(safeEngine.coinBalance(coinName, bob)) * ray(100 ether) / uint(currentRates), 2999999999999999999920);
        assertEq(wad(safeEngine.coinBalance(coinName, char)) * ray(100 ether) / uint(currentRates), 3499999999999999999880);

        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 9433419401661621093);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, bob)), 18866838803323242187);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, char)), 22011311937210449218);

        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)) * ray(100 ether) / uint(currentRates), 1499999999999999999880);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, bob)) * ray(100 ether) / uint(currentRates), 2999999999999999999920);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, char)) * ray(100 ether) / uint(currentRates), 3499999999999999999880);
    }
    function testFail_tax_when_safe_engine_is_disabled() public {
        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1050000000000000000000000000);
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1050000000000000000000000000);

        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(coinName, "i", 1, ray(40 ether) - coreReceiverTaxCut / 2, bob);
        taxCollector.modifyParameters(coinName, "i", 2, ray(45 ether) - coreReceiverTaxCut / 2, char);

        taxCollector.modifyParameters(secondCoinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(40 ether) - coreReceiverTaxCut / 2, bob);
        taxCollector.modifyParameters(secondCoinName, "i", 2, ray(45 ether) - coreReceiverTaxCut / 2, char);

        safeEngine.disableCoin(secondCoinName);

        hevm.warp(now + 10);
        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");
    }



    function test_add_secondaryTaxReceivers_multi_collateral_types_collect_tax_positive() public {
        taxCollector.modifyParameters("primaryTaxReceiver", ali);
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(secondCoinName, "maxSecondaryReceivers", 2);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1050000000000000000000000000);
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1050000000000000000000000000);

        safeEngine.initializeCollateralType(coinName, "j");
        safeEngine.initializeCollateralType(secondCoinName, "j");

        safeEngine.addCollateralJoin("j", address(this));

        taxCollector.initializeCollateralType(coinName, "j");
        taxCollector.initializeCollateralType(secondCoinName, "j");

        draw(coinName, "j", 100 ether);
        draw(secondCoinName, "j", 100 ether);

        taxCollector.modifyParameters(coinName, "j", "stabilityFee", 1050000000000000000000000000);
        taxCollector.modifyParameters(secondCoinName, "j", "stabilityFee", 1050000000000000000000000000);

        taxCollector.modifyParameters(coinName, "i", 1, ray(40 ether) - coreReceiverTaxCut / 2, bob);
        taxCollector.modifyParameters(coinName, "i", 2, ray(45 ether) - coreReceiverTaxCut / 2, char);

        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(40 ether) - coreReceiverTaxCut / 2, bob);
        taxCollector.modifyParameters(secondCoinName, "i", 2, ray(45 ether) - coreReceiverTaxCut / 2, char);

        hevm.warp(now + 10);
        taxCollector.taxMany(coinName, 0, taxCollector.collateralListLength(coinName) - 1);
        taxCollector.taxMany(secondCoinName, 0, taxCollector.collateralListLength(secondCoinName) - 1);

        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 59744989543856933593);
        assertEq(wad(safeEngine.coinBalance(coinName, bob)), 18866838803323242187);
        assertEq(wad(safeEngine.coinBalance(coinName, char)), 22011311937210449218);

        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 59744989543856933593);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, bob)), 18866838803323242187);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, char)), 22011311937210449218);

        taxCollector.modifyParameters(coinName, "j", 1, ray(25 ether), bob);
        taxCollector.modifyParameters(coinName, "j", 2, ray(33 ether), char);

        taxCollector.modifyParameters(secondCoinName, "j", 1, ray(25 ether), bob);
        taxCollector.modifyParameters(secondCoinName, "j", 2, ray(33 ether), char);

        hevm.warp(now + 10);
        taxCollector.taxMany(coinName, 0, taxCollector.collateralListLength(coinName) - 1);
        taxCollector.taxMany(secondCoinName, 0, taxCollector.collateralListLength(secondCoinName) - 1);

        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 97647903443435146518);
        assertEq(wad(safeEngine.coinBalance(coinName, bob)), 75209008113507072210);
        assertEq(wad(safeEngine.coinBalance(coinName, char)), 91670721266165002702);

        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 97647903443435146518);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, bob)), 75209008113507072210);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, char)), 91670721266165002702);

        assertEq(taxCollector.secondaryReceiverAllotedTax(coinName, "i"), ray(65 ether));
        assertEq(taxCollector.latestSecondaryReceiver(coinName), 2);
        assertEq(taxCollector.usedSecondaryReceiver(coinName, bob), 1);
        assertEq(taxCollector.usedSecondaryReceiver(coinName, char), 1);
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, bob), 2);
        assertEq(taxCollector.secondaryReceiverRevenueSources(coinName, char), 2);
        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 1), bob);
        assertEq(taxCollector.secondaryReceiverAccounts(coinName, 2), char);
        assertEq(taxCollector.secondaryReceiversAmount(coinName), 2);
        assertTrue(taxCollector.isSecondaryReceiver(coinName, 1));
        assertTrue(taxCollector.isSecondaryReceiver(coinName, 2));

        assertEq(taxCollector.secondaryReceiverAllotedTax(secondCoinName, "i"), ray(65 ether));
        assertEq(taxCollector.latestSecondaryReceiver(secondCoinName), 2);
        assertEq(taxCollector.usedSecondaryReceiver(secondCoinName, bob), 1);
        assertEq(taxCollector.usedSecondaryReceiver(secondCoinName, char), 1);
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, bob), 2);
        assertEq(taxCollector.secondaryReceiverRevenueSources(secondCoinName, char), 2);
        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 1), bob);
        assertEq(taxCollector.secondaryReceiverAccounts(secondCoinName, 2), char);
        assertEq(taxCollector.secondaryReceiversAmount(secondCoinName), 2);
        assertTrue(taxCollector.isSecondaryReceiver(secondCoinName, 1));
        assertTrue(taxCollector.isSecondaryReceiver(secondCoinName, 2));

        (uint take, uint cut) = taxCollector.secondaryTaxReceivers(coinName, "i", 1);
        assertEq(take, 0);
        assertEq(cut, ray(30 ether));

        (take, cut) = taxCollector.secondaryTaxReceivers(secondCoinName, "i", 1);
        assertEq(take, 0);
        assertEq(cut, ray(30 ether));

        (take, cut) = taxCollector.secondaryTaxReceivers(coinName, "i", 2);
        assertEq(take, 0);
        assertEq(cut, ray(35 ether));

        (take, cut) = taxCollector.secondaryTaxReceivers(secondCoinName, "i", 2);
        assertEq(take, 0);
        assertEq(cut, ray(35 ether));

        (take, cut) = taxCollector.secondaryTaxReceivers(coinName, "j", 1);
        assertEq(take, 0);
        assertEq(cut, ray(25 ether));

        (take, cut) = taxCollector.secondaryTaxReceivers(secondCoinName, "j", 1);
        assertEq(take, 0);
        assertEq(cut, ray(25 ether));

        (take, cut) = taxCollector.secondaryTaxReceivers(coinName, "j", 2);
        assertEq(take, 0);
        assertEq(cut, ray(33 ether));

        (take, cut) = taxCollector.secondaryTaxReceivers(secondCoinName, "j", 2);
        assertEq(take, 0);
        assertEq(cut, ray(33 ether));
    }
    function test_add_secondaryTaxReceivers_single_collateral_type_toggle_collect_tax_negative() public {
        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1050000000000000000000000000);
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1050000000000000000000000000);

        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(coinName, "i", 1, ray(5 ether), bob);
        taxCollector.modifyParameters(coinName, "i", 2, ray(10 ether), char);
        taxCollector.modifyParameters(coinName, "i", 1, 1);
        taxCollector.modifyParameters(coinName, "i", 2, 1);

        taxCollector.modifyParameters(secondCoinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(5 ether), bob);
        taxCollector.modifyParameters(secondCoinName, "i", 2, ray(10 ether), char);
        taxCollector.modifyParameters(secondCoinName, "i", 1, 1);
        taxCollector.modifyParameters(secondCoinName, "i", 2, 1);

        hevm.warp(now + 5);
        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");

        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 17958301562500000000);
        assertEq(wad(safeEngine.coinBalance(coinName, bob)), 1381407812500000000);
        assertEq(wad(safeEngine.coinBalance(coinName, char)), 2762815625000000000);

        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 17958301562500000000);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, bob)), 1381407812500000000);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, char)), 2762815625000000000);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 900000000000000000000000000);
        taxCollector.modifyParameters(coinName, "i", 1, ray(10 ether), bob);
        taxCollector.modifyParameters(coinName, "i", 2, ray(20 ether), char);

        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 900000000000000000000000000);
        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(10 ether), bob);
        taxCollector.modifyParameters(secondCoinName, "i", 2, ray(20 ether), char);

        hevm.warp(now + 5);
        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");

        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 0);
        assertEq(wad(safeEngine.coinBalance(coinName, bob)), 0);
        assertEq(wad(safeEngine.coinBalance(coinName, char)), 0);

        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 0);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, bob)), 0);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, char)), 0);
    }
    function test_add_secondaryTaxReceivers_multi_collateral_types_toggle_collect_tax_negative() public {
        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1050000000000000000000000000);
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1050000000000000000000000000);

        safeEngine.initializeCollateralType(coinName, "j");
        safeEngine.initializeCollateralType(secondCoinName, "j");

        safeEngine.addCollateralJoin("j", address(this));

        taxCollector.initializeCollateralType(coinName, "j");
        taxCollector.initializeCollateralType(secondCoinName, "j");

        draw(coinName, "j", 100 ether);
        draw(secondCoinName, "j", 100 ether);

        taxCollector.modifyParameters(coinName, "j", "stabilityFee", 1050000000000000000000000000);
        taxCollector.modifyParameters(secondCoinName, "j", "stabilityFee", 1050000000000000000000000000);

        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(coinName, "i", 1, ray(5 ether), bob);
        taxCollector.modifyParameters(coinName, "i", 2, ray(10 ether), char);
        taxCollector.modifyParameters(coinName, "i", 1, 1);
        taxCollector.modifyParameters(coinName, "i", 2, 1);

        taxCollector.modifyParameters(secondCoinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(5 ether), bob);
        taxCollector.modifyParameters(secondCoinName, "i", 2, ray(10 ether), char);
        taxCollector.modifyParameters(secondCoinName, "i", 1, 1);
        taxCollector.modifyParameters(secondCoinName, "i", 2, 1);

        hevm.warp(now + 5);
        taxCollector.taxMany(coinName, 0, taxCollector.collateralListLength(coinName) - 1);
        taxCollector.taxMany(secondCoinName, 0, taxCollector.collateralListLength(secondCoinName) - 1);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 900000000000000000000000000);
        taxCollector.modifyParameters(coinName, "j", "stabilityFee", 900000000000000000000000000);

        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 900000000000000000000000000);
        taxCollector.modifyParameters(secondCoinName, "j", "stabilityFee", 900000000000000000000000000);

        taxCollector.modifyParameters(coinName, "i", 1, ray(10 ether), bob);
        taxCollector.modifyParameters(coinName, "i", 2, ray(20 ether), char);
        taxCollector.modifyParameters(coinName, "j", 1, ray(10 ether), bob);
        taxCollector.modifyParameters(coinName, "j", 2, ray(20 ether), char);

        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(10 ether), bob);
        taxCollector.modifyParameters(secondCoinName, "i", 2, ray(20 ether), char);
        taxCollector.modifyParameters(secondCoinName, "j", 1, ray(10 ether), bob);
        taxCollector.modifyParameters(secondCoinName, "j", 2, ray(20 ether), char);

        hevm.warp(now + 5);
        taxCollector.taxMany(coinName, 0, taxCollector.collateralListLength(coinName) - 1);
        taxCollector.taxMany(coinName, 0, taxCollector.collateralListLength(secondCoinName) - 1);

        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 0);
        assertEq(wad(safeEngine.coinBalance(coinName, bob)), 0);
        assertEq(wad(safeEngine.coinBalance(coinName, char)), 0);

        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 40060826562500000000);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, bob)), 1381407812500000000);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, char)), 2762815625000000000);
    }
    function test_add_secondaryTaxReceivers_no_toggle_collect_tax_negative() public {
        // Setup
        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1050000000000000000000000000);
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1050000000000000000000000000);

        taxCollector.modifyParameters("primaryTaxReceiver", ali);
        taxCollector.modifyParameters(coinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(coinName, "i", 1, ray(5 ether), bob);
        taxCollector.modifyParameters(coinName, "i", 2, ray(10 ether), char);

        taxCollector.modifyParameters(secondCoinName, "maxSecondaryReceivers", 2);
        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(5 ether), bob);
        taxCollector.modifyParameters(secondCoinName, "i", 2, ray(10 ether), char);

        hevm.warp(now + 5);
        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");

        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 17958301562500000000);
        assertEq(wad(safeEngine.coinBalance(coinName, bob)), 1381407812500000000);
        assertEq(wad(safeEngine.coinBalance(coinName, char)), 2762815625000000000);

        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 17958301562500000000);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, bob)), 1381407812500000000);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, char)), 2762815625000000000);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 900000000000000000000000000);
        taxCollector.modifyParameters(coinName, "i", 1, ray(10 ether), bob);
        taxCollector.modifyParameters(coinName, "i", 2, ray(20 ether), char);

        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 900000000000000000000000000);
        taxCollector.modifyParameters(secondCoinName, "i", 1, ray(10 ether), bob);
        taxCollector.modifyParameters(secondCoinName, "i", 2, ray(20 ether), char);

        hevm.warp(now + 5);
        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");

        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 0);
        assertEq(wad(safeEngine.coinBalance(coinName, bob)), 1381407812500000000);
        assertEq(wad(safeEngine.coinBalance(coinName, char)), 2762815625000000000);

        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 0);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, bob)), 1381407812500000000);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, char)), 2762815625000000000);
    }
    function test_collectedManyTax() public {
        safeEngine.initializeCollateralType(coinName, "j");
        safeEngine.initializeCollateralType(secondCoinName, "j");

        safeEngine.addCollateralJoin("j", address(this));

        taxCollector.initializeCollateralType(coinName, "j");
        taxCollector.initializeCollateralType(secondCoinName, "j");

        draw(coinName, "j", 100 ether);
        draw(secondCoinName, "j", 100 ether);

        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1050000000000000000000000000);  // 5% / second
        taxCollector.modifyParameters(coinName, "j", "stabilityFee", 1000000000000000000000000000);  // 0% / second
        taxCollector.modifyParameters(coinName, "globalStabilityFee", uint(50000000000000000000000000));  // 5% / second

        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1050000000000000000000000000);  // 5% / second
        taxCollector.modifyParameters(secondCoinName, "j", "stabilityFee", 1000000000000000000000000000);  // 0% / second
        taxCollector.modifyParameters(secondCoinName, "globalStabilityFee", uint(50000000000000000000000000));  // 5% / second

        hevm.warp(now + 1);
        assertTrue(!taxCollector.collectedManyTax(coinName, 0, 1));
        assertTrue(!taxCollector.collectedManyTax(secondCoinName, 0, 1));

        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");

        assertTrue(taxCollector.collectedManyTax(coinName, 0, 0));
        assertTrue(!taxCollector.collectedManyTax(coinName, 0, 1));

        assertTrue(taxCollector.collectedManyTax(secondCoinName, 0, 0));
        assertTrue(!taxCollector.collectedManyTax(secondCoinName, 0, 1));
    }
    function test_modify_stabilityFee() public {
        hevm.warp(now + 1);
        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");
        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1);
        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1);
    }
    function testFail_modify_stabilityFee() public {
        hevm.warp(now + 1);
        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1);
    }
    function test_taxManyOutcome_all_untaxed_positive_rates() public {
        safeEngine.initializeCollateralType(coinName, "j");
        safeEngine.initializeCollateralType(secondCoinName, "j");

        safeEngine.addCollateralJoin("j", address(this));

        taxCollector.initializeCollateralType(coinName, "j");
        taxCollector.initializeCollateralType(secondCoinName, "j");

        draw(coinName, "i", 100 ether);
        draw(coinName, "j", 100 ether);

        draw(secondCoinName, "i", 100 ether);
        draw(secondCoinName, "j", 100 ether);

        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1050000000000000000000000000);  // 5% / second
        taxCollector.modifyParameters(coinName, "j", "stabilityFee", 1030000000000000000000000000);  // 3% / second
        taxCollector.modifyParameters(coinName, "globalStabilityFee",  uint(50000000000000000000000000));  // 5% / second

        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1050000000000000000000000000);  // 5% / second
        taxCollector.modifyParameters(secondCoinName, "j", "stabilityFee", 1030000000000000000000000000);  // 3% / second
        taxCollector.modifyParameters(secondCoinName, "globalStabilityFee",  uint(50000000000000000000000000));  // 5% / second

        hevm.warp(now + 1);
        (bool ok, int rad) = taxCollector.taxManyOutcome(coinName, 0, 1);
        assertTrue(ok);
        assertEq(uint(rad), 28 * 10 ** 45);

        (ok, rad) = taxCollector.taxManyOutcome(secondCoinName, 0, 1);
        assertTrue(ok);
        assertEq(uint(rad), 28 * 10 ** 45);
    }
    function test_taxManyOutcome_some_untaxed_positive_rates() public {
        safeEngine.initializeCollateralType(coinName, "j");
        safeEngine.initializeCollateralType(secondCoinName, "j");

        safeEngine.addCollateralJoin("j", address(this));

        taxCollector.initializeCollateralType(coinName, "j");
        taxCollector.initializeCollateralType(secondCoinName, "j");

        draw(coinName, "i", 100 ether);
        draw(coinName, "j", 100 ether);

        draw(secondCoinName, "i", 100 ether);
        draw(secondCoinName, "j", 100 ether);

        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 1050000000000000000000000000);  // 5% / second
        taxCollector.modifyParameters(coinName, "j", "stabilityFee", 1030000000000000000000000000);  // 3% / second
        taxCollector.modifyParameters(coinName, "globalStabilityFee",  uint(50000000000000000000000000));  // 5% / second

        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 1050000000000000000000000000);  // 5% / second
        taxCollector.modifyParameters(secondCoinName, "j", "stabilityFee", 1030000000000000000000000000);  // 3% / second
        taxCollector.modifyParameters(secondCoinName, "globalStabilityFee",  uint(50000000000000000000000000));  // 5% / second

        hevm.warp(now + 1);
        taxCollector.taxSingle(coinName, "i");
        taxCollector.taxSingle(secondCoinName, "i");

        (bool ok, int rad) = taxCollector.taxManyOutcome(coinName, 0, 1);
        assertTrue(ok);
        assertEq(uint(rad), 8 * 10 ** 45);

        (ok, rad) = taxCollector.taxManyOutcome(secondCoinName, 0, 1);
        assertTrue(ok);
        assertEq(uint(rad), 8 * 10 ** 45);
    }
    function test_taxManyOutcome_all_untaxed_negative_rates() public {
        safeEngine.initializeCollateralType(coinName, "j");
        safeEngine.initializeCollateralType(secondCoinName, "j");

        safeEngine.addCollateralJoin("j", address(this));

        taxCollector.initializeCollateralType(coinName, "j");
        taxCollector.initializeCollateralType(secondCoinName, "j");

        draw(coinName, "i", 100 ether);
        draw(coinName, "j", 100 ether);

        draw(secondCoinName, "i", 100 ether);
        draw(secondCoinName, "j", 100 ether);

        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 950000000000000000000000000);  // -5% / second
        taxCollector.modifyParameters(coinName, "j", "stabilityFee", 930000000000000000000000000);  // -3% / second

        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 950000000000000000000000000);  // -5% / second
        taxCollector.modifyParameters(secondCoinName, "j", "stabilityFee", 930000000000000000000000000);  // -3% / second

        hevm.warp(now + 1);
        (bool ok, int rad) = taxCollector.taxManyOutcome(coinName, 0, 1);
        assertTrue(!ok);
        assertEq(rad, -17 * 10 ** 45);

        (ok, rad) = taxCollector.taxManyOutcome(secondCoinName, 0, 1);
        assertTrue(!ok);
        assertEq(rad, -17 * 10 ** 45);
    }
    function test_taxManyOutcome_all_untaxed_mixed_rates() public {
        safeEngine.initializeCollateralType(coinName, "j");
        safeEngine.initializeCollateralType(secondCoinName, "j");

        safeEngine.addCollateralJoin("j", address(this));

        taxCollector.initializeCollateralType(coinName, "j");
        taxCollector.initializeCollateralType(secondCoinName, "j");

        draw(coinName, "j", 100 ether);
        draw(secondCoinName, "j", 100 ether);

        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        taxCollector.modifyParameters(coinName, "i", "stabilityFee", 950000000000000000000000000);  // -5% / second
        taxCollector.modifyParameters(coinName, "j", "stabilityFee", 1050000000000000000000000000);  // 5% / second

        taxCollector.modifyParameters(secondCoinName, "i", "stabilityFee", 950000000000000000000000000);  // -5% / second
        taxCollector.modifyParameters(secondCoinName, "j", "stabilityFee", 1050000000000000000000000000);  // 5% / second

        hevm.warp(now + 1);
        (bool ok, int rad) = taxCollector.taxManyOutcome(coinName, 0, 1);
        assertTrue(ok);
        assertEq(rad, 0);

        (ok, rad) = taxCollector.taxManyOutcome(secondCoinName, 0, 1);
        assertTrue(ok);
        assertEq(rad, 0);
    }
    function test_negative_tax_accumulated_goes_negative() public {
        safeEngine.initializeCollateralType(coinName, "j");
        safeEngine.initializeCollateralType(secondCoinName, "j");

        safeEngine.addCollateralJoin("j", address(this));

        taxCollector.initializeCollateralType(coinName, "j");
        taxCollector.initializeCollateralType(secondCoinName, "j");

        taxCollector.modifyParameters("primaryTaxReceiver", ali);

        draw(coinName, "j", 100 ether);
        draw(secondCoinName, "j", 100 ether);

        safeEngine.transferInternalCoins(coinName, address(this), ali, safeEngine.coinBalance(coinName, address(this)));
        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 200 ether);

        safeEngine.transferInternalCoins(secondCoinName, address(this), ali, safeEngine.coinBalance(secondCoinName, address(this)));
        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 200 ether);

        taxCollector.modifyParameters(coinName, "j", "stabilityFee", 999999706969857929985428567);  // -2.5% / day
        taxCollector.modifyParameters(secondCoinName, "j", "stabilityFee", 999999706969857929985428567);  // -2.5% / day

        hevm.warp(now + 3 days);
        taxCollector.taxSingle(coinName, "j");
        taxCollector.taxSingle(secondCoinName, "j");

        assertEq(wad(safeEngine.coinBalance(coinName, ali)), 192.6859375 ether);
        assertEq(wad(safeEngine.coinBalance(secondCoinName, ali)), 192.6859375 ether);

        (, uint accumulatedRate, , , ,) = safeEngine.collateralTypes(coinName, "j");
        assertEq(accumulatedRate, 926859375000000000000022885);

        (, accumulatedRate, , , ,) = safeEngine.collateralTypes(secondCoinName, "j");
        assertEq(accumulatedRate, 926859375000000000000022885);
    }
}
