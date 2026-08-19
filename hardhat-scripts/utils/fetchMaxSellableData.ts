import { BigNumber, ethers } from "ethers";
import { Strategy } from "../../typechain-types/src/Strategy";
import { ITermRepoToken } from "../../typechain-types/src/interfaces/term/ITermRepoToken";
import { MaxSellableInputData } from "./maxSellableRepoToken";

/**
 * Fetches all required data for calculating maximum sellable repoToken amount.
 * 
 * This function demonstrates how to fetch each required data point from on-chain sources.
 * You can use this as a reference or modify it to use subgraphs, caching, or other optimizations.
 * 
 * @param strategy The Strategy contract instance
 * @param repoToken The address of the repoToken to check
 * @param providerOrSigner The ethers provider or signer
 * @returns All input data needed for calculateMaxSellableRepoTokenAmount
 */
export async function fetchMaxSellableData(
  strategy: Strategy,
  repoToken: string,
  providerOrSigner: any
): Promise<MaxSellableInputData> {
  
  // ============================================================================
  // STRATEGY STATE DATA
  // ============================================================================
  
  // Get strategy state (contains thresholds, ratios, and adapter addresses)
  // Source: strategy.strategyState() -> StrategyState struct
  const strategyState = await strategy.strategyState();
  
  // Get current liquid balance (assets available for withdrawal)
  // Source: strategy.totalLiquidBalance() -> uint256
  const liquidBalance = await strategy.totalLiquidBalance();
  
  // Get total asset value (liquid balance + present value of repoTokens)
  // Source: strategy.totalAssetValue() -> uint256
  const totalAssetValue = await strategy.totalAssetValue();
  
  // Check if repoToken is blacklisted
  // Source: strategy.repoTokenBlacklist(repoToken) -> bool
  const isBlacklisted = await strategy.repoTokenBlacklist(repoToken);
  
  // ============================================================================
  // REPOTOKEN DATA
  // ============================================================================
  
  // Get repoToken contract instance
  const repoTokenContract = await ethers.getContractAt(
    "ITermRepoToken",
    repoToken,
    providerOrSigner
  ) as ITermRepoToken;
  
  // Get repoToken config (contains redemptionTimestamp, purchaseToken, etc.)
  // Source: repoToken.config() -> Config struct
  const config = await repoTokenContract.config();
  const redemptionTimestamp = config.redemptionTimestamp;
  
  // Get redemption value (face value at maturity)
  // Source: repoToken.redemptionValue() -> uint256
  const redemptionValue = await repoTokenContract.redemptionValue();
  
  // Get repoToken decimals
  // Source: repoToken.decimals() -> uint8
  const repoTokenDecimals = await repoTokenContract.decimals();
  
  // Calculate time to maturity (current time vs redemption timestamp)
  // Source: block.timestamp (or Date.now() / 1000 for off-chain)
  const currentTime = BigNumber.from(Math.floor(Date.now() / 1000));
  const repoTokenTimeToMaturity = redemptionTimestamp.gt(currentTime)
    ? redemptionTimestamp.sub(currentTime)
    : BigNumber.from(0);
  
  // ============================================================================
  // ASSET DATA
  // ============================================================================
  
  // Get asset address
  // Source: strategy.asset() -> address
  const assetAddress = await strategy.asset();
  
  // Get asset decimals
  // Source: asset.decimals() -> uint8
  const assetContract = await ethers.getContractAt("ERC20", assetAddress, providerOrSigner);
  const assetDecimals = await assetContract.decimals();
  const purchaseTokenPrecision = BigNumber.from(10).pow(assetDecimals);
  
  // ============================================================================
  // DISCOUNT RATE ADAPTER DATA
  // ============================================================================
  
  // Get discount rate adapter (from strategyState)
  const discountRateAdapter = strategyState.discountRateAdapter;
  
  // Get discount rate for this repoToken
  // Source: discountRateAdapter.getDiscountRate(repoToken) -> uint256 (scaled by RATE_PRECISION)
  const discountRate = await discountRateAdapter.getDiscountRate(repoToken);
  
  // Get redemption haircut for this repoToken
  // Source: discountRateAdapter.repoRedemptionHaircut(repoToken) -> uint256 (scaled by RATE_PRECISION)
  const repoRedemptionHaircut = await discountRateAdapter.repoRedemptionHaircut(repoToken);
  
  // ============================================================================
  // SIMULATION DATA (REQUIRED)
  // ============================================================================
  
  // Get current weighted maturity and other metrics by simulating a transaction with no changes
  // Source: strategy.simulateTransaction(address(0), 0) -> (weightedMaturity, concentration, liquidityRatio)
  // 
  // This returns the current state:
  // - simulatedWeightedMaturity: current weighted maturity in seconds
  // - simulatedRepoTokenConcentrationRatio: current concentration (scaled by RATE_PRECISION)
  // - simulatedLiquidityRatio: current liquidity ratio (scaled by RATE_PRECISION)
  const simulation = await strategy.simulateTransaction(ethers.constants.AddressZero, 0);
  
  // ============================================================================
  // EXISTING HOLDINGS DATA
  // ============================================================================
  
  // Get current value of this specific repoToken held by the strategy
  // Source: strategy.getRepoTokenHoldingValue(repoToken) -> uint256
  // Returns 0 if the repoToken is not currently held
  const currentRepoTokenValue = await strategy.getRepoTokenHoldingValue(repoToken);
  
  // ============================================================================
  // ASSEMBLE AND RETURN DATA
  // ============================================================================
  
  return {
    // Strategy state
    liquidBalance,
    totalAssetValue,
    timeToMaturityThreshold: strategyState.timeToMaturityThreshold,
    requiredReserveRatio: strategyState.requiredReserveRatio,
    repoTokenConcentrationLimit: strategyState.repoTokenConcentrationLimit,
    discountRateMarkup: strategyState.discountRateMarkup,
    
    // RepoToken info
    redemptionTimestamp,
    redemptionValue,
    repoTokenDecimals,
    repoTokenTimeToMaturity,
    
    // Discount rate adapter values
    discountRate,
    repoRedemptionHaircut,
    
    // Asset info
    purchaseTokenPrecision,
    
    // Existing holdings
    currentRepoTokenValue,
    
    // Simulation data (required)
    simulationData: {
      simulatedWeightedMaturity: simulation.simulatedWeightedMaturity,
      simulatedRepoTokenConcentrationRatio: simulation.simulatedRepoTokenConcentrationRatio,
      simulatedLiquidityRatio: simulation.simulatedLiquidityRatio,
    },
    
    // Validation flags
    isBlacklisted,
  };
}

