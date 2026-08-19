import { ethers } from "hardhat";
import { Strategy } from "../../typechain-types/src/Strategy";
import { maxSellableRepoTokenAmount } from "./maxSellableRepoTokenWrapper";

/**
 * Example usage of maxSellableRepoTokenAmount
 */
async function main() {
  // Get signer
  const [signer] = await ethers.getSigners();

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

  // Get Strategy contract instance
  const strategy = (await ethers.getContractAt(
    "Strategy",
    strategyAddress,
    signer
  )) as Strategy;

  console.log(`Checking maximum sellable amount for repoToken: ${repoTokenAddress}`);
  console.log(`Strategy: ${strategyAddress}`);

  // Calculate maximum sellable amount
  const result = await maxSellableRepoTokenAmount(
    strategy,
    repoTokenAddress,
    signer
  );

  if (result.maxAmount.gt(0)) {
    console.log(`\n✅ Maximum sellable amount: ${result.maxAmount.toString()}`);
    if (result.constraints) {
      console.log("\nConstraints after selling maximum amount:");
      console.log(`  Liquid Balance: ${result.constraints.liquidBalance.toString()}`);
      console.log(`  Total Asset Value: ${result.constraints.totalAssetValue.toString()}`);
      console.log(`  Proceeds: ${result.constraints.proceeds.toString()}`);
      console.log(`  Time to Maturity: ${result.constraints.timeToMaturity.toString()}`);
      console.log(`  Time to Maturity Threshold: ${result.constraints.timeToMaturityThreshold.toString()}`);
      console.log(`  Liquid Reserve Ratio: ${result.constraints.liquidReserveRatio.toString()}`);
      console.log(`  Required Reserve Ratio: ${result.constraints.requiredReserveRatio.toString()}`);
      console.log(`  RepoToken Concentration: ${result.constraints.repoTokenConcentration.toString()}`);
      console.log(`  RepoToken Concentration Limit: ${result.constraints.repoTokenConcentrationLimit.toString()}`);
    }
  } else {
    console.log(`\n❌ Cannot sell any amount`);
    console.log(`Reason: ${result.reason || "Unknown"}`);
    if (result.constraints) {
      console.log("\nCurrent constraints:");
      console.log(`  Liquid Balance: ${result.constraints.liquidBalance.toString()}`);
      console.log(`  Total Asset Value: ${result.constraints.totalAssetValue.toString()}`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

