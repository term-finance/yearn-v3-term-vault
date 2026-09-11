import { BigNumber } from "ethers";

const RATE_PRECISION = BigNumber.from(10).pow(18);
const THREESIXTY_DAYCOUNT_SECONDS = BigNumber.from(360 * 24 * 60 * 60);
const ZERO = BigNumber.from(0);
const ONE = BigNumber.from(1);

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

  /** @dev Units: scaled by RATE_PRECISION (1e18) - purchase token value of one whole repoToken, e.g., 1e18 = 1:1 */
  redemptionValue: BigNumber;

  /** @dev Units: number (not BigNumber) - e.g., 18 for tokens with 18 decimals */
  repoTokenDecimals: number;

  /** @dev Units: seconds (NOT scaled) - redemptionTimestamp minus the snapshot block's timestamp, floored at 0 */
  repoTokenTimeToMaturity: BigNumber;

  // Discount rate adapter values
  /** @dev Units: scaled by RATE_PRECISION (1e18) - e.g., 0.05 (5%) = 5e16 */
  discountRate: BigNumber;

  /** @dev Units: scaled by RATE_PRECISION (1e18) - e.g., 1.0 (100%) = 1e18, 0.95 (95%) = 95e16; 0 means no haircut */
  repoRedemptionHaircut: BigNumber;

  // Asset info
  /** @dev Units: 10^assetDecimals (e.g., 1e18 for tokens with 18 decimals) */
  purchaseTokenPrecision: BigNumber;

  // Existing holdings - will be calculated from simulationData
  // These represent the CURRENT state BEFORE selling the new repoToken

  /**
   * @dev Required: Results from calling strategy.simulateTransaction(address(0), 0)
   *
   * When simulateTransaction is called with address(0) and 0, it returns the current state:
   * - simulatedWeightedMaturity: current weighted maturity in seconds
   * - simulatedRepoTokenConcentrationRatio: always 0 for address(0)
   * - simulatedLiquidityRatio: current liquidity ratio (scaled by RATE_PRECISION)
   *
   * simulatedWeightedMaturity is floor(cumulativeWeightedTime / (cumulativeAmount + liquidBalance)).
   * The strategy does not expose cumulativeAmount (the face value of held repoTokens and pending
   * offers), so the time-to-maturity constraint estimates it conservatively:
   * cumulativeAmount + liquidBalance as totalAssetValue, which is never above it because holdings
   * count at present value rather than face value, and cumulativeWeightedTime as
   * (simulatedWeightedMaturity + 1) * totalAssetValue, which covers the flooring. While the
   * strategy is below its threshold, an amount that passes this estimate also passes on-chain.
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

/** The checks sellRepoToken applies to a sale, in the order it applies them. */
export type SellRepoTokenCheck =
  | "liquidBalance"
  | "timeToMaturity"
  | "reserveRatio"
  | "concentration";

/**
 * Strategy state after selling a given repoToken amount, computed with the same integer math
 * sellRepoToken uses. For a zero amount this is the current state.
 */
export interface SaleEvaluation {
  /** @dev Units: repoToken precision */
  repoTokenAmount: BigNumber;
  /** @dev Units: base asset precision - the repoToken amount at face value, after the redemption haircut */
  repoTokenAmountInBaseAssetPrecision: BigNumber;
  /** @dev Units: base asset precision - what the strategy pays for repoTokenAmount */
  proceeds: BigNumber;
  /** @dev Units: base asset precision */
  liquidBalanceBefore: BigNumber;
  /** @dev Units: base asset precision - liquidBalanceBefore minus proceeds */
  liquidBalanceAfter: BigNumber;
  /** @dev Units: base asset precision */
  totalAssetValueBefore: BigNumber;
  /**
   * @dev Units: seconds - conservative estimate, rounded up; see MaxSellableInputData.simulationData.
   *      strategy.simulateTransaction(repoToken, repoTokenAmount) returns the exact on-chain value.
   */
  weightedTimeToMaturityAfter: BigNumber;
  /** @dev Units: seconds */
  timeToMaturityThreshold: BigNumber;
  /**
   * @dev Units: scaled by RATE_PRECISION (1e18) - liquidBalanceAfter / totalAssetValueBefore,
   *      which is the ratio sellRepoToken checks against requiredReserveRatio
   */
  liquidReserveRatioAfter: BigNumber;
  /** @dev Units: scaled by RATE_PRECISION (1e18) */
  requiredReserveRatio: BigNumber;
  /** @dev Units: scaled by RATE_PRECISION (1e18) */
  repoTokenConcentrationAfter: BigNumber;
  /** @dev Units: scaled by RATE_PRECISION (1e18) */
  repoTokenConcentrationLimit: BigNumber;
  /** The sellRepoToken checks this amount fails, in the order sellRepoToken applies them */
  failedChecks: SellRepoTokenCheck[];
}

