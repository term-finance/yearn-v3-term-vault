import { BigNumber, Contract, constants, providers } from "ethers";
import { MaxSellableInputData } from "./maxSellableRepoToken";

// Human-readable ABIs for the view functions this helper reads, so it runs without compiling the
// contracts or generating TypeChain bindings. Strategy.sol exposes all of these; TwoWayStrategy.sol
// has no simulateTransaction and an extra strategyState field, so it is not supported.
const STRATEGY_ABI = [
  "function asset() view returns (address)",
  "function strategyState() view returns (address assetVault, address eventEmitter, address governorAddress, address prevTermController, address currTermController, address discountRateAdapter, uint256 timeToMaturityThreshold, uint256 requiredReserveRatio, uint256 discountRateMarkup, uint256 repoTokenConcentrationLimit)",
  "function totalLiquidBalance() view returns (uint256)",
  "function totalAssetValue() view returns (uint256)",
  "function repoTokenBlacklist(address) view returns (bool)",
  "function getRepoTokenHoldingValue(address repoToken) view returns (uint256)",
  "function simulateTransaction(address repoToken, uint256 amount) view returns (uint256 simulatedWeightedMaturity, uint256 simulatedRepoTokenConcentrationRatio, uint256 simulatedLiquidityRatio)",
];

const REPO_TOKEN_ABI = [
  "function config() view returns (uint256 redemptionTimestamp, address purchaseToken, address termRepoServicer, address termRepoCollateralManager)",
  "function redemptionValue() view returns (uint256)",
  "function decimals() view returns (uint8)",
];

const ERC20_ABI = ["function decimals() view returns (uint8)"];

// ITermDiscountRateAdapter also overloads getDiscountRate(termController, repoToken); only the
// single-argument form sellRepoToken uses is declared, which keeps the call unambiguous.
const DISCOUNT_RATE_ADAPTER_ABI = [
  "function getDiscountRate(address repoToken) view returns (uint256)",
  "function repoRedemptionHaircut(address repoToken) view returns (uint256)",
];

interface StrategyStateView {
  discountRateAdapter: string;
  timeToMaturityThreshold: BigNumber;
  requiredReserveRatio: BigNumber;
  discountRateMarkup: BigNumber;
  repoTokenConcentrationLimit: BigNumber;
}

interface SimulationView {
  simulatedWeightedMaturity: BigNumber;
  simulatedRepoTokenConcentrationRatio: BigNumber;
  simulatedLiquidityRatio: BigNumber;
}

interface RepoTokenConfigView {
  redemptionTimestamp: BigNumber;
  purchaseToken: string;
}

export interface FetchDataOptions {
  /**
   * Block to read every value at. Defaults to the latest block. The repoToken's time to maturity
   * is measured from this block's timestamp, matching what the strategy computes at that block.
   */
  blockTag?: providers.BlockTag;
}

/**
 * Fetches all required data for calculating maximum sellable repoToken amount.
 *
 * This function demonstrates how to fetch each required data point from on-chain sources.
 * You can use this as a reference or modify it to use subgraphs, caching, or other optimizations.
 *
 * All reads are pinned to one block so that the values are mutually consistent.
 *
 * @param strategyAddress The address of a Strategy (Strategy.sol) deployment
 * @param repoToken The address of the repoToken to check
 * @param provider The ethers provider to read from
 * @param options Optional block to read at
 * @returns All input data needed for calculateMaxSellableRepoTokenAmount
 */
