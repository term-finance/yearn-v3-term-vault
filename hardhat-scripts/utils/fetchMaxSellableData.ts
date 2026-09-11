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
  "function repoTokenHoldings() view returns (address[])",
  "function calculateRepoTokenPresentValue(address repoToken, uint256 discountRate, uint256 amount) view returns (uint256)",
  "function simulateTransaction(address repoToken, uint256 amount) view returns (uint256 simulatedWeightedMaturity, uint256 simulatedRepoTokenConcentrationRatio, uint256 simulatedLiquidityRatio)",
];

const REPO_TOKEN_ABI = [
  "function config() view returns (uint256 redemptionTimestamp, address purchaseToken, address termRepoServicer, address termRepoCollateralManager)",
  "function redemptionValue() view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function balanceOf(address account) view returns (uint256)",
];

const ERC20_ABI = ["function decimals() view returns (uint8)"];

// getDiscountRate is overloaded, so it is called by full signature: sellRepoToken prices with the
// single-argument form, while getRepoTokenHoldingValue values listed balances with the
// (termController, repoToken) form.
const DISCOUNT_RATE_ADAPTER_ABI = [
  "function getDiscountRate(address repoToken) view returns (uint256)",
  "function getDiscountRate(address termController, address repoToken) view returns (uint256)",
  "function repoRedemptionHaircut(address repoToken) view returns (uint256)",
];

const TERM_CONTROLLER_ABI = ["function isTermDeployed(address termContract) view returns (bool)"];

interface StrategyStateView {
  prevTermController: string;
  currTermController: string;
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
   * Mined block to read every value at, as a number, hash or tag such as "latest" (the default)
   * or "finalized". It is resolved to one block, and the repoToken's time to maturity is measured
   * from that block's timestamp, matching what the strategy computes at that block.
   */
  blockTag?: providers.BlockTag;
}

/**
 * Fetches all required data for calculating maximum sellable repoToken amount.
 *
 * This function demonstrates how to fetch each required data point from on-chain sources.
 * You can use this as a reference or modify it to use subgraphs, caching, or other optimizations.
 *
 * All reads are pinned to one block so that the values are mutually consistent. Contract calls
 * can only name that block by number, so the block's hash is checked again after the reads and a
 * reorganization in between raises an error instead of mixing two blocks.
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
  // ethers v5 resolves to null for a block the provider does not have, e.g. above the chain head;
  // a pending block has no hash to pin to
  const block: providers.Block | null = await provider.getBlock(blockTag);
  if (!block || block.number == null || !block.hash) {
    throw new Error(`No mined block found for blockTag ${String(blockTag)}`);
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
    strategyRepoTokenBalance,
    repoTokenHoldings,
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
    BigNumber,
    string[],
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
    repoTokenContract.balanceOf(strategyAddress, overrides),
    // RepoTokens the strategy lists and therefore counts in its valuations
    strategy.repoTokenHoldings(overrides),
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
    discountRateAdapter["getDiscountRate(address)"](repoToken, overrides),
    // Scaled by 1e18; 0 means no haircut
    discountRateAdapter.repoRedemptionHaircut(repoToken, overrides),
    assetContract.decimals(overrides),
  ]);

  const isListed = repoTokenHoldings.some(
    (holding) => holding.toLowerCase() === repoToken.toLowerCase()
  );
  // getRepoTokenHoldingValue adds the value of any auction offer for this repoToken to the present
  // value of the listed balance; recomputing the latter the same way isolates the offer.
  let listedBalanceValue = BigNumber.from(0);
  if (isListed) {
    const termController = await findTermController(strategyState, repoToken, provider, overrides);
    listedBalanceValue = await strategy.calculateRepoTokenPresentValue(
      repoToken,
      await discountRateAdapter["getDiscountRate(address,address)"](
        termController,
        repoToken,
        overrides
      ),
      strategyRepoTokenBalance,
      overrides
    );
  }

  // sellRepoToken first redeems every listed repoToken at or past its redemption timestamp, which
  // can move the liquid balance and total asset value this snapshot reads.
  const blockTimestamp = BigNumber.from(block.timestamp);
  const hasMaturedHoldings = (
    await Promise.all(
      repoTokenHoldings
        .filter((holding) => holding.toLowerCase() !== repoToken.toLowerCase())
        .map(async (holding) => {
          const token = new Contract(holding, REPO_TOKEN_ABI, provider);
          const [holdingConfig, balance]: [RepoTokenConfigView, BigNumber] = await Promise.all([
            token.config(overrides),
            token.balanceOf(strategyAddress, overrides),
          ]);
          return holdingConfig.redemptionTimestamp.lte(blockTimestamp) && balance.gt(0);
        })
    )
  ).some((matured) => matured);

  const blockAfterReads: providers.Block | null = await provider.getBlock(block.number);
  if (!blockAfterReads || blockAfterReads.hash !== block.hash) {
    throw new Error(`Block ${block.number} was reorganized while reading; retry`);
  }

  const redemptionTimestamp = config.redemptionTimestamp;
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
    repoTokenBalance: strategyRepoTokenBalance,

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
    hasUntrackedBalance: strategyRepoTokenBalance.gt(0) && !isListed,
    hasPendingOffer: currentRepoTokenValue.gt(listedBalanceValue),
    hasMaturedHoldings,
  };
}

/**
 * The term controller getRepoTokenHoldingValue prices a listed repoToken with: the current
 * controller if it deployed the repoToken, else the previous one, else address(0).
 */
async function findTermController(
  strategyState: StrategyStateView,
  repoToken: string,
  provider: providers.Provider,
  overrides: { blockTag: number }
): Promise<string> {
  for (const controller of [strategyState.currTermController, strategyState.prevTermController]) {
    if (
      controller !== constants.AddressZero &&
      (await new Contract(controller, TERM_CONTROLLER_ABI, provider).isTermDeployed(
        repoToken,
        overrides
      ))
    ) {
      return controller;
    }
  }
  return constants.AddressZero;
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
 *    differ slightly from these. While matured holdings await redemption the calculator declines
 *    to size (hasMaturedHoldings); calling the permissionless strategy.auctionClosed() runs that
 *    cleanup. strategy.simulateTransaction(repoToken, amount) returns the exact post-sale weighted
 *    maturity, which calculateMaxSellableRepoTokenAmount only estimates.
 */