/**
 * Result of calculating maximum sellable repoToken amount
 */
export interface MaxSellableResult {
  /** @dev Units: repoToken precision */
  maxAmount: BigNumber;
  /**
   * @dev Units: repoToken precision - set only when the strategy is at or above its
   *      time-to-maturity threshold and selling this repoToken lowers its weighted maturity, which
   *      needs threshold - timeToMaturity > 360 days / rate: smaller sales leave it above the
   *      threshold and revert.
   */
  minAmount?: BigNumber;
  reason?: string;
  limitingConstraint?:
    | SellRepoTokenCheck
    | "blacklisted"
    | "matured"
    | "zeroBalance"
    | "zeroValue";
  /** Strategy state after selling maxAmount (the current state when maxAmount is zero) */
  constraints?: SaleEvaluation;
}

/** Bounds on the repoToken amount imposed by one check, as solved from its linear form. */
interface AmountBounds {
  upper?: BigNumber;
  lower?: BigNumber;
}

function ceilDiv(numerator: BigNumber, denominator: BigNumber): BigNumber {
  return numerator.add(denominator).sub(1).div(denominator);
}

function minOf(values: BigNumber[]): BigNumber {
  return values.reduce((min, value) => (value.lt(min) ? value : min));
}

/**
 * Solves amount * growth <= slack over non-negative amounts.
 *
 * When growth is negative the inequality flips, so the quotient becomes a minimum amount rather
 * than a maximum. A zero upper bound means no positive amount satisfies the check.
 */
function solveAmountBounds(growth: BigNumber, slack: BigNumber): AmountBounds {
  if (growth.gt(0)) {
    return { upper: slack.lt(0) ? ZERO : slack.div(growth) };
  }
  if (growth.lt(0)) {
    return slack.gte(0) ? {} : { lower: ceilDiv(slack.mul(-1), growth.mul(-1)) };
  }
  return slack.gte(0) ? {} : { upper: ZERO };
}

/** Mirrors RepoTokenUtils.getNormalizedRepoTokenAmount */
function normalizeRepoTokenAmount(
  inputData: MaxSellableInputData,
  repoTokenAmount: BigNumber
): BigNumber {
  const repoTokenPrecision = BigNumber.from(10).pow(inputData.repoTokenDecimals);
  return inputData.repoRedemptionHaircut.isZero()
    ? inputData.redemptionValue
        .mul(repoTokenAmount)
        .mul(inputData.purchaseTokenPrecision)
        .div(repoTokenPrecision.mul(RATE_PRECISION))
    : inputData.redemptionValue
        .mul(inputData.repoRedemptionHaircut)
        .mul(repoTokenAmount)
        .mul(inputData.purchaseTokenPrecision)
        .div(repoTokenPrecision.mul(RATE_PRECISION).mul(RATE_PRECISION));
}

/**
 * The divisor RepoTokenUtils.calculatePresentValue applies (after multiplying by
 * purchaseTokenPrecision) at the sellRepoToken rate, discountRate + discountRateMarkup.
 */
function presentValueDenominator(inputData: MaxSellableInputData): BigNumber {
  const timeLeftToMaturityDayFraction = inputData.repoTokenTimeToMaturity
    .mul(inputData.purchaseTokenPrecision)
    .div(THREESIXTY_DAYCOUNT_SECONDS);
  const rate = inputData.discountRate.add(inputData.discountRateMarkup);
  return inputData.purchaseTokenPrecision.add(
    rate.mul(timeLeftToMaturityDayFraction).div(RATE_PRECISION)
  );
}

/**
 * Evaluates selling repoTokenAmount to the strategy with the integer math sellRepoToken uses, and
 * reports which of its checks fail.
 */
