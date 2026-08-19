import { BigNumber } from "ethers";

/**
 * Input data required to calculate maximum sellable repoToken amount
 * 
 * @dev All BigNumber values should be provided in their native units as specified below.
 *      Do NOT scale values unless explicitly noted (e.g., ratios scaled by RATE_PRECISION).
 */
export interface MaxSellableInputData {
  // Strategy state
  /** @dev Units: base asset precision (e.g., wei for ETH, smallest unit for ERC20 tokens) */
  liquidBalance: BigNumber;
  
  /** @dev Units: base asset precision (e.g., wei for ETH, smallest unit for ERC20 tokens) */
  totalAssetValue: BigNumber;
  
  /** @dev Units: seconds (NOT scaled by RATE_PRECISION) - Unix timestamp difference */
  timeToMaturityThreshold: BigNumber;
  
  /** @dev Units: scaled by RATE_PRECISION (1e18) - e.g., 0.1 (10%) = 1e17 */
  requiredReserveRatio: BigNumber;
  
  /** @dev Units: scaled by RATE_PRECISION (1e18) - e.g., 0.25 (25%) = 25e16 */
  repoTokenConcentrationLimit: BigNumber;
  
  /** @dev Units: scaled by RATE_PRECISION (1e18) - e.g., 0.01 (1%) = 1e16 */
  discountRateMarkup: BigNumber;
  
  // RepoToken info
  /** @dev Units: Unix timestamp in seconds */
  redemptionTimestamp: BigNumber;
  
  /** @dev Units: base asset precision (typically 1e18 for standard tokens) */
  redemptionValue: BigNumber;
  
  /** @dev Units: number (not BigNumber) - e.g., 18 for tokens with 18 decimals */
  repoTokenDecimals: number;
  
  /** @dev Units: seconds (NOT scaled) - calculated as redemptionTimestamp - currentTime */
  repoTokenTimeToMaturity: BigNumber;
  
  // Discount rate adapter values
  /** @dev Units: scaled by RATE_PRECISION (1e18) - e.g., 0.05 (5%) = 5e16 */
  discountRate: BigNumber;
  
  /** @dev Units: scaled by RATE_PRECISION (1e18) - e.g., 1.0 (100%) = 1e18, 0.95 (95%) = 95e16 */
  repoRedemptionHaircut: BigNumber;
  
  // Asset info
  /** @dev Units: 10^assetDecimals (e.g., 1e18 for tokens with 18 decimals) */
  purchaseTokenPrecision: BigNumber;
  
  // Existing holdings - will be calculated from simulationData
  // These represent the CURRENT state BEFORE selling the new repoToken
  
  /**
   * @dev Required: Results from calling strategy.simulateTransaction(address(0), 0)
   * 
   * These values are used to calculate existingAmount and existingWeightedTime accurately.
   * 
   * When simulateTransaction is called with address(0) and 0, it returns the current state:
   * - simulatedWeightedMaturity: current weighted maturity in seconds
   * - simulatedRepoTokenConcentrationRatio: current concentration (scaled by RATE_PRECISION)
   * - simulatedLiquidityRatio: current liquidity ratio (scaled by RATE_PRECISION)
   * 
   * From simulatedWeightedMaturity, we can derive:
   * - existingWeightedTime = simulatedWeightedMaturity × (existingAmount + liquidBalance)
   * 
   * Note: We still need existingAmount separately, or it can be estimated from totalAssetValue.
   */
  simulationData: {
    /** @dev Units: seconds - Current weighted maturity from simulateTransaction */
    simulatedWeightedMaturity: BigNumber;
    /** @dev Units: scaled by RATE_PRECISION (1e18) - Current repoToken concentration */
    simulatedRepoTokenConcentrationRatio?: BigNumber;
    /** @dev Units: scaled by RATE_PRECISION (1e18) - Current liquidity ratio */
    simulatedLiquidityRatio?: BigNumber;
  };
  
  /**
   * @dev Units: base asset precision (e.g., wei for ETH, smallest unit for ERC20 tokens)
   * 
   * The current value of the specific repoToken already held by the strategy.
   * This is used for concentration calculations.
   * 
   * If the repoToken is not currently held, this should be 0.
   */
  currentRepoTokenValue?: BigNumber;
  
