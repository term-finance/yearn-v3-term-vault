import { ethers } from "hardhat";
import "@nomiclabs/hardhat-ethers";
import { SaleEvaluation } from "./maxSellableRepoToken";
import { maxSellableRepoTokenAmount } from "./maxSellableRepoTokenWrapper";

/**
 * Example usage of maxSellableRepoTokenAmount
 *
 * The helpers only read on-chain state and need no compiled artifacts, so the Solidity compile
 * can be skipped. hardhat.config.ts reads remappings.txt, which `forge remappings > remappings.txt`
 * creates.
 *
 *   STRATEGY_ADDRESS=0x... REPOTOKEN_ADDRESS=0x... \
 *     npx hardhat run --no-compile --network mainnet hardhat-scripts/utils/example-maxSellable.ts
 */
async function main() {
  // Replace with your actual strategy address
  const strategyAddress = process.env.STRATEGY_ADDRESS || "";
  if (!strategyAddress) {
    throw new Error("STRATEGY_ADDRESS environment variable not set");
  }

  // Replace with the repoToken address you want to check
  const repoTokenAddress = process.env.REPOTOKEN_ADDRESS || "";
  if (!repoTokenAddress) {
    throw new Error("REPOTOKEN_ADDRESS environment variable not set");
  }

  console.log(`Checking maximum sellable amount for repoToken: ${repoTokenAddress}`);
  console.log(`Strategy: ${strategyAddress}`);

  // Calculate maximum sellable amount
  const result = await maxSellableRepoTokenAmount(
    strategyAddress,
    repoTokenAddress,
    ethers.provider
  );

  if (result.maxAmount.gt(0)) {
    console.log(`\n✅ Maximum sellable amount: ${result.maxAmount.toString()}`);
    console.log(`Limited by: ${result.limitingConstraint}`);
    if (result.minAmount) {
      console.log(
        `Minimum sellable amount (strategy is above its time-to-maturity threshold): ${result.minAmount.toString()}`
      );
    }
    if (result.constraints) {
      console.log("\nStrategy state after selling the maximum amount:");
      printSaleEvaluation(result.constraints);
    }
  } else {
    console.log(`\n❌ Cannot sell any amount`);
    console.log(`Reason: ${result.reason || "Unknown"}`);
    if (result.constraints) {
      console.log("\nCurrent strategy state:");
      printSaleEvaluation(result.constraints);
    }
  }
}

function printSaleEvaluation(state: SaleEvaluation) {
  console.log(`  Proceeds: ${state.proceeds.toString()}`);
  console.log(`  Liquid Balance Before: ${state.liquidBalanceBefore.toString()}`);
  console.log(`  Liquid Balance After: ${state.liquidBalanceAfter.toString()}`);
  console.log(`  Total Asset Value Before: ${state.totalAssetValueBefore.toString()}`);
  console.log(
    `  Weighted Time to Maturity After (upper estimate): ${state.weightedTimeToMaturityAfter.toString()}`
  );
  console.log(`  Time to Maturity Threshold: ${state.timeToMaturityThreshold.toString()}`);
  console.log(`  Liquid Reserve Ratio After: ${state.liquidReserveRatioAfter.toString()}`);
  console.log(`  Required Reserve Ratio: ${state.requiredReserveRatio.toString()}`);
  console.log(`  RepoToken Concentration After: ${state.repoTokenConcentrationAfter.toString()}`);
  console.log(`  RepoToken Concentration Limit: ${state.repoTokenConcentrationLimit.toString()}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