export function evaluateRepoTokenSale(
  inputData: MaxSellableInputData,
  repoTokenAmount: BigNumber
): SaleEvaluation {
  const liquidBalance = inputData.liquidBalance;
  const totalAssetValue = inputData.totalAssetValue;
  const precision = inputData.purchaseTokenPrecision;

  const amountInBase = normalizeRepoTokenAmount(inputData, repoTokenAmount);
  // calculatePresentValue caps the result at amountInBase; the denominator is never below
  // purchaseTokenPrecision, so the cap never binds here.
  const proceeds = amountInBase.mul(precision).div(presentValueDenominator(inputData));
  // Signed, so a sale that fails the liquidBalance check still yields comparable ratios below.
  const liquidBalanceAfter = liquidBalance.sub(proceeds);

  // Strategy._calculateWeightedMaturity with the conservative estimate described in
  // MaxSellableInputData.simulationData. Rounded up, so comparing it with the threshold is the
  // unrounded comparison the on-chain guarantee relies on.
  const cumulativeWeightedTime = inputData.simulationData.simulatedWeightedMaturity
    .add(1)
    .mul(totalAssetValue);
  const weightedDenominator = totalAssetValue.add(amountInBase).sub(proceeds);
  const weightedTimeToMaturityAfter = weightedDenominator.lte(0)
    ? ZERO
    : ceilDiv(
        cumulativeWeightedTime.add(inputData.repoTokenTimeToMaturity.mul(amountInBase)),
        weightedDenominator
      );

  // sellRepoToken reverts before this check when totalAssetValue is zero
  const liquidReserveRatioAfter = totalAssetValue.isZero()
    ? ZERO
    : liquidBalanceAfter.mul(RATE_PRECISION).div(totalAssetValue);

  // Strategy._getRepoTokenConcentrationRatio
  const repoTokenValue = (inputData.currentRepoTokenValue ?? ZERO)
    .add(amountInBase)
    .mul(RATE_PRECISION)
    .div(precision);
  const adjustedTotalAssetValue = totalAssetValue
    .add(amountInBase)
    .sub(proceeds)
    .mul(RATE_PRECISION)
    .div(precision);
  const repoTokenConcentrationAfter = adjustedTotalAssetValue.lte(0)
    ? ZERO
    : repoTokenValue.mul(RATE_PRECISION).div(adjustedTotalAssetValue);

  const failedChecks: SellRepoTokenCheck[] = [];
  if (liquidBalance.lt(proceeds)) {
    failedChecks.push("liquidBalance");
  }
  if (weightedTimeToMaturityAfter.gt(inputData.timeToMaturityThreshold)) {
    failedChecks.push("timeToMaturity");
  }
  if (liquidReserveRatioAfter.lt(inputData.requiredReserveRatio)) {
    failedChecks.push("reserveRatio");
  }
  if (repoTokenConcentrationAfter.gt(inputData.repoTokenConcentrationLimit)) {
    failedChecks.push("concentration");
  }

  return {
    repoTokenAmount,
    repoTokenAmountInBaseAssetPrecision: amountInBase,
    proceeds,
    liquidBalanceBefore: liquidBalance,
    liquidBalanceAfter,
    totalAssetValueBefore: totalAssetValue,
    weightedTimeToMaturityAfter,
    timeToMaturityThreshold: inputData.timeToMaturityThreshold,
    liquidReserveRatioAfter,
    requiredReserveRatio: inputData.requiredReserveRatio,
    repoTokenConcentrationAfter,
    repoTokenConcentrationLimit: inputData.repoTokenConcentrationLimit,
    failedChecks,
  };
}

const CHECK_FAILURE_REASONS: Record<SellRepoTokenCheck, string> = {
  liquidBalance: "Strategy liquid balance cannot cover the proceeds",
  timeToMaturity: "Sale would put the weighted time to maturity above the threshold",
  reserveRatio: "Sale would put the liquid reserve ratio below the required ratio",
  concentration: "Sale would put the repoToken concentration above the limit",
};

/**
 * Calculates the maximum amount of a repoToken that can be sold using analytical solutions
 * for each constraint, then taking the minimum.
 *
 * This is a pure function that takes all required data as input - no RPC calls.
 *
 * Each bound is solved from the linear form of its check, and the exact boundary around the
 * smallest one is then found with evaluateRepoTokenSale, so the liquid balance, reserve ratio and
 * concentration checks hold exactly as sellRepoToken computes them. The time-to-maturity check
 * uses a conservative estimate (see MaxSellableInputData.simulationData), so when it is the
 * binding check the true maximum can be slightly higher.
 * Eligibility checks that do not depend on the amount (term deployment, purchase token,
 * collateral parameters, paused state) are not evaluated.
 *
 * @param inputData All required input data for the calculation
 * @returns The maximum sellable amount and reason if no amount can be sold
 */