  // Validation flags
  /** @dev Units: boolean - true if repoToken is blacklisted */
  isBlacklisted: boolean;
}

/**
 * Result of calculating maximum sellable repoToken amount
 */
export interface MaxSellableResult {
  maxAmount: BigNumber;
  reason?: string;
  limitingConstraint?: string;
  constraints?: {
    liquidBalance: BigNumber;
    totalAssetValue: BigNumber;
    proceeds: BigNumber;
    timeToMaturity: BigNumber;
    timeToMaturityThreshold: BigNumber;
    liquidReserveRatio: BigNumber;
    requiredReserveRatio: BigNumber;
    repoTokenConcentration: BigNumber;
    repoTokenConcentrationLimit: BigNumber;
  };
}

/**
 * Calculates the maximum amount of a repoToken that can be sold using analytical solutions
 * for each constraint, then taking the minimum.
 * 
 * This is a pure function that takes all required data as input - no RPC calls.
 * 
 * @param inputData All required input data for the calculation
 * @returns The maximum sellable amount and reason if no amount can be sold
 */
export function calculateMaxSellableRepoTokenAmount(
  inputData: MaxSellableInputData
): MaxSellableResult {
  // Basic validations
  if (inputData.isBlacklisted) {
    return { maxAmount: BigNumber.from(0), reason: "RepoToken is blacklisted" };
  }

  if (inputData.liquidBalance.isZero() || inputData.totalAssetValue.isZero()) {
    return { maxAmount: BigNumber.from(0), reason: "Insufficient liquid balance" };
  }

  if (inputData.repoTokenTimeToMaturity.isZero()) {
    return { maxAmount: BigNumber.from(0), reason: "RepoToken has already matured" };
  }

  const RATE_PRECISION = BigNumber.from(10).pow(18);
  const THREESIXTY_DAYCOUNT_SECONDS = BigNumber.from(360 * 24 * 60 * 60);
  const repoTokenPrecision = BigNumber.from(10).pow(inputData.repoTokenDecimals);

  // Calculate conversion factors
  // Factor 1: repoTokenAmount -> repoTokenAmountInBaseAssetPrecision (normalization_factor)
  const normalizeFactor = inputData.repoRedemptionHaircut.gt(0)
    ? inputData.redemptionValue
        .mul(inputData.repoRedemptionHaircut)
        .mul(inputData.purchaseTokenPrecision)
        .div(repoTokenPrecision.mul(RATE_PRECISION).mul(BigNumber.from(10).pow(18)))
    : inputData.redemptionValue
        .mul(inputData.purchaseTokenPrecision)
        .div(repoTokenPrecision.mul(RATE_PRECISION));

  // Factor 2: repoTokenAmountInBaseAssetPrecision -> proceeds (proceeds_factor)
  const timeLeftToMaturityDayFraction = inputData.repoTokenTimeToMaturity
    .mul(inputData.purchaseTokenPrecision)
    .div(THREESIXTY_DAYCOUNT_SECONDS);
  
  const discountRateWithMarkup = inputData.discountRate.add(inputData.discountRateMarkup);
  const presentValueDenominator = inputData.purchaseTokenPrecision.add(
    discountRateWithMarkup.mul(timeLeftToMaturityDayFraction).div(RATE_PRECISION)
  );
  
  // proceeds = repoTokenAmountInBaseAssetPrecision * purchaseTokenPrecision / presentValueDenominator
  // But capped at repoTokenAmountInBaseAssetPrecision
  const presentValueFactor = inputData.purchaseTokenPrecision
    .mul(inputData.purchaseTokenPrecision)
    .div(presentValueDenominator);
  const effectivePVFactor = presentValueFactor.gt(inputData.purchaseTokenPrecision) 
    ? inputData.purchaseTokenPrecision 
    : presentValueFactor;
  
  // Calculate proceeds per unit of repoTokenAmount
  // proceeds = repoTokenAmount × normalizeFactor × (effectivePVFactor / purchaseTokenPrecision)
  const proceedsPerRepoTokenAmount = normalizeFactor
    .mul(effectivePVFactor)
    .div(inputData.purchaseTokenPrecision);

  // CONSTRAINT 1: Liquid Balance
  // proceeds <= liquidBalance
  // repoTokenAmount × proceedsPerRepoTokenAmount <= liquidBalance
  // repoTokenAmount <= liquidBalance / proceedsPerRepoTokenAmount
  const maxRepoTokenAmountFromLiquidBalance = inputData.liquidBalance
    .mul(repoTokenPrecision)
    .div(proceedsPerRepoTokenAmount);

  // CONSTRAINT 2: Reserve Ratio  
  // (liquidBalance - proceeds) / totalAssetValue >= requiredReserveRatio
  // liquidBalance - proceeds >= totalAssetValue × requiredReserveRatio
  // proceeds <= liquidBalance - totalAssetValue × requiredReserveRatio
  const maxProceedsFromReserve = inputData.liquidBalance.sub(
    inputData.totalAssetValue
      .mul(inputData.requiredReserveRatio)
      .div(RATE_PRECISION)
  );

  if (maxProceedsFromReserve.lte(0)) {
    return {
      maxAmount: BigNumber.from(0),
      reason: "Reserve ratio constraint cannot be satisfied",
      limitingConstraint: "reserveRatio",
      constraints: {
        liquidBalance: inputData.liquidBalance,
        totalAssetValue: inputData.totalAssetValue,
        proceeds: BigNumber.from(0),
        timeToMaturity: BigNumber.from(0),
        timeToMaturityThreshold: inputData.timeToMaturityThreshold,
        liquidReserveRatio: inputData.liquidBalance.mul(RATE_PRECISION).div(inputData.totalAssetValue),
        requiredReserveRatio: inputData.requiredReserveRatio,
        repoTokenConcentration: BigNumber.from(0),
        repoTokenConcentrationLimit: inputData.repoTokenConcentrationLimit,
      },
    };
  }

  const maxRepoTokenAmountFromReserveRatio = maxProceedsFromReserve
    .mul(repoTokenPrecision)
    .div(proceedsPerRepoTokenAmount);

  // CONSTRAINT 3: Time to Maturity (analytical solution)
  // Derive existing values from simulation data (which is required)
  const simulatedWeightedMaturity = inputData.simulationData.simulatedWeightedMaturity;
  
  // Always estimate existingAmount from totalAssetValue
  // NOTE: This is approximate because totalAssetValue uses discounted present values,
  // but existingAmount should be normalized (face value) amounts.
  // Formula: existingAmount ≈ totalAssetValue - liquidBalance
  const existingAmount = inputData.totalAssetValue.sub(inputData.liquidBalance);
  
  // Always derive existingWeightedTime from simulatedWeightedMaturity
  // Formula: simulatedWeightedMaturity = existingWeightedTime / (existingAmount + liquidBalance)
  // So: existingWeightedTime = simulatedWeightedMaturity × (existingAmount + liquidBalance)
  const totalDenominator = existingAmount.add(inputData.liquidBalance);
  const existingWeightedTime = simulatedWeightedMaturity.mul(totalDenominator);
  
  // The constraint after adding new repoToken:
  // (existingWeightedTime + repoTokenTimeToMaturity × newAmount) / 
  // (existingAmount + liquidBalance - proceeds + newAmount) ≤ threshold
  //
  // Where: newAmount = repoTokenAmount × normalizeFactor
  //       proceeds = repoTokenAmount × normalizeFactor × proceedsFactor
  //
  // Simplified denominator: existingAmount + liquidBalance + newAmount - proceeds
  //                         = existingAmount + liquidBalance + repoTokenAmount × (normalizeFactor - proceedsPerRepoTokenAmount)
  //
  // NOTE: threshold is in seconds (not scaled by RATE_PRECISION)
  //       existingWeightedTime is in seconds × baseAssetPrecision
  //       normalizeFactor is in baseAssetPrecision / repoTokenPrecision
  
  const threshold = inputData.timeToMaturityThreshold;
  const netAmountFactor = normalizeFactor.sub(proceedsPerRepoTokenAmount);
  
  // Numerator: existingWeightedTime - threshold × existingAmount - threshold × liquidBalance
  // Units: (seconds × baseAssetPrecision) - (seconds × baseAssetPrecision) - (seconds × baseAssetPrecision)
  //      = seconds × baseAssetPrecision
  const numerator = existingWeightedTime.sub(
    threshold.mul(existingAmount)
  ).sub(
    threshold.mul(inputData.liquidBalance)
  );
  
  // Denominator: threshold × netAmountFactor - repoTokenTimeToMaturity × normalizeFactor
  // Units: (seconds × baseAssetPrecision/repoTokenPrecision) - (seconds × baseAssetPrecision/repoTokenPrecision)
  //      = seconds × baseAssetPrecision/repoTokenPrecision
  const denominator = threshold
    .mul(netAmountFactor)
    .sub(inputData.repoTokenTimeToMaturity.mul(normalizeFactor));
  
  let maxRepoTokenAmountFromMaturity = BigNumber.from(10).pow(30); // Very large default
  
  if (denominator.gt(0) && numerator.gt(0)) {
    maxRepoTokenAmountFromMaturity = numerator.mul(repoTokenPrecision).div(denominator);
  } else if (denominator.lt(0) || numerator.lte(0)) {
    // If denominator is negative or numerator is non-positive, check if constraint can be satisfied
    if (inputData.repoTokenTimeToMaturity.lt(threshold)) {
      // RepoToken maturity is less than threshold, so constraint is less restrictive
      maxRepoTokenAmountFromMaturity = BigNumber.from(10).pow(30);
    } else {
      // RepoToken maturity exceeds threshold, need to check if any amount works
      maxRepoTokenAmountFromMaturity = BigNumber.from(0);
    }
  }

  // CONSTRAINT 4: Concentration
  // (currentRepoTokenValue + newRepoTokenValue) / (totalAssetValue + newRepoTokenValue - proceeds) ≤ limit
  // Simplified: (currentRepoTokenValue + newRepoTokenValue) / totalAssetValue ≤ limit
  // newRepoTokenValue ≤ limit × totalAssetValue - currentRepoTokenValue
  const currentRepoTokenValue = inputData.currentRepoTokenValue || BigNumber.from(0);
  const maxRepoTokenValueFromConcentration = inputData.totalAssetValue
    .mul(inputData.repoTokenConcentrationLimit)
    .div(RATE_PRECISION)
    .sub(currentRepoTokenValue);
  
  const maxRepoTokenAmount4 = maxRepoTokenValueFromConcentration.gt(0)
    ? maxRepoTokenValueFromConcentration.mul(repoTokenPrecision).div(normalizeFactor)
    : BigNumber.from(0);

  // Take the minimum of all constraints
  const candidates = [
    maxRepoTokenAmountFromLiquidBalance,
    maxRepoTokenAmountFromReserveRatio,
    maxRepoTokenAmountFromMaturity,
    maxRepoTokenAmount4,
  ].filter(amount => amount.gt(0));

  if (candidates.length === 0) {
    return {
      maxAmount: BigNumber.from(0),
      reason: "All constraints result in zero or negative amounts",
    };
  }

  const minAmount = BigNumber.min(...candidates);

  return {
    maxAmount: minAmount,
    constraints: {
      liquidBalance: inputData.liquidBalance,
      totalAssetValue: inputData.totalAssetValue,
      proceeds: minAmount.mul(proceedsPerRepoTokenAmount).div(repoTokenPrecision),
      timeToMaturity: BigNumber.from(0), // Would need simulation to get exact value
      timeToMaturityThreshold: inputData.timeToMaturityThreshold,
      liquidReserveRatio: BigNumber.from(0), // Would need simulation to get exact value
      requiredReserveRatio: inputData.requiredReserveRatio,
      repoTokenConcentration: BigNumber.from(0), // Would need simulation to get exact value
      repoTokenConcentrationLimit: inputData.repoTokenConcentrationLimit,
    },
  };
}
