// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {TermStrategyAprOracle} from "../helper/TermStrategyAprOracle.sol";
import {MockAprOracle} from "./mocks/MockAprOracle.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";
import {MockDiscountRateAdapter} from "./mocks/MockDiscountRateAdapter.sol";
import {MockTermRepoToken} from "./mocks/MockTermRepoToken.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

/**
 * @title TermStrategyAprOracleTest
 * @notice Comprehensive unit tests for TermStrategyAprOracle contract
 */
contract TermStrategyAprOracleTest is Test {
    TermStrategyAprOracle public oracle;
    MockAprOracle public externalOracle;
    MockStrategy public strategy;
    MockDiscountRateAdapter public discountRateAdapter;
    MockTermRepoToken public repoToken1;
    MockTermRepoToken public repoToken2;
    MockUSDC public purchaseToken;

    address public admin = address(1);
    address public underlyingVault = address(2);
    address public user = address(3);

    uint256 public constant SECONDS_PER_YEAR = 360 days;
    uint256 public constant BASIS_POINTS = 10000;

    event ExternalAprOracleSet(address indexed underlyingVault, address indexed aprOracle);
    event ExternalAprOracleRemoved(address indexed underlyingVault);

    function setUp() public {
        // Deploy mock contracts
        purchaseToken = new MockUSDC();
        discountRateAdapter = new MockDiscountRateAdapter();
        strategy = new MockStrategy(underlyingVault, address(discountRateAdapter));

        // Deploy external APR oracle
        externalOracle = new MockAprOracle("ExternalOracle", admin);
        externalOracle.setMockApr(500); // 5% APR

        // Deploy TermStrategyAprOracle
        address[] memory vaults = new address[](1);
        address[] memory oracles = new address[](1);
        vaults[0] = underlyingVault;
        oracles[0] = address(externalOracle);

        oracle = new TermStrategyAprOracle(admin, vaults, oracles);

        // Deploy mock repo tokens with different redemption timestamps
        repoToken1 = new MockTermRepoToken(
            bytes32("REPO1"),
            address(purchaseToken),
            address(0x1), // collateral
            1e18, // maintenance ratio
            block.timestamp + 30 days
        );

        repoToken2 = new MockTermRepoToken(
            bytes32("REPO2"),
            address(purchaseToken),
            address(0x2), // collateral
            1e18, // maintenance ratio
            block.timestamp + 60 days
        );
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_constructor_success() public {
        address[] memory vaults = new address[](2);
        address[] memory oracles = new address[](2);
        vaults[0] = address(0x100);
        vaults[1] = address(0x200);
        oracles[0] = address(0x300);
        oracles[1] = address(0x400);

        TermStrategyAprOracle newOracle = new TermStrategyAprOracle(admin, vaults, oracles);

        // Verify external oracles are set correctly
        assertEq(address(newOracle.externalAprOracles(vaults[0])), oracles[0]);
        assertEq(address(newOracle.externalAprOracles(vaults[1])), oracles[1]);
        assertEq(newOracle.name(), "TermStrategyAprOracle");
    }

    function test_constructor_mismatchedInputLengths() public {
        address[] memory vaults = new address[](2);
        address[] memory oracles = new address[](1);
        vaults[0] = address(0x100);
        vaults[1] = address(0x200);
        oracles[0] = address(0x300);

        vm.expectRevert("Mismatched input lengths");
        new TermStrategyAprOracle(admin, vaults, oracles);
    }

    function test_constructor_emptyArrays() public {
        address[] memory vaults = new address[](0);
        address[] memory oracles = new address[](0);

        TermStrategyAprOracle newOracle = new TermStrategyAprOracle(admin, vaults, oracles);
        assertEq(newOracle.name(), "TermStrategyAprOracle");
    }

    /*//////////////////////////////////////////////////////////////
                    APR AFTER DEBT CHANGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_aprAfterDebtChange_noRepoTokens_positiveDebtChange() public {
        // Setup: Strategy with only liquid balance
        strategy.setTotalAssetValue(1000e18);
        strategy.setTotalLiquidBalance(1000e18);
        
        address[] memory emptyRepoTokens = new address[](0);
        strategy.setRepoTokenHoldings(emptyRepoTokens);

        // External oracle returns 500 (5% APR)
        externalOracle.setMockApr(500);

        // Calculate expected APR with debt change
        int256 debtChange = 200e18;
        uint256 adjustedLiquidBalance = 1000e18 + 200e18; // 1200e18
        uint256 adjustedAssetValue = 1000e18 + 200e18; // 1200e18
        uint256 expectedWeightedApr = 500 * adjustedLiquidBalance; // 500 * 1200e18
        uint256 expectedApr = expectedWeightedApr / adjustedAssetValue; // Should be 500

        uint256 apr = oracle.aprAfterDebtChange(address(strategy), debtChange);
        assertEq(apr, expectedApr, "APR should match expected value");
    }

    function test_aprAfterDebtChange_noRepoTokens_negativeDebtChange() public {
        // Setup: Strategy with liquid balance
        strategy.setTotalAssetValue(1000e18);
        strategy.setTotalLiquidBalance(1000e18);
        
        address[] memory emptyRepoTokens = new address[](0);
        strategy.setRepoTokenHoldings(emptyRepoTokens);

        externalOracle.setMockApr(500);

        int256 debtChange = -200e18;
        uint256 adjustedLiquidBalance = 1000e18 - 200e18; // 800e18
        uint256 adjustedAssetValue = 1000e18 - 200e18; // 800e18
        uint256 expectedWeightedApr = 500 * adjustedLiquidBalance;
        uint256 expectedApr = expectedWeightedApr / adjustedAssetValue; // Should be 500

        uint256 apr = oracle.aprAfterDebtChange(address(strategy), debtChange);
        assertEq(apr, expectedApr, "APR should match expected value");
    }

    function test_aprAfterDebtChange_noRepoTokens_zeroDebtChange() public {
        // Setup: Strategy with only liquid balance
        strategy.setTotalAssetValue(1000e18);
        strategy.setTotalLiquidBalance(1000e18);
        
        address[] memory emptyRepoTokens = new address[](0);
        strategy.setRepoTokenHoldings(emptyRepoTokens);

        externalOracle.setMockApr(500);

        uint256 apr = oracle.aprAfterDebtChange(address(strategy), 0);
        assertEq(apr, 500, "APR should be 500 with no debt change");
    }

    function test_aprAfterDebtChange_withRepoTokens() public {
        // Setup repo tokens
        address[] memory repoTokens = new address[](2);
        repoTokens[0] = address(repoToken1);
        repoTokens[1] = address(repoToken2);
        strategy.setRepoTokenHoldings(repoTokens);

        // Set repo token values
        strategy.setRepoTokenHoldingValue(address(repoToken1), 300e18);
        strategy.setRepoTokenHoldingValue(address(repoToken2), 200e18);

        // Set discount rates (in basis points)
        discountRateAdapter.setDiscountRate(address(repoToken1), 1000); // 10%
        discountRateAdapter.setDiscountRate(address(repoToken2), 800);  // 8%

        // Set liquid balance
        strategy.setTotalLiquidBalance(500e18);
        strategy.setTotalAssetValue(1000e18); // 300 + 200 + 500

        externalOracle.setMockApr(500); // 5% for liquid balance

        // Calculate expected APR
        // Repo token 1: discountRate = 1000, timeToMaturity = 30 days
        uint256 timeToMaturity1 = 30 days;
        uint256 repoApr1 = (1000 * timeToMaturity1) / SECONDS_PER_YEAR;
        uint256 weightedRepoApr1 = repoApr1 * 300e18;

        // Repo token 2: discountRate = 800, timeToMaturity = 60 days  
        uint256 timeToMaturity2 = 60 days;
        uint256 repoApr2 = (800 * timeToMaturity2) / SECONDS_PER_YEAR;
        uint256 weightedRepoApr2 = repoApr2 * 200e18;

        // Liquid balance: externalApr = 500, liquidBalance = 500e18
        uint256 weightedLiquidApr = 500 * 500e18;

        uint256 totalWeightedApr = weightedRepoApr1 + weightedRepoApr2 + weightedLiquidApr;
        uint256 expectedApr = totalWeightedApr / 1000e18;

        uint256 apr = oracle.aprAfterDebtChange(address(strategy), 0);
        assertEq(apr, expectedApr, "APR should include both repo tokens and liquid balance");
    }

    function test_aprAfterDebtChange_withRepoTokens_positiveDebtChange() public {
        // Setup repo tokens
        address[] memory repoTokens = new address[](1);
        repoTokens[0] = address(repoToken1);
        strategy.setRepoTokenHoldings(repoTokens);

        strategy.setRepoTokenHoldingValue(address(repoToken1), 500e18);
        discountRateAdapter.setDiscountRate(address(repoToken1), 1200); // 12%

        strategy.setTotalLiquidBalance(500e18);
        strategy.setTotalAssetValue(1000e18);

        externalOracle.setMockApr(600); // 6%

        int256 debtChange = 300e18;
        
        // Repo token weighted APR doesn't change with debt change
        uint256 timeToMaturity1 = 30 days;
        uint256 repoApr1 = (1200 * timeToMaturity1) / SECONDS_PER_YEAR;
        uint256 weightedRepoApr = repoApr1 * 500e18;

        // Liquid balance increases
        uint256 adjustedLiquidBalance = 500e18 + 300e18; // 800e18
        uint256 weightedLiquidApr = 600 * adjustedLiquidBalance;

        // Asset value increases
        uint256 adjustedAssetValue = 1000e18 + 300e18; // 1300e18

        uint256 totalWeightedApr = weightedRepoApr + weightedLiquidApr;
        uint256 expectedApr = totalWeightedApr / adjustedAssetValue;

        uint256 apr = oracle.aprAfterDebtChange(address(strategy), debtChange);
        assertEq(apr, expectedApr, "APR should reflect debt change");
    }

    function test_aprAfterDebtChange_maturedRepoToken() public {
        // Create a repo token that's already matured
        MockTermRepoToken maturedRepoToken = new MockTermRepoToken(
            bytes32("MATURED"),
            address(purchaseToken),
            address(0x3),
            1e18,
            block.timestamp - 1 days // Already matured
        );

        address[] memory repoTokens = new address[](1);
        repoTokens[0] = address(maturedRepoToken);
        strategy.setRepoTokenHoldings(repoTokens);

        strategy.setRepoTokenHoldingValue(address(maturedRepoToken), 100e18);
        discountRateAdapter.setDiscountRate(address(maturedRepoToken), 1000);

        strategy.setTotalLiquidBalance(900e18);
        strategy.setTotalAssetValue(1000e18);

        externalOracle.setMockApr(500);

        // For matured repo token, timeToMaturity should be treated as 1
        uint256 repoApr = (1000 * 1) / SECONDS_PER_YEAR;
        uint256 weightedRepoApr = repoApr * 100e18;
        uint256 weightedLiquidApr = 500 * 900e18;
        uint256 expectedApr = (weightedRepoApr + weightedLiquidApr) / 1000e18;

        uint256 apr = oracle.aprAfterDebtChange(address(strategy), 0);
        assertEq(apr, expectedApr, "APR calculation should handle matured repo tokens");
    }

    /*//////////////////////////////////////////////////////////////
                        ERROR CONDITION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_aprAfterDebtChange_unknownUnderlyingVaultAprOracle() public {
        // Create strategy with unknown vault
        MockStrategy unknownStrategy = new MockStrategy(address(0x999), address(discountRateAdapter));
        unknownStrategy.setTotalAssetValue(1000e18);
        unknownStrategy.setTotalLiquidBalance(1000e18);
        
        address[] memory emptyRepoTokens = new address[](0);
        unknownStrategy.setRepoTokenHoldings(emptyRepoTokens);

        vm.expectRevert(TermStrategyAprOracle.UnknownUnderlyingVaultAprOracle.selector);
        oracle.aprAfterDebtChange(address(unknownStrategy), 0);
    }

    function test_aprAfterDebtChange_assetValueInsufficientForNegativeDebtChange() public {
        strategy.setTotalAssetValue(100e18);
        strategy.setTotalLiquidBalance(100e18);
        
        address[] memory emptyRepoTokens = new address[](0);
        strategy.setRepoTokenHoldings(emptyRepoTokens);

        int256 debtChange = -200e18; // Trying to reduce more than available

        vm.expectRevert("Asset value insufficient for debt change");
        oracle.aprAfterDebtChange(address(strategy), debtChange);
    }

    function test_aprAfterDebtChange_liquidBalanceInsufficientForNegativeDebtChange() public {
        // Setup with repo tokens and small liquid balance
        address[] memory repoTokens = new address[](1);
        repoTokens[0] = address(repoToken1);
        strategy.setRepoTokenHoldings(repoTokens);
        strategy.setRepoTokenHoldingValue(address(repoToken1), 900e18);
        discountRateAdapter.setDiscountRate(address(repoToken1), 1000);

        strategy.setTotalLiquidBalance(100e18);
        strategy.setTotalAssetValue(1000e18);

        int256 debtChange = -200e18; // Trying to reduce more liquid than available

        vm.expectRevert("Liquid balance insufficient for debt change");
        oracle.aprAfterDebtChange(address(strategy), debtChange);
    }

    /*//////////////////////////////////////////////////////////////
                    BATCH SET EXTERNAL APR ORACLES TESTS
    //////////////////////////////////////////////////////////////*/

    function test_batchSetExternalAprOracles_success() public {
        address[] memory vaults = new address[](2);
        address[] memory oracles = new address[](2);
        vaults[0] = address(0x100);
        vaults[1] = address(0x200);
        oracles[0] = address(0x300);
        oracles[1] = address(0x400);

        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit ExternalAprOracleSet(vaults[0], oracles[0]);
        vm.expectEmit(true, true, false, false);
        emit ExternalAprOracleSet(vaults[1], oracles[1]);
        oracle.batchSetExternalAprOracles(vaults, oracles);

        assertEq(address(oracle.externalAprOracles(vaults[0])), oracles[0]);
        assertEq(address(oracle.externalAprOracles(vaults[1])), oracles[1]);
    }

    function test_batchSetExternalAprOracles_removeOracle() public {
        // First set an oracle
        address[] memory vaults = new address[](1);
        address[] memory oracles = new address[](1);
        vaults[0] = address(0x100);
        oracles[0] = address(0x300);

        vm.prank(admin);
        oracle.batchSetExternalAprOracles(vaults, oracles);
        assertEq(address(oracle.externalAprOracles(vaults[0])), oracles[0]);

        // Now remove it by setting to address(0)
        oracles[0] = address(0);
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit ExternalAprOracleRemoved(vaults[0]);
        oracle.batchSetExternalAprOracles(vaults, oracles);

        assertEq(address(oracle.externalAprOracles(vaults[0])), address(0));
    }

    function test_batchSetExternalAprOracles_zeroAddressVault() public {
        address[] memory vaults = new address[](1);
        address[] memory oracles = new address[](1);
        vaults[0] = address(0);
        oracles[0] = address(0x300);

        vm.prank(admin);
        vm.expectRevert(TermStrategyAprOracle.ZeroAddress.selector);
        oracle.batchSetExternalAprOracles(vaults, oracles);
    }

    function test_batchSetExternalAprOracles_mismatchedLengths() public {
        address[] memory vaults = new address[](2);
        address[] memory oracles = new address[](1);
        vaults[0] = address(0x100);
        vaults[1] = address(0x200);
        oracles[0] = address(0x300);

        vm.prank(admin);
        vm.expectRevert("Mismatched input lengths");
        oracle.batchSetExternalAprOracles(vaults, oracles);
    }

    function test_batchSetExternalAprOracles_onlyGovernance() public {
        address[] memory vaults = new address[](1);
        address[] memory oracles = new address[](1);
        vaults[0] = address(0x100);
        oracles[0] = address(0x300);

        // Try to call from non-governance address
        vm.prank(user);
        vm.expectRevert("!governance");
        oracle.batchSetExternalAprOracles(vaults, oracles);
    }

    function test_batchSetExternalAprOracles_updateExistingOracle() public {
        address[] memory vaults = new address[](1);
        address[] memory oracles = new address[](1);
        vaults[0] = underlyingVault; // Already set in setUp
        oracles[0] = address(0x999); // New oracle

        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit ExternalAprOracleSet(vaults[0], oracles[0]);
        oracle.batchSetExternalAprOracles(vaults, oracles);

        assertEq(address(oracle.externalAprOracles(vaults[0])), oracles[0]);
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_integration_fullScenario() public {
        // Setup a realistic scenario with multiple repo tokens and liquid balance
        address[] memory repoTokens = new address[](2);
        repoTokens[0] = address(repoToken1);
        repoTokens[1] = address(repoToken2);
        strategy.setRepoTokenHoldings(repoTokens);

        // Repo token holdings: 40% and 30% of portfolio
        strategy.setRepoTokenHoldingValue(address(repoToken1), 400e18);
        strategy.setRepoTokenHoldingValue(address(repoToken2), 300e18);
        
        // Discount rates
        discountRateAdapter.setDiscountRate(address(repoToken1), 1500); // 15%
        discountRateAdapter.setDiscountRate(address(repoToken2), 1200); // 12%

        // Liquid balance: 30% of portfolio
        strategy.setTotalLiquidBalance(300e18);
        strategy.setTotalAssetValue(1000e18);

        // External oracle APR for liquid balance
        externalOracle.setMockApr(800); // 8%

        // Calculate APR
        uint256 apr = oracle.aprAfterDebtChange(address(strategy), 0);
        
        // Verify APR is reasonable (should be weighted average)
        assertGt(apr, 0, "APR should be greater than 0");
        assertLt(apr, 1500, "APR should be less than max discount rate");
    }

    function test_integration_debtChangeAffectsApr() public {
        // Simple scenario to verify debt change affects APR
        strategy.setTotalAssetValue(1000e18);
        strategy.setTotalLiquidBalance(1000e18);
        
        address[] memory emptyRepoTokens = new address[](0);
        strategy.setRepoTokenHoldings(emptyRepoTokens);

        externalOracle.setMockApr(1000); // 10% APR

        uint256 aprBefore = oracle.aprAfterDebtChange(address(strategy), 0);
        assertEq(aprBefore, 1000, "APR without debt change should be 1000");

        // With debt change, the APR should still be 1000 because the weighted average
        // of the same rate applied to all assets is still the same rate
        uint256 aprAfter = oracle.aprAfterDebtChange(address(strategy), 500e18);
        assertEq(aprAfter, 1000, "APR should remain constant when all assets have same rate");
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_aprAfterDebtChange_positiveDebtChange(
        uint128 totalAssets,
        uint128 debtChange
    ) public {
        vm.assume(totalAssets > 1e18 && totalAssets < 1e30);
        vm.assume(debtChange > 0 && debtChange < 1e30);

        strategy.setTotalAssetValue(totalAssets);
        strategy.setTotalLiquidBalance(totalAssets);
        
        address[] memory emptyRepoTokens = new address[](0);
        strategy.setRepoTokenHoldings(emptyRepoTokens);

        externalOracle.setMockApr(500);

        uint256 apr = oracle.aprAfterDebtChange(address(strategy), int256(uint256(debtChange)));
        assertEq(apr, 500, "APR should always be 500 for uniform rate");
    }

    function testFuzz_aprAfterDebtChange_negativeDebtChange(
        uint128 totalAssets,
        uint128 debtChange
    ) public {
        vm.assume(totalAssets > 1e18 && totalAssets < 1e30);
        vm.assume(debtChange > 0 && debtChange < totalAssets);

        strategy.setTotalAssetValue(totalAssets);
        strategy.setTotalLiquidBalance(totalAssets);
        
        address[] memory emptyRepoTokens = new address[](0);
        strategy.setRepoTokenHoldings(emptyRepoTokens);

        externalOracle.setMockApr(500);

        uint256 apr = oracle.aprAfterDebtChange(address(strategy), -int256(uint256(debtChange)));
        assertEq(apr, 500, "APR should always be 500 for uniform rate");
    }
}