export async function fetchMaxSellableData(
  strategyAddress: string,
  repoToken: string,
  provider: providers.Provider,
  options: FetchDataOptions = {}
): Promise<MaxSellableInputData> {
  const blockTag = options.blockTag ?? "latest";
  // ethers v5 resolves to null for a block the provider does not have, e.g. above the chain head
  const block: providers.Block | null = await provider.getBlock(blockTag);
  if (!block) {
    throw new Error(`Block not found for blockTag ${String(blockTag)}`);
  }
  const overrides = { blockTag: block.number };

  const strategy = new Contract(strategyAddress, STRATEGY_ABI, provider);
  const repoTokenContract = new Contract(repoToken, REPO_TOKEN_ABI, provider);

  const [
    strategyState,
    liquidBalance,
    totalAssetValue,
    isBlacklisted,
    assetAddress,
    simulation,
    currentRepoTokenValue,
    config,
    redemptionValue,
    repoTokenDecimals,
  ]: [
    StrategyStateView,
    BigNumber,
    BigNumber,
    boolean,
    string,
    SimulationView,
    BigNumber,
    RepoTokenConfigView,
    BigNumber,
    number,
  ] = await Promise.all([
    // Thresholds, ratios, markup and the discount rate adapter address
    strategy.strategyState(overrides),
    // Assets held directly or in the Yearn vault
    strategy.totalLiquidBalance(overrides),
    // Liquid balance plus the present value of repoTokens and pending offers
    strategy.totalAssetValue(overrides),
    strategy.repoTokenBlacklist(repoToken, overrides),
    strategy.asset(overrides),
    // With address(0) and 0 this returns the current weighted maturity and liquidity ratio
    strategy.simulateTransaction(constants.AddressZero, 0, overrides),
    // Present value of this repoToken already held or pending in offers; 0 if none
    strategy.getRepoTokenHoldingValue(repoToken, overrides),
    repoTokenContract.config(overrides),
    // Purchase token value of one whole repoToken, scaled by 1e18
    repoTokenContract.redemptionValue(overrides),
    repoTokenContract.decimals(overrides),
  ]);

  const discountRateAdapter = new Contract(
    strategyState.discountRateAdapter,
    DISCOUNT_RATE_ADAPTER_ABI,
    provider
  );
  const assetContract = new Contract(assetAddress, ERC20_ABI, provider);

  const [discountRate, repoRedemptionHaircut, assetDecimals]: [
    BigNumber,
    BigNumber,
    number,
  ] = await Promise.all([
    // Oracle discount rate, scaled by 1e18; sellRepoToken adds discountRateMarkup to it
    discountRateAdapter.getDiscountRate(repoToken, overrides),
    // Scaled by 1e18; 0 means no haircut
    discountRateAdapter.repoRedemptionHaircut(repoToken, overrides),
    assetContract.decimals(overrides),
  ]);

  const redemptionTimestamp = config.redemptionTimestamp;
  const blockTimestamp = BigNumber.from(block.timestamp);
  const repoTokenTimeToMaturity = redemptionTimestamp.gt(blockTimestamp)
    ? redemptionTimestamp.sub(blockTimestamp)
    : BigNumber.from(0);

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
    purchaseTokenPrecision: BigNumber.from(10).pow(assetDecimals),

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
    // RepoTokenList.validateRepoToken rejects only redemptionTimestamp < block.timestamp
    isMatured: redemptionTimestamp.lt(blockTimestamp),
  };
}

/**
 * OPTIMIZATION NOTES:
 *
 * 1. CACHING: Some values change infrequently and can be cached:
 *    - Strategy state (thresholds, ratios) - changes only on governance updates
 *    - RepoToken config (redemptionTimestamp, redemptionValue) - immutable per repoToken
 *    - Discount rates and haircuts - may change but infrequently
 *    - Asset decimals - immutable
 *    Mixing cached values with fresh ones gives up the single-block consistency above.
 *
 * 2. SUBGRAPHS: For production, consider using subgraphs to reduce RPC calls:
 *    - Strategy state can be indexed
 *    - RepoToken holdings can be aggregated
 *    - Historical data can be queried efficiently
 *
 * 3. FREQUENT UPDATES: These values change frequently and should be fetched fresh:
 *    - liquidBalance - changes on every deposit/withdrawal
 *    - totalAssetValue - changes as repoTokens mature or are added/removed
 *    - simulation data - reflects current portfolio state
 *    - currentRepoTokenValue - changes as holdings change
 *
 * 4. SELL-TIME DRIFT: sellRepoToken first redeems matured repoTokens and settles completed
 *    auction offers, and it executes in a later block than the snapshot, so its values can
 *    differ slightly from these. strategy.simulateTransaction(repoToken, amount) returns the exact
 *    post-sale weighted maturity, which calculateMaxSellableRepoTokenAmount only estimates.
 */
