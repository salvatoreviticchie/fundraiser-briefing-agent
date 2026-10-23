/**
 * Rule-based lapse-risk score (0-100, higher = more likely to lapse) built from
 * the classic fundraising RFM signals:
 *
 *   Recency   (max 50): time since last gift, relative to the donor's own cadence
 *   Frequency (max 25): giving consistency - of the last 3 years the donor could
 *                       have given in, how many did they actually give in
 *   Monetary  (max 25): year-on-year giving trend
 *
 * Deliberately transparent rather than a trained model: a gift officer can see
 * exactly why a donor is flagged, and each threshold is unit-tested.
 */
public with sharing class LapseRiskScorer {
    public static final String BAND_LOW = 'Low';
    public static final String BAND_MEDIUM = 'Medium';
    public static final String BAND_HIGH = 'High';
    public static final String BAND_UNKNOWN = 'Unknown';

    /** Beyond two years of silence a donor is considered lapsed whatever their cadence. */
    public static final Integer LAPSED_AFTER_DAYS = 730;

    @TestVisible
    private static final Integer MEDIUM_THRESHOLD = 30;
    @TestVisible
    private static final Integer HIGH_THRESHOLD = 60;
    /** In the Low band, only factors at least this large are worth a "watch" note. */
    @TestVisible
    private static final Integer WATCH_THRESHOLD = 10;

    public class Result {
        /** Null when there is no gift history to score. */
        public Integer score;
        public String band;
        public String explanation;
        public Integer recencyPoints = 0;
        public Integer frequencyPoints = 0;
        public Integer monetaryPoints = 0;
    }

    /**
     * A scored factor. `risk` explains the points when they are > 0; `strength` is the
     * positive phrasing used for Low-band donors (null when there is nothing worth saying).
     */
    private class Factor {
        Integer points;
        String risk;
        String strength;
        Factor(Integer points, String risk, String strength) {
            this.points = points;
            this.risk = risk;
            this.strength = strength;
        }
    }

    public static Result score(GivingSummary summary) {
        Result r = new Result();
        if (!summary.hasGifts()) {
            r.band = BAND_UNKNOWN;
            r.explanation = 'No gifts on record: treat as a prospect, not a lapse risk.';
            return r;
        }

        List<Factor> factors = new List<Factor>{
            recencyFactor(summary),
            frequencyFactor(summary),
            monetaryFactor(summary)
        };
        r.recencyPoints = factors[0].points;
        r.frequencyPoints = factors[1].points;
        r.monetaryPoints = factors[2].points;
        r.score = r.recencyPoints + r.frequencyPoints + r.monetaryPoints;
        r.band = bandFor(r.score);
        r.explanation = r.band == BAND_LOW ? explainLow(factors) : explainRisk(r.band, factors);
        return r;
    }

    @TestVisible
    private static String bandFor(Integer score) {
        if (score >= HIGH_THRESHOLD) {
            return BAND_HIGH;
        }
        return score >= MEDIUM_THRESHOLD ? BAND_MEDIUM : BAND_LOW;
    }

    private static Factor recencyFactor(GivingSummary s) {
        Integer days = s.daysSinceLastGift;
        String lastGift = 'last gift ' + describeAgo(days);
        if (days > LAPSED_AFTER_DAYS) {
            return new Factor(50, lastGift, null);
        }
        if (s.averageIntervalDays == null) {
            // Single gift: no cadence yet, so fall back to absolute time.
            Integer points = days <= 180 ? 0 : days <= 365 ? 15 : days <= 540 ? 30 : 40;
            return new Factor(points, lastGift, lastGift);
        }
        // Cadence-aware: compare the silence with how often this donor normally gives.
        String rhythm = ' (usually gives every ' + describeDuration(s.averageIntervalDays) + ')';
        Decimal ratio = Decimal.valueOf(days) / s.averageIntervalDays;
        Integer points = ratio <= 1.25 ? 0 : ratio <= 1.5 ? 15 : ratio <= 2 ? 30 : ratio <= 3 ? 40 : 50;
        return new Factor(
            points,
            lastGift + rhythm,
            lastGift + ', in line with their usual rhythm (every ' + describeDuration(s.averageIntervalDays) + ')'
        );
    }

    private static Factor frequencyFactor(GivingSummary s) {
        Integer eligible = s.eligibleGivingYears;
        Integer active = s.activeGivingYears;
        if (active == 0) {
            return new Factor(25, 'no gifts in the last 3 years', null);
        }
        Integer missed = eligible - active;
        Integer points = missed == 0 ? 0 : missed == 1 ? 10 : 18;
        String risk = 'gave in only ' + active + ' of the last ' + eligible + ' years';
        // "Gave in each of the last 1 years" says nothing, so only praise multi-year consistency.
        String strength = eligible >= 2 ? 'gave in each of the last ' + eligible + ' years' : null;
        return new Factor(points, risk, strength);
    }

    private static Factor monetaryFactor(GivingSummary s) {
        switch on s.trend {
            when 'Increasing' {
                String text = 'giving up ' + s.trendPercent + '% year on year';
                return new Factor(0, text, text);
            }
            when 'Stable' {
                return new Factor(5, 'giving flat year on year', 'giving steady year on year');
            }
            when 'New' {
                return new Factor(5, 'giving only started in the last 12 months', 'new donor this year');
            }
            when 'Declining' {
                Integer points = s.trendPercent < -50 ? 25 : 15;
                return new Factor(points, 'giving down ' + Math.abs(s.trendPercent) + '% year on year', null);
            }
            when else {
                return new Factor(25, 'no gifts in the last 2 years', null);
            }
        }
    }

    /** Medium/High: "<Band>: <biggest risk>; <second risk>." */
    private static String explainRisk(String band, List<Factor> factors) {
        List<String> reasons = new List<String>();
        for (Factor f : sortByPointsDesc(factors)) {
            if (f.points > 0 && reasons.size() < 2) {
                reasons.add(f.risk);
            }
        }
        return band + ': ' + String.join(reasons, '; ') + '.';
    }

    /**
     * Low: lead with what is going well, then flag any single factor that is worth watching.
     * Never empty: recency is either 0 (and always has a strength) or at least 15 (a watch item).
     */
    private static String explainLow(List<Factor> factors) {
        List<String> parts = new List<String>();
        for (Factor f : factors) {
            if (f.points == 0 && f.strength != null) {
                parts.add(f.strength);
            }
        }
        for (Factor f : sortByPointsDesc(factors)) {
            if (f.points >= WATCH_THRESHOLD) {
                parts.add('watch: ' + f.risk);
                break;
            }
        }
        return BAND_LOW + ': ' + String.join(parts, '; ') + '.';
    }

    private static List<Factor> sortByPointsDesc(List<Factor> factors) {
        List<Factor> sorted = new List<Factor>();
        for (Factor f : factors) {
            Integer i = 0;
            while (i < sorted.size() && sorted[i].points >= f.points) {
                i++;
            }
            if (i == sorted.size()) {
                sorted.add(f);
            } else {
                sorted.add(i, f);
            }
        }
        return sorted;
    }

    @TestVisible
    private static String describeAgo(Integer days) {
        return days == 0 ? 'today' : describeDuration(days) + ' ago';
    }

    /** Human-readable duration: "10 days", "3 weeks", "14 months". */
    public static String describeDuration(Integer days) {
        if (days < 14) {
            return days + (days == 1 ? ' day' : ' days');
        }
        if (days < 60) {
            return Math.round(days / 7.0) + ' weeks';
        }
        return Math.round(days / 30.44) + ' months';
    }
}
