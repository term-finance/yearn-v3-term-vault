import { providers } from "ethers";
import { calculateMaxSellableRepoTokenAmount, MaxSellableResult } from "./maxSellableRepoToken";
import { fetchMaxSellableData, FetchDataOptions } from "./fetchMaxSellableData";

/**
 * Convenience wrapper that fetches data and calculates maximum sellable amount.
 * This combines fetchMaxSellableData and calculateMaxSellableRepoTokenAmount.
 *
 * @param strategyAddress The address of a Strategy (Strategy.sol) deployment
 * @param repoToken The address of the repoToken to check
 * @param provider The ethers provider to read from
 * @param options Optional block to read at
 * @returns The maximum sellable amount and reason if no amount can be sold
 */
export async function maxSellableRepoTokenAmount(
  strategyAddress: string,
  repoToken: string,
  provider: providers.Provider,
  options: FetchDataOptions = {}
): Promise<MaxSellableResult> {
  // Fetch all required data
  const inputData = await fetchMaxSellableData(strategyAddress, repoToken, provider, options);

  // Calculate maximum sellable amount
  return calculateMaxSellableRepoTokenAmount(inputData);
}
