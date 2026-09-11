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
   * simulatedWeightedMaturity is floor(W / D), where W is the cumulative weighted time and D is
   * cumulativeAmount + liquidBalance. The strategy exposes neither W nor cumulativeAmount (the
   * face value of held repoTokens and pending offers), so the time-to-maturity check substitutes
   * totalAssetValue for D and (simulatedWeightedMaturity + 1) * totalAssetValue for W. Neither
   * substitute bounds its counterpart on its own, but W < (simulatedWeightedMaturity + 1) * D and
   * D >= totalAssetValue (holdings count at present value, not face value), so while
   * simulatedWeightedMaturity < threshold, a sale that passes the substituted check also passes
   * on-chain. At or above the threshold no sale can be vouched for, so the check fails for every
   * amount. The guarantee also assumes the repoToken has no untracked balance or auction offer at
   * the strategy; the calculator declines to size those states (see the validation flags).
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

  /**
   * @dev Units: repoToken precision - the strategy's current balance of this repoToken; 0 if none.
   *
   * For a held repoToken, the weighted-maturity calculation normalizes balance + amount together,
   * which can add one base unit more than normalizing the amount alone.
   */
  repoTokenBalance: BigNumber;

  // Validation flags
  /** @dev Units: boolean - true if repoToken is blacklisted */
  isBlacklisted: boolean;

  /**
   * @dev Units: boolean - true if redemptionTimestamp is before the snapshot block's timestamp,
   *      which sellRepoToken rejects. A repoToken at exactly its redemption timestamp is still
   *      accepted, at face value.
   */
  isMatured: boolean;

  /**
   * @dev Units: boolean - true if the strategy holds a balance of this repoToken without listing
   *      it (a direct transfer, or repoTokens from an auction it has not processed yet).
   *      sellRepoToken lists the repoToken first and then values that balance as a holding, which
   *      this snapshot does not reflect.
   */
  hasUntrackedBalance: boolean;

  /**
   * @dev Units: boolean - true if the strategy has an auction offer for this repoToken. Its
   *      weighted-maturity calculation then replaces that offer's amount with the sale amount,
   *      which the time-to-maturity estimate does not model.
   */
  hasPendingOffer: boolean;
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
   * @dev Units: seconds - estimate, rounded up; see MaxSellableInputData.simulationData. It is not
   *      a bound on the on-chain value, but while the strategy is below its threshold, a value at
   *      or below the threshold means sellRepoToken's check passes.
   *      strategy.simulateTransaction(repoToken, repoTokenAmount) returns the exact value.
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
  reason?: string;
  limitingConstraint?:
    | SellRepoTokenCheck
    | "blacklisted"
    | "matured"
    | "untrackedBalance"
    | "pendingOffer"
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

  // Strategy._calculateWeightedMaturity with the substitutes described in
  // MaxSellableInputData.simulationData. Rounded up, so comparing it with the threshold is the
  // unrounded comparison the on-chain guarantee relies on. Selling nothing leaves the current,
  // exactly known value.
  const weightedMaturity = inputData.simulationData.simulatedWeightedMaturity;
  const cumulativeWeightedTime = weightedMaturity.add(1).mul(totalAssetValue);
  // RepoTokenList.getCumulativeRepoTokenData normalizes a held balance and the sale together
  const balance = inputData.repoTokenBalance;
  const weightedAmountInBase = normalizeRepoTokenAmount(inputData, balance.add(repoTokenAmount)).sub(
    normalizeRepoTokenAmount(inputData, balance)
  );
  const weightedDenominator = totalAssetValue.add(weightedAmountInBase).sub(proceeds);
  const weightedTimeToMaturityAfter = repoTokenAmount.isZero()
    ? weightedMaturity
    : weightedDenominator.lte(0)
      ? ZERO
      : ceilDiv(
          cumulativeWeightedTime.add(inputData.repoTokenTimeToMaturity.mul(weightedAmountInBase)),
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
  if (
    weightedMaturity.gte(inputData.timeToMaturityThreshold) ||
    weightedTimeToMaturityAfter.gt(inputData.timeToMaturityThreshold)
  ) {
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
 * uses substitutes that only err toward rejecting a sale (see MaxSellableInputData.simulationData),
 * so when it is the binding check the true maximum can be slightly higher.
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

  if (inputData.isMatured) {
    return {
      maxAmount: ZERO,
      reason: "RepoToken has already matured",
      limitingConstraint: "matured",
    };
  }

  // removeAndRedeemMaturedTokens treats redemptionTimestamp <= block.timestamp as matured, so at
  // exactly that timestamp sellRepoToken redeems a held balance before pricing the sale, leaving a
  // state this snapshot does not describe.
  if (inputData.repoTokenTimeToMaturity.isZero() && inputData.repoTokenBalance.gt(0)) {
    return {
      maxAmount: ZERO,
      reason:
        "RepoToken reaches its redemption timestamp in this block and sellRepoToken would first redeem the strategy's balance",
      limitingConstraint: "matured",
    };
  }

  if (inputData.hasUntrackedBalance) {
    return {
      maxAmount: ZERO,
      reason:
        "Strategy holds an unlisted balance of this repoToken that sellRepoToken would start counting",
      limitingConstraint: "untrackedBalance",
    };
  }

  if (inputData.hasPendingOffer) {
    return {
      maxAmount: ZERO,
      reason:
        "Strategy has an auction offer for this repoToken, which changes how sellRepoToken computes weighted maturity",
      limitingConstraint: "pendingOffer",
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
  const boundProceeds = (maxProceeds: BigNumber): BigNumber | undefined =>
    solveAmountBounds(proceedsGrowth, maxProceeds.mul(scale)).upper;

  // CONSTRAINT 1: Liquid Balance
  // proceeds <= liquidBalance
  const liquidBalanceBound = boundProceeds(liquidBalance);

  // CONSTRAINT 2: Time to Maturity
  // (cumulativeWeightedTime + timeToMaturity * amountInBase)
  //   / (cumulativeAmount + liquidBalance + amountInBase - proceeds) <= threshold
  // With the estimates cumulativeAmount + liquidBalance = totalAssetValue and
  // cumulativeWeightedTime = (weightedMaturity + 1) * totalAssetValue:
  //   amount * (timeToMaturity * amountInBase' - threshold * (amountInBase' - proceeds'))
  //     <= (threshold - weightedMaturity - 1) * totalAssetValue
  // where primes are per unit of amount. The left-hand factor is negative only when the discount
  // outweighs the repoToken's time to maturity (threshold - timeToMaturity > 360 days / rate).
  // A negative factor with a negative right-hand side gives a minimum amount: the strategy is at
  // or above its threshold and only a large enough sale would bring it back under. The estimate
  // cannot vouch for any sale from that state, so it is treated as allowing none.
  // BigNumber is signed, so at or above the threshold the right-hand side is simply negative.
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
  const maturityBound = maturityBounds.lower !== undefined ? ZERO : maturityBounds.upper;

  // CONSTRAINT 3: Reserve Ratio
  // (liquidBalance - proceeds) * 1e18 / totalAssetValue >= requiredReserveRatio, i.e.
  // proceeds <= liquidBalance - ceil(totalAssetValue * requiredReserveRatio / 1e18).
  // Compared first so a reserve larger than the liquid balance maps to a zero bound.
  const requiredReserve = ceilDiv(
    totalAssetValue.mul(inputData.requiredReserveRatio),
    RATE_PRECISION
  );
  const reserveRatioBound = boundProceeds(
    requiredReserve.lt(liquidBalance) ? liquidBalance.sub(requiredReserve) : ZERO
  );

  // CONSTRAINT 4: Concentration
  // (currentRepoTokenValue + amountInBase) / (totalAssetValue + amountInBase - proceeds) <= limit
  // The denominator keeps proceeds: the sale adds the repoToken at face value and removes the
  // proceeds paid for it, which differ by the discount.
  //   amount * (1e18 * amountInBase' - limit * (amountInBase' - proceeds'))
  //     <= limit * totalAssetValue - 1e18 * currentRepoTokenValue
  const limit = inputData.repoTokenConcentrationLimit;
  const concentrationBound = solveAmountBounds(
    RATE_PRECISION.mul(baseGrowth).sub(limit.mul(baseGrowth.sub(proceedsGrowth))),
    limit
      .mul(totalAssetValue)
      .sub(RATE_PRECISION.mul(inputData.currentRepoTokenValue ?? ZERO))
      .mul(scale)
  ).upper;

  // Zero bounds are kept: a check that allows no amount caps the result at zero. The liquid
  // balance bound always exists, so there is at least one.
  const upper = minOf(
    [liquidBalanceBound, maturityBound, reserveRatioBound, concentrationBound].filter(
      (bound): bound is BigNumber => bound !== undefined
    )
  );

  // The analytic bounds ignore the contract's intermediate flooring, so the smallest one can be
  // off by a few units either way; a zero bound can even hide dust amounts whose value floors to
  // zero. Settle the exact boundary with the contract's math: step up from the bound while larger
  // amounts still pass, or search down if the bound itself fails. Selling nothing always passes.
  const passes = (amount: BigNumber) =>
    amount.isZero() || evaluateRepoTokenSale(inputData, amount).failedChecks.length === 0;
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
  let maxAmount: BigNumber;
  if (passes(upper)) {
    let step = ONE;
    let passing = upper;
    while (passes(passing.add(step))) {
      passing = passing.add(step);
      step = step.mul(2);
    }
    maxAmount = largestPassing(passing, passing.add(step));
  } else {
    maxAmount = largestPassing(ZERO, upper);
  }

  // By construction one more unit fails; the first check it fails is the binding one.
  const limitingConstraint = evaluateRepoTokenSale(inputData, maxAmount.add(1)).failedChecks[0];
  const aboveThreshold =
    inputData.simulationData.simulatedWeightedMaturity.gte(threshold);

  return {
    maxAmount,
    reason: !maxAmount.isZero()
      ? undefined
      : limitingConstraint === "timeToMaturity" && aboveThreshold
        ? "Strategy is already at or above its time-to-maturity threshold"
        : CHECK_FAILURE_REASONS[limitingConstraint],
    limitingConstraint,
    constraints: evaluateRepoTokenSale(inputData, maxAmount),
  };
}