export function calculateMaxSellableRepoTokenAmount(
  inputData: MaxSellableInputData
): MaxSellableResult {
  // Basic validations
  if (inputData.isBlacklisted) {
    return {
      maxAmount: ZERO,
      reason: "RepoToken is blacklisted",
      limitingConstraint: "blacklisted",
    };
  }

  // sellRepoToken requires both to be non-zero
  if (inputData.liquidBalance.isZero() || inputData.totalAssetValue.isZero()) {
    return {
      maxAmount: ZERO,
      reason: "Insufficient liquid balance",
      limitingConstraint: "zeroBalance",
    };
  }

  if (inputData.repoTokenTimeToMaturity.isZero()) {
    return {
      maxAmount: ZERO,
      reason: "RepoToken has already matured",
      limitingConstraint: "matured",
    };
  }

  const liquidBalance = inputData.liquidBalance;
  const totalAssetValue = inputData.totalAssetValue;
  const precision = inputData.purchaseTokenPrecision;
  const repoTokenPrecision = BigNumber.from(10).pow(inputData.repoTokenDecimals);

  // amountInBase = amount * normalizedNumerator / normalizedDenominator (before flooring)
  const normalizedNumerator = inputData.repoRedemptionHaircut.isZero()
    ? inputData.redemptionValue.mul(precision)
    : inputData.redemptionValue.mul(inputData.repoRedemptionHaircut).mul(precision);
  const normalizedDenominator = inputData.repoRedemptionHaircut.isZero()
    ? repoTokenPrecision.mul(RATE_PRECISION)
    : repoTokenPrecision.mul(RATE_PRECISION).mul(RATE_PRECISION);

  if (normalizedNumerator.isZero()) {
    return {
      maxAmount: ZERO,
      reason: "RepoToken has zero redemption value",
      limitingConstraint: "zeroValue",
    };
  }

  // proceeds = amountInBase * precision / pvDenominator (before flooring). Multiplying every
  // inequality below through by normalizedDenominator * pvDenominator keeps it in integers:
  //   amountInBase -> amount * normalizedNumerator * pvDenominator
  //   proceeds     -> amount * normalizedNumerator * precision
  const pvDenominator = presentValueDenominator(inputData);
  const scale = normalizedDenominator.mul(pvDenominator);
  const baseGrowth = normalizedNumerator.mul(pvDenominator);
  const proceedsGrowth = normalizedNumerator.mul(precision);

  // Flooring in the contract can only lower proceeds, so an amount within this bound always
  // keeps proceeds <= maxProceeds.
  const boundProceeds = (maxProceeds: BigNumber): AmountBounds =>
    solveAmountBounds(proceedsGrowth, maxProceeds.mul(scale));

  // CONSTRAINT 1: Liquid Balance
  // proceeds <= liquidBalance
  const liquidBalanceBounds = boundProceeds(liquidBalance);

  // CONSTRAINT 2: Time to Maturity
  // (cumulativeWeightedTime + timeToMaturity * amountInBase)
  //   / (cumulativeAmount + liquidBalance + amountInBase - proceeds) <= threshold
  // With the estimates cumulativeAmount + liquidBalance = totalAssetValue and
  // cumulativeWeightedTime = (weightedMaturity + 1) * totalAssetValue:
  //   amount * (timeToMaturity * amountInBase' - threshold * (amountInBase' - proceeds'))
  //     <= (threshold - weightedMaturity - 1) * totalAssetValue
  // where primes are per unit of amount. The left-hand factor is negative only when the discount
  // outweighs the repoToken's time to maturity (threshold - timeToMaturity > 360 days / rate);
  // the solution is then a minimum amount.
  const threshold = inputData.timeToMaturityThreshold;
  const maturityBounds = solveAmountBounds(
    inputData.repoTokenTimeToMaturity
      .mul(baseGrowth)
      .sub(threshold.mul(baseGrowth.sub(proceedsGrowth))),
    threshold
      .sub(inputData.simulationData.simulatedWeightedMaturity.add(1))
      .mul(totalAssetValue)
      .mul(scale)
  );

  // CONSTRAINT 3: Reserve Ratio
  // (liquidBalance - proceeds) * 1e18 / totalAssetValue >= requiredReserveRatio, i.e.
  // proceeds <= liquidBalance - ceil(totalAssetValue * requiredReserveRatio / 1e18).
  // Compared first so a reserve larger than the liquid balance maps to a zero bound.
  const requiredReserve = ceilDiv(
    totalAssetValue.mul(inputData.requiredReserveRatio),
    RATE_PRECISION
  );
  const reserveRatioBounds = boundProceeds(
    requiredReserve.lt(liquidBalance) ? liquidBalance.sub(requiredReserve) : ZERO
  );

  // CONSTRAINT 4: Concentration
  // (currentRepoTokenValue + amountInBase) / (totalAssetValue + amountInBase - proceeds) <= limit
  // The denominator keeps proceeds: the sale adds the repoToken at face value and removes the
  // proceeds paid for it, which differ by the discount.
  //   amount * (1e18 * amountInBase' - limit * (amountInBase' - proceeds'))
  //     <= limit * totalAssetValue - 1e18 * currentRepoTokenValue
  const limit = inputData.repoTokenConcentrationLimit;
  const concentrationBounds = solveAmountBounds(
    RATE_PRECISION.mul(baseGrowth).sub(limit.mul(baseGrowth.sub(proceedsGrowth))),
    limit
      .mul(totalAssetValue)
      .sub(RATE_PRECISION.mul(inputData.currentRepoTokenValue ?? ZERO))
      .mul(scale)
  );

  const bounds: { check: SellRepoTokenCheck; bounds: AmountBounds }[] = [
    { check: "liquidBalance", bounds: liquidBalanceBounds },
    { check: "timeToMaturity", bounds: maturityBounds },
    { check: "reserveRatio", bounds: reserveRatioBounds },
    { check: "concentration", bounds: concentrationBounds },
  ];

  // Zero bounds are kept: a check that allows no amount caps the result at zero.
  const upperBounds = bounds.filter(({ bounds }) => bounds.upper !== undefined);
  const upper = minOf(upperBounds.map(({ bounds }) => bounds.upper as BigNumber));
  const minAmount = maturityBounds.lower;
  const lower = minAmount !== undefined && minAmount.gt(ONE) ? minAmount : ONE;

  // The analytic bounds ignore the contract's intermediate flooring, so the smallest one can be
  // off by a few units either way. Settle the exact boundary with the contract's math: step up
  // from the bound while larger amounts still pass, or search down if the bound itself fails.
  const passes = (amount: BigNumber) =>
    evaluateRepoTokenSale(inputData, amount).failedChecks.length === 0;
  // Largest passing amount in [passing, failing), given that `passing` passes and `failing` fails.
  const largestPassing = (passing: BigNumber, failing: BigNumber): BigNumber => {
    while (failing.sub(passing).gt(1)) {
      const mid = passing.add(failing).div(2);
      if (passes(mid)) {
        passing = mid;
      } else {
        failing = mid;
      }
    }
    return passing;
  };
  let maxAmount = ZERO;
  if (upper.gte(lower)) {
    if (passes(upper)) {
      let step = ONE;
      let passing = upper;
      while (passes(passing.add(step))) {
        passing = passing.add(step);
        step = step.mul(2);
      }
      maxAmount = largestPassing(passing, passing.add(step));
    } else if (passes(lower)) {
      maxAmount = largestPassing(lower, upper);
    }
  }

  // The binding check is the first one that fails for one more unit (or, when nothing can be
  // sold, for the smallest candidate), falling back to the check with the smallest bound.
  const firstFailure = evaluateRepoTokenSale(
    inputData,
    maxAmount.gt(0) ? maxAmount.add(1) : lower
  ).failedChecks[0];
  const smallestBound = upperBounds.find(({ bounds }) => bounds.upper?.eq(upper))?.check;
  const limitingConstraint = firstFailure ?? smallestBound;

  return {
    maxAmount,
    minAmount,
    reason:
      maxAmount.isZero() && limitingConstraint
        ? CHECK_FAILURE_REASONS[limitingConstraint]
        : undefined,
    limitingConstraint,
    constraints: evaluateRepoTokenSale(inputData, maxAmount),
  };
}
