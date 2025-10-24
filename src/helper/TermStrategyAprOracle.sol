// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";
import {Strategy} from "../Strategy.sol";
import {ITermRepoToken} from "../interfaces/term/ITermRepoToken.sol";
import {ITermDiscountRateAdapter} from "../interfaces/term/ITermDiscountRateAdapter.sol";

// =============================================================
//                          TYPES
// =============================================================

enum VaultType {
    STRATEGY,
    MULTISTRAT
}

struct VaultMapping {
    address vaultAddress;
    VaultType vaultType;
}

interface IAprOracleGlobal {
    function getWeightedAverageApr(
        address _vault,
        int256 _delta
    ) external view returns (uint256);

    function getStrategyApr(
        address _strategy,
        int256 _debtChange
    ) external view returns (uint256 apr);
}

/**
 * @title TermStrategyAprOracle
 * @dev Oracle contract for providing APR data for Term Strategy
 * @author Term Finance
 */
contract TermStrategyAprOracle is
    AprOracleBase
{

    // =============================================================
    //                          ERRORS
    // =============================================================
    error UnknownUnderlyingVaultAprOracle();
    error ZeroAddress();

    // =============================================================
    //                          EVENTS
    // =============================================================

    event ExternalAprOracleSet(address indexed underlyingVault, address indexed aprOracle);
    event ExternalAprOracleRemoved(address indexed underlyingVault);

    // =============================================================
    //                        STATE VARIABLES
    // =============================================================
    
    IAprOracleGlobal public immutable globalOracle;
    mapping(address => VaultMapping) public idleVaultRemappings;


    // =============================================================
    //                        CONSTRUCTOR
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address admin_, address globalOracle_, address[] memory underlyingVaults_, VaultMapping[] memory vaultMappings_) AprOracleBase("TermStrategyAprOracle", admin_) {
        require(underlyingVaults_.length == vaultMappings_.length, "Mismatched input lengths");
        require(globalOracle_ != address(0), "ZERO ADDRESS");
        globalOracle = IAprOracleGlobal(globalOracle_);
        for (uint256 i = 0; i < underlyingVaults_.length; i++) {
            idleVaultRemappings[underlyingVaults_[i]] = vaultMappings_[i];
        }
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

   function aprAfterDebtChange(
        address _strategy,
        int256 _debtChange
    ) public view override returns (uint256) {
        Strategy termStrategy = Strategy(_strategy);
        
        // Get strategy state fields individually since public struct getter returns tuple
        (
            address assetVault,
            ,  // eventEmitter
            ,  // governorAddress
            ,  // prevTermController
            ,  // currTermController
            ITermDiscountRateAdapter discountRateAdapter,
            ,  // timeToMaturityThreshold
            ,  // requiredReserveRatio
            ,  // discountRateMarkup
               // repoTokenConcentrationLimit
        ) = termStrategy.strategyState();
        
        uint256 totalWeightedApr = _calculateTotalWeightedRepoTokenApr(termStrategy, discountRateAdapter);
        
        uint256 liquidBalanceWeightedApr = _calculateTotalWeightedLiquidBalanceApr(termStrategy, assetVault, _debtChange);

        uint256 totalAssetValue = termStrategy.totalAssetValue();

        // Handle signed debt change safely
        uint256 adjustedAssetValue;
        if (_debtChange >= 0) {
            adjustedAssetValue = totalAssetValue + uint256(_debtChange);
        } else {
            uint256 absDebtChange = uint256(-_debtChange);
            require(totalAssetValue >= absDebtChange, "Asset value insufficient for debt change");
            adjustedAssetValue = totalAssetValue - absDebtChange;
        }

        require(adjustedAssetValue > 0, "Adjusted asset value is zero");
        return (totalWeightedApr + liquidBalanceWeightedApr) / adjustedAssetValue;
    }

    // =============================================================
    //                      INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @dev Calculates the total weighted APR for all repo token holdings
     * @param termStrategy The Term strategy contract
     * @param discountRateAdapter The discount rate adapter from strategy state
     * @return totalWeightedApr The weighted APR based on repo token holdings
     */
    function _calculateTotalWeightedRepoTokenApr(
        Strategy termStrategy,
        ITermDiscountRateAdapter discountRateAdapter
    ) internal view returns (uint256 totalWeightedApr) {
        address[] memory repoTokens = termStrategy.repoTokenHoldings();

        uint256 repoTokenTokenHoldingValue;
        uint256 repoTokenDiscountRate;
        uint256 redemptionTimestamp;
        uint256 repoTokenApr;
        
        for (uint256 i = 0; i < repoTokens.length; i++) {
            repoTokenTokenHoldingValue = termStrategy.getRepoTokenHoldingValue(repoTokens[i]);

            repoTokenDiscountRate = discountRateAdapter.getDiscountRate(repoTokens[i]);

            (redemptionTimestamp, , , ) = ITermRepoToken(repoTokens[i]).config();
            // Calculate the APR for the repo token based on its discount rate and time to maturity
            repoTokenApr =
                (repoTokenDiscountRate * 
                (redemptionTimestamp > block.timestamp
                    ? (redemptionTimestamp - block.timestamp)
                    : 1)) / 360 days;

            totalWeightedApr += repoTokenApr * repoTokenTokenHoldingValue;
        }
    }

    /**
     * @dev Calculates the total weighted APR for liquid balance using external oracle
     * @param termStrategy The Term strategy contract
     * @param strategyUnderlyingVault The asset vault address from strategy state
     * @param _debtChange The debt change parameter to pass to external oracle
     * @return liquidBalanceWeightedApr The weighted APR based on liquid balance
     */
    function _calculateTotalWeightedLiquidBalanceApr(
        Strategy termStrategy,
        address strategyUnderlyingVault,
        int256 _debtChange
    ) internal view returns (uint256 liquidBalanceWeightedApr) {
        uint256 liquidBalance = termStrategy.totalLiquidBalance();

        // Handle signed debt change safely for liquid balance
        uint256 adjustedLiquidBalance;
        if (_debtChange >= 0) {
            adjustedLiquidBalance = liquidBalance + uint256(_debtChange);
        } else {
            uint256 absDebtChange = uint256(-_debtChange);
            require(liquidBalance >= absDebtChange, "Liquid balance insufficient for debt change");
            adjustedLiquidBalance = liquidBalance - absDebtChange;
        }

        // Check if there is an external APR oracle for the underlying asset
        VaultMapping memory vaultMapping = idleVaultRemappings[strategyUnderlyingVault];
        if (vaultMapping.vaultAddress == address(0)) {
            revert UnknownUnderlyingVaultAprOracle();
        }
        uint256 externalApr;
        if (vaultMapping.vaultType == VaultType.MULTISTRAT) {
            externalApr = globalOracle.getWeightedAverageApr(strategyUnderlyingVault, _debtChange);
        } else {
            externalApr = globalOracle.getStrategyApr(strategyUnderlyingVault, _debtChange);
        }
      
        liquidBalanceWeightedApr = (externalApr * adjustedLiquidBalance);
    }

    // =============================================================
    //                      ADMIN FUNCTIONS
    // =============================================================

    /**
     * @dev Batch sets or removes idle vault remappings for underlying vaults
     * @param _underlyingVaults Array of underlying vault addresses
     * @param _vaultMappings Array of corresponding vault mappings (use address(0) in vaultAddress to remove)
     */
    function batchSetIdleVaultRemappings(
        address[] calldata _underlyingVaults,
        VaultMapping[] calldata _vaultMappings
    ) external onlyGovernance {
        require(_underlyingVaults.length == _vaultMappings.length, "Mismatched input lengths");
        
        for (uint256 i = 0; i < _underlyingVaults.length; i++) {
            if (_underlyingVaults[i] == address(0)) revert ZeroAddress();
            
            if (_vaultMappings[i].vaultAddress == address(0)) {
                // Remove mapping
                delete idleVaultRemappings[_underlyingVaults[i]];
                emit ExternalAprOracleRemoved(_underlyingVaults[i]);
            } else {
                // Set mapping
                idleVaultRemappings[_underlyingVaults[i]] = _vaultMappings[i];
                emit ExternalAprOracleSet(_underlyingVaults[i], _vaultMappings[i].vaultAddress);
            }
        }
    }
}