/**
 * OPTIMIZATION NOTES:
 * 
 * 1. BATCHING: Many of these calls can be batched using Promise.all() to reduce latency
 * 
 * 2. CACHING: Some values change infrequently and can be cached:
 *    - Strategy state (thresholds, ratios) - changes only on governance updates
 *    - RepoToken config (redemptionTimestamp, redemptionValue) - immutable per repoToken
 *    - Discount rates and haircuts - may change but infrequently
 *    - Asset decimals - immutable
 * 
 * 3. SUBGRAPHS: For production, consider using subgraphs to reduce RPC calls:
 *    - Strategy state can be indexed
 *    - RepoToken holdings can be aggregated
 *    - Historical data can be queried efficiently
 * 
 * 4. FREQUENT UPDATES: These values change frequently and should be fetched fresh:
 *    - liquidBalance - changes on every deposit/withdrawal
 *    - totalAssetValue - changes as repoTokens mature or are added/removed
 *    - simulation data - reflects current portfolio state
 *    - currentRepoTokenValue - changes as holdings change
 * 
 * 5. ESTIMATION: existingAmount is estimated as totalAssetValue - liquidBalance
 *    This is approximate because totalAssetValue uses discounted present values,
 *    while existingAmount should be normalized (face value) amounts.
 *    For exact values, you would need to call getCumulativeRepoTokenData() directly
 *    (which is internal, so not accessible externally).
 */
