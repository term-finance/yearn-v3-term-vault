import { ethers } from "ethers";
import { Strategy } from "../../typechain-types/src/Strategy";
import { calculateMaxSellableRepoTokenAmount, MaxSellableResult } from "./maxSellableRepoToken";
import { fetchMaxSellableData, FetchDataOptions } from "./fetchMaxSellableData";

/**
 * Convenience wrapper that fetches data and calculates maximum sellable amount.
 * This combines fetchMaxSellableData and calculateMaxSellableRepoTokenAmount.
 * 
 * @param strategy The Strategy contract instance
 * @param repoToken The address of the repoToken to check
 * @param providerOrSigner The ethers provider or signer
 * @param options Optional configuration for subgraph usage
 * @returns The maximum sellable amount and reason if no amount can be sold
 */
export async function maxSellableRepoTokenAmount(
  strategy: Strategy,
  repoToken: string,
  providerOrSigner: any,
  options?: FetchDataOptions
): Promise<MaxSellableResult> {
  // Fetch all required data
  const inputData = await fetchMaxSellableData(strategy, repoToken, providerOrSigner, options || {});
  
  // Calculate maximum sellable amount
  return calculateMaxSellableRepoTokenAmount(inputData);
}



