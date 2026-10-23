/**
 * Suggests an ask amount for the next conversation and explains how it was reached.
 * The first matching strategy wins:
 *
 *   1. No gifts       -> no amount; open with a discovery conversation
 *   2. Lapsed (> 2y)  -> reactivation ask at 50% of their last gift
 *   3. Recurring      -> monthly ask: current monthly gift x risk multiplier
 *   4. Declining      -> renewal at the last 12 months' level, no upgrade
 *   5. Otherwise      -> largest gift in the last 3 years x risk multiplier
 *
 *   risk multiplier = 1.5 Low (upgrade) | 1.2 Medium | 1.0 High (renewal), +0.1 if increasing
 *   cap             = upper bound of the donor's capacity rating, compared on an annual basis
 *   rounding        = to a figure a person would actually say out loud
 */
public with sharing class AskAmountCalculator {
    public static final String FREQUENCY_ONE_OFF = 'One-off';
    public static final String FREQUENCY_MONTHLY = 'Monthly';

    @TestVisible
    private static final Map<String, Decimal> RISK_MULTIPLIERS = new Map<String, Decimal>{
        LapseRiskScorer.BAND_LOW => 1.5,
        LapseRiskScorer.BAND_MEDIUM => 1.2,
        LapseRiskScorer.BAND_HIGH => 1.0
    };
    @TestVisible
    private static final Decimal INCREASING_TREND_BONUS = 0.1;
    @TestVisible
    private static final Decimal REACTIVATION_SHARE = 0.5;

    /** Upper bound of each capacity band per year; 'A' is intentionally absent (no cap). */
    @TestVisible
    private static final Map<String, Decimal> CAPACITY_CAPS = new Map<String, Decimal>{
        'B' => 100000,
        'C' => 25000,
        'D' => 5000
    };

    public class Result {
        /** Null when there is no history to base an ask on. */
        public Decimal amount;
        /** One-off or Monthly. */
        public String frequency = FREQUENCY_ONE_OFF;
        public String reasoning;
    }

    public static Result suggest(
        GivingSummary summary,
        LapseRiskScorer.Result risk,
        String capacityRating,
        String currencyCode
    ) {
        Result r = new Result();
        if (!summary.hasGifts()) {
            r.reasoning = 'No giving history: open with a discovery conversation rather than a specific ask.';
            if (String.isNotBlank(capacityRating)) {
                r.reasoning += ' Capacity rating ' + capacityRating + ' indicates the potential level.';
            }
            return r;
        }

        if (summary.daysSinceLastGift > LapseRiskScorer.LAPSED_AFTER_DAYS) {
            r.amount = roundToNatural(summary.lastGiftAmount * REACTIVATION_SHARE, false);
            r.reasoning =
                'Lapsed for ' +
                LapseRiskScorer.describeDuration(summary.daysSinceLastGift) +
                ': reactivation ask at 50% of their last gift (' +
                CurrencyFormatter.format(summary.lastGiftAmount, currencyCode) +
                ') to rebuild the relationship';
        } else if (summary.lastGiftRecurring) {
            Decimal multiplier = riskMultiplier(summary, risk);
            r.frequency = FREQUENCY_MONTHLY;
            r.amount = roundToNatural(summary.lastGiftAmount * multiplier, true);
            r.reasoning =
                format(multiplier) +
                'x current monthly gift (' +
                CurrencyFormatter.format(summary.lastGiftAmount, currencyCode) +
                '): ' +
                askType(summary, risk);
        } else if (summary.trend == GivingSummary.TREND_DECLINING) {
            Boolean hasRecent = summary.givingLast12Months > 0;
            Decimal base = hasRecent ? summary.givingLast12Months : summary.lastGiftAmount;
            r.amount = roundToNatural(base, false);
            r.reasoning =
                'Giving is down ' +
                Math.abs(summary.trendPercent) +
                '% year on year, so renew at ' +
                (hasRecent ? 'the last 12 months\' level' : 'the level of their last gift') +
                ' (' +
                CurrencyFormatter.format(base, currencyCode) +
                ') rather than ask for an upgrade';
        } else {
            // A gift within the last 2 years guarantees one within the last 3, so this is never null here.
            Decimal base = summary.largestGiftLast36Months;
            Decimal multiplier = riskMultiplier(summary, risk);
            r.amount = roundToNatural(base * multiplier, false);
            r.reasoning =
                format(multiplier) +
                'x largest gift in the last 3 years (' +
                CurrencyFormatter.format(base, currencyCode) +
                '): ' +
                askType(summary, risk);
        }

        applyCapacityCap(r, capacityRating, currencyCode);
        r.reasoning += '.';
        return r;
    }

    private static Decimal riskMultiplier(GivingSummary summary, LapseRiskScorer.Result risk) {
        Decimal multiplier = RISK_MULTIPLIERS.get(risk.band);
        return summary.trend == GivingSummary.TREND_INCREASING ? multiplier + INCREASING_TREND_BONUS : multiplier;
    }

    private static String askType(GivingSummary summary, LapseRiskScorer.Result risk) {
        String text = risk.band == LapseRiskScorer.BAND_HIGH
            ? 'renewal ask, as the donor is at high lapse risk'
            : 'upgrade ask for a ' + risk.band.toLowerCase() + '-risk donor';
        return summary.trend == GivingSummary.TREND_INCREASING ? text + ', with a bonus for increasing giving' : text;
    }

    /** Caps are annual, so a monthly ask is compared as 12 payments and capped to a round monthly figure. */
    private static void applyCapacityCap(Result r, String capacityRating, String currencyCode) {
        Decimal cap = capacityRating == null ? null : CAPACITY_CAPS.get(capacityRating);
        if (cap == null) {
            return;
        }
        Boolean monthly = r.frequency == FREQUENCY_MONTHLY;
        Decimal annual = monthly ? r.amount * 12 : r.amount;
        if (annual <= cap) {
            return;
        }
        if (monthly) {
            Decimal monthlyCap = cap / 12;
            Decimal step = stepFor(monthlyCap, true);
            r.amount = (monthlyCap / step).setScale(0, System.RoundingMode.FLOOR) * step;
        } else {
            r.amount = cap;
        }
        r.reasoning +=
            '; capped at capacity rating ' +
            capacityRating +
            ' (' +
            CurrencyFormatter.format(cap, currencyCode) +
            (monthly ? ' a year' : '') +
            ')';
    }

    /** Rounds to a natural step for the magnitude (finer for monthly amounts), never below one step. */
    @TestVisible
    private static Decimal roundToNatural(Decimal raw, Boolean monthly) {
        Decimal step = stepFor(raw, monthly);
        Decimal rounded = (raw / step).setScale(0, System.RoundingMode.HALF_UP) * step;
        return Math.max(step, rounded);
    }

    private static Decimal stepFor(Decimal raw, Boolean monthly) {
        if (monthly && raw < 100) {
            return 5;
        }
        if (monthly && raw < 1000) {
            return 25;
        }
        if (raw < 1000) {
            return 50;
        }
        if (raw < 10000) {
            return 250;
        }
        return raw < 100000 ? 1000 : 5000;
    }

    /** 1 -> "1.0", 1.5 -> "1.5" */
    private static String format(Decimal multiplier) {
        return multiplier.setScale(1).toPlainString();
    }
}
