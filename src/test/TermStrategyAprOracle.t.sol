// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {TermStrategyAprOracle, VaultMapping, VaultType} from "../helper/TermStrategyAprOracle.sol";
import {MockAprOracle} from "./mocks/MockAprOracle.sol";
import {MockGlobalOracle} from "./mocks/MockGlobalOracle.sol";
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
    MockGlobalOracle public globalOracle;
    MockStrategy public strategy;
    MockDiscountRateAdapter public discountRateAdapter;
    MockTermRepoToken public repoToken1;
    MockTermRepoToken public repoToken2;
    MockUSDC public purchaseToken;

    address public admin = address(1);
    address public underlyingVault = address(2);
    address public mappedVault = address(4);
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

        // Deploy global oracle
        globalOracle = new MockGlobalOracle();
        globalOracle.setMockApr(underlyingVault, 500); // 5% APR

        // Deploy TermStrategyAprOracle
        address[] memory vaults = new address[](1);
        VaultMapping[] memory mappings = new VaultMapping[](1);
        vaults[0] = underlyingVault;
        mappings[0] = VaultMapping({
            vaultAddress: mappedVault,
            vaultType: VaultType.STRATEGY
        });

        oracle = new TermStrategyAprOracle(admin, address(globalOracle), vaults, mappings);

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
        VaultMapping[] memory mappings = new VaultMapping[](2);
        vaults[0] = address(0x100);
        vaults[1] = address(0x200);
        mappings[0] = VaultMapping({
            vaultAddress: address(0x300),
            vaultType: VaultType.STRATEGY
        });
        mappings[1] = VaultMapping({
            vaultAddress: address(0x400),
            vaultType: VaultType.MULTISTRAT
        });

        TermStrategyAprOracle newOracle = new TermStrategyAprOracle(admin, address(globalOracle), vaults, mappings);

        // Verify mappings are set correctly
        (address mappedVault0, VaultType vaultType0) = newOracle.idleVaultRemappings(vaults[0]);
        (address mappedVault1, VaultType vaultType1) = newOracle.idleVaultRemappings(vaults[1]);
        assertEq(mappedVault0, mappings[0].vaultAddress);
        assertEq(uint256(vaultType0), uint256(mappings[0].vaultType));
        assertEq(mappedVault1, mappings[1].vaultAddress);
        assertEq(uint256(vaultType1), uint256(mappings[1].vaultType));
        assertEq(newOracle.name(), "TermStrategyAprOracle");
    }

    function test_constructor_mismatchedInputLengths() public {
        address[] memory vaults = new address[](2);
        VaultMapping[] memory mappings = new VaultMapping[](1);
        vaults[0] = address(0x100);
        vaults[1] = address(0x200);
        mappings[0] = VaultMapping({
            vaultAddress: address(0x300),
            vaultType: VaultType.STRATEGY
        });

        vm.expectRevert("Mismatched input lengths");
        new TermStrategyAprOracle(admin, address(globalOracle), vaults, mappings);
    }

    function test_constructor_emptyArrays() public {
        address[] memory vaults = new address[](0);
        VaultMapping[] memory mappings = new VaultMapping[](0);

        TermStrategyAprOracle newOracle = new TermStrategyAprOracle(admin, address(globalOracle), vaults, mappings);
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

        // Global oracle returns 500 (5% APR) for the underlying vault
        globalOracle.setMockApr(underlyingVault, 500);

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

        globalOracle.setMockApr(underlyingVault, 500);

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

        globalOracle.setMockApr(underlyingVault, 500);

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

        globalOracle.setMockApr(underlyingVault, 500); // 5% for liquid balance

        // Calculate expected APR
        // Repo token 1: discountRate = 1000 (APR directly from adapter)
        uint256 repoApr1 = 1000;
        uint256 weightedRepoApr1 = repoApr1 * 300e18;

        // Repo token 2: discountRate = 800 (APR directly from adapter)
        uint256 repoApr2 = 800;
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

        globalOracle.setMockApr(underlyingVault, 600); // 6%

        int256 debtChange = 300e18;

        // Repo token weighted APR doesn't change with debt change
        uint256 repoApr1 = 1200; // APR directly from adapter
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
        // Use vm.warp to set block.timestamp to a known value first
        vm.warp(100 days);
        
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

        globalOracle.setMockApr(underlyingVault, 500);

        // For matured repo token, APR comes directly from discount rate adapter
        uint256 repoApr = 1000; // APR directly from adapter
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

        // When there are no repo tokens, liquid balance check happens first
        vm.expectRevert("Liquid balance insufficient for debt change");
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
                    BATCH SET IDLE VAULT REMAPPINGS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_batchSetIdleVaultRemappings_success() public {
        address[] memory vaults = new address[](2);
        VaultMapping[] memory mappings = new VaultMapping[](2);
        vaults[0] = address(0x100);
        vaults[1] = address(0x200);
        mappings[0] = VaultMapping({
            vaultAddress: address(0x300),
            vaultType: VaultType.STRATEGY
        });
        mappings[1] = VaultMapping({
            vaultAddress: address(0x400),
            vaultType: VaultType.MULTISTRAT
        });

        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit ExternalAprOracleSet(vaults[0], mappings[0].vaultAddress);
        vm.expectEmit(true, true, false, false);
        emit ExternalAprOracleSet(vaults[1], mappings[1].vaultAddress);
        oracle.batchSetIdleVaultRemappings(vaults, mappings);

        (address mappedVault0, VaultType vaultType0) = oracle.idleVaultRemappings(vaults[0]);
        (address mappedVault1, VaultType vaultType1) = oracle.idleVaultRemappings(vaults[1]);
        assertEq(mappedVault0, mappings[0].vaultAddress);
        assertEq(uint256(vaultType0), uint256(mappings[0].vaultType));
        assertEq(mappedVault1, mappings[1].vaultAddress);
        assertEq(uint256(vaultType1), uint256(mappings[1].vaultType));
    }

    function test_batchSetIdleVaultRemappings_removeMapping() public {
        // First set a mapping
        address[] memory vaults = new address[](1);
        VaultMapping[] memory mappings = new VaultMapping[](1);
        vaults[0] = address(0x100);
        mappings[0] = VaultMapping({
            vaultAddress: address(0x300),
            vaultType: VaultType.STRATEGY
        });

        vm.prank(admin);
        oracle.batchSetIdleVaultRemappings(vaults, mappings);
        (address mappedVault, ) = oracle.idleVaultRemappings(vaults[0]);
        assertEq(mappedVault, mappings[0].vaultAddress);

        // Now remove it by setting vaultAddress to address(0)
        mappings[0].vaultAddress = address(0);
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit ExternalAprOracleRemoved(vaults[0]);
        oracle.batchSetIdleVaultRemappings(vaults, mappings);

        (address removedMappedVault, ) = oracle.idleVaultRemappings(vaults[0]);
        assertEq(removedMappedVault, address(0));
    }

    function test_batchSetIdleVaultRemappings_zeroAddressVault() public {
        address[] memory vaults = new address[](1);
        VaultMapping[] memory mappings = new VaultMapping[](1);
        vaults[0] = address(0);
        mappings[0] = VaultMapping({
            vaultAddress: address(0x300),
            vaultType: VaultType.STRATEGY
        });

        vm.prank(admin);
        vm.expectRevert(TermStrategyAprOracle.ZeroAddress.selector);
        oracle.batchSetIdleVaultRemappings(vaults, mappings);
    }

    function test_batchSetIdleVaultRemappings_mismatchedLengths() public {
        address[] memory vaults = new address[](2);
        VaultMapping[] memory mappings = new VaultMapping[](1);
        vaults[0] = address(0x100);
        vaults[1] = address(0x200);
        mappings[0] = VaultMapping({
            vaultAddress: address(0x300),
            vaultType: VaultType.STRATEGY
        });

        vm.prank(admin);
        vm.expectRevert("Mismatched input lengths");
        oracle.batchSetIdleVaultRemappings(vaults, mappings);
    }

    function test_batchSetIdleVaultRemappings_onlyGovernance() public {
        address[] memory vaults = new address[](1);
        VaultMapping[] memory mappings = new VaultMapping[](1);
        vaults[0] = address(0x100);
        mappings[0] = VaultMapping({
            vaultAddress: address(0x300),
            vaultType: VaultType.STRATEGY
        });

        // Try to call from non-governance address
        vm.prank(user);
        vm.expectRevert("!governance");
        oracle.batchSetIdleVaultRemappings(vaults, mappings);
    }

    function test_batchSetIdleVaultRemappings_updateExistingMapping() public {
        address[] memory vaults = new address[](1);
        VaultMapping[] memory mappings = new VaultMapping[](1);
        vaults[0] = underlyingVault; // Already set in setUp
        mappings[0] = VaultMapping({
            vaultAddress: address(0x999),
            vaultType: VaultType.MULTISTRAT
        });

        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit ExternalAprOracleSet(vaults[0], mappings[0].vaultAddress);
        oracle.batchSetIdleVaultRemappings(vaults, mappings);

        (address mappedVault, VaultType vaultType) = oracle.idleVaultRemappings(vaults[0]);
        assertEq(mappedVault, mappings[0].vaultAddress);
        assertEq(uint256(vaultType), uint256(mappings[0].vaultType));
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
        globalOracle.setMockApr(underlyingVault, 800); // 8%

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

        // Note: The oracle calls getStrategyApr with the underlyingVault address
        globalOracle.setMockApr(underlyingVault, 1000); // 10% APR

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

        globalOracle.setMockApr(underlyingVault, 500);

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

        globalOracle.setMockApr(underlyingVault, 500);

        uint256 apr = oracle.aprAfterDebtChange(address(strategy), -int256(uint256(debtChange)));
        assertEq(apr, 500, "APR should always be 500 for uniform rate");
    }
}
