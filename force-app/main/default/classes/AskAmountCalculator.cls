/**
 * Suggests an ask amount for the next conversation and explains how it was reached.
 *
 *   base       = largest gift in the last 36 months (falls back to largest ever)
 *   multiplier = 1.5 Low risk (upgrade) | 1.2 Medium (modest upgrade) | 1.0 High (renewal)
 *                +0.1 when giving is increasing
 *   cap        = upper bound of the donor's capacity rating (A uncapped)
 *   rounding   = to a figure a person would actually say out loud
 */
public with sharing class AskAmountCalculator {
    @TestVisible
    private static final Map<String, Decimal> RISK_MULTIPLIERS = new Map<String, Decimal>{
        LapseRiskScorer.BAND_LOW => 1.5,
        LapseRiskScorer.BAND_MEDIUM => 1.2,
        LapseRiskScorer.BAND_HIGH => 1.0
    };
    @TestVisible
    private static final Decimal INCREASING_TREND_BONUS = 0.1;

    /** Upper bound of each capacity band; 'A' is intentionally absent (no cap). */
    @TestVisible
    private static final Map<String, Decimal> CAPACITY_CAPS = new Map<String, Decimal>{
        'B' => 100000,
        'C' => 25000,
        'D' => 5000
    };

    public class Result {
        /** Null when there is no history to base an ask on. */
        public Decimal amount;
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

        Boolean hasRecentGift = summary.largestGiftLast36Months != null;
        Decimal base = hasRecentGift ? summary.largestGiftLast36Months : summary.largestGiftEver;
        String baseLabel = hasRecentGift ? 'largest gift in the last 3 years' : 'largest gift (over 3 years ago)';

        Decimal multiplier = RISK_MULTIPLIERS.get(risk.band);
        String askType = risk.band == LapseRiskScorer.BAND_HIGH
            ? 'renewal ask, as the donor is at high lapse risk'
            : 'upgrade ask for a ' + risk.band.toLowerCase() + '-risk donor';
        Boolean increasing = summary.trend == GivingSummary.TREND_INCREASING;
        if (increasing) {
            multiplier += INCREASING_TREND_BONUS;
        }

        Decimal amount = roundToNatural(base * multiplier);
        String reasoning =
            multiplier.stripTrailingZeros().toPlainString() +
            'x ' +
            baseLabel +
            ' (' +
            CurrencyFormatter.format(base, currencyCode) +
            '): ' +
            askType +
            (increasing ? ', with a bonus for increasing giving' : '');

        Decimal cap = capacityRating == null ? null : CAPACITY_CAPS.get(capacityRating);
        if (cap != null && amount > cap) {
            amount = cap;
            reasoning += '; capped at capacity rating ' + capacityRating + ' (' + CurrencyFormatter.format(cap, currencyCode) + ')';
        }

        r.amount = amount;
        r.reasoning = reasoning + '.';
        return r;
    }

    /** Rounds to steps of 50 / 250 / 1'000 / 5'000 depending on magnitude, never below one step. */
    @TestVisible
    private static Decimal roundToNatural(Decimal raw) {
        Decimal step;
        if (raw < 1000) {
            step = 50;
        } else if (raw < 10000) {
            step = 250;
        } else if (raw < 100000) {
            step = 1000;
        } else {
            step = 5000;
        }
        Decimal rounded = (raw / step).setScale(0, System.RoundingMode.HALF_UP) * step;
        return Math.max(step, rounded);
    }
}
