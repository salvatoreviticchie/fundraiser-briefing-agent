/**
 * Rule-based lapse-risk score (0-100, higher = more likely to lapse) built from
 * the classic fundraising RFM signals:
 *
 *   Recency   (max 50): time since last gift, relative to the donor's own cadence
 *   Frequency (max 25): number of gifts in the last 36 months
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

    @TestVisible
    private static final Integer MEDIUM_THRESHOLD = 30;
    @TestVisible
    private static final Integer HIGH_THRESHOLD = 60;
    /** Beyond two years of silence a donor is considered lapsed whatever their cadence. */
    @TestVisible
    private static final Integer LAPSED_AFTER_DAYS = 730;

    public class Result {
        /** Null when there is no gift history to score. */
        public Integer score;
        public String band;
        public String explanation;
        public Integer recencyPoints = 0;
        public Integer frequencyPoints = 0;
        public Integer monetaryPoints = 0;
    }

    /** A scored factor with its human-readable reason, so the explanation can lead with the biggest driver. */
    private class Factor {
        Integer points;
        String reason;
        Factor(Integer points, String reason) {
            this.points = points;
            this.reason = reason;
        }
    }

    public static Result score(GivingSummary summary) {
        Result r = new Result();
        if (!summary.hasGifts()) {
            r.band = BAND_UNKNOWN;
            r.explanation = 'No gifts on record: treat as a prospect, not a lapse risk.';
            return r;
        }

        Factor recency = recencyFactor(summary);
        Factor frequency = frequencyFactor(summary);
        Factor monetary = monetaryFactor(summary);

        r.recencyPoints = recency.points;
        r.frequencyPoints = frequency.points;
        r.monetaryPoints = monetary.points;
        r.score = recency.points + frequency.points + monetary.points;
        r.band = bandFor(r.score);
        r.explanation = explain(r.band, new List<Factor>{ recency, frequency, monetary });
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
        String reason = 'last gift ' + describeDays(days) + ' ago';
        Integer points;

        if (days > LAPSED_AFTER_DAYS) {
            points = 50;
        } else if (s.averageIntervalDays != null) {
            // Cadence-aware: compare the silence with how often this donor normally gives.
            reason += ' (usually gives every ' + describeDays(s.averageIntervalDays) + ')';
            Decimal ratio = Decimal.valueOf(days) / s.averageIntervalDays;
            if (ratio <= 1.25) {
                points = 0;
            } else if (ratio <= 1.5) {
                points = 15;
            } else if (ratio <= 2) {
                points = 30;
            } else if (ratio <= 3) {
                points = 40;
            } else {
                points = 50;
            }
        } else {
            // Single gift: no cadence yet, so fall back to absolute time.
            if (days <= 180) {
                points = 0;
            } else if (days <= 365) {
                points = 15;
            } else if (days <= 540) {
                points = 30;
            } else {
                points = 40;
            }
        }
        return new Factor(points, reason);
    }

    private static Factor frequencyFactor(GivingSummary s) {
        Integer n = s.giftsLast36Months;
        Integer points;
        if (n >= 6) {
            points = 0;
        } else if (n >= 3) {
            points = 8;
        } else if (n == 2) {
            points = 15;
        } else if (n == 1) {
            points = 20;
        } else {
            points = 25;
        }
        String reason = n == 0
            ? 'no gifts in the last 3 years'
            : 'only ' + n + (n == 1 ? ' gift' : ' gifts') + ' in the last 3 years';
        return new Factor(points, reason);
    }

    private static Factor monetaryFactor(GivingSummary s) {
        switch on s.trend {
            when 'Increasing' {
                return new Factor(0, 'giving up ' + s.trendPercent + '% year on year');
            }
            when 'Stable' {
                return new Factor(5, 'giving flat year on year');
            }
            when 'New' {
                return new Factor(5, 'giving only started in the last 12 months');
            }
            when 'Declining' {
                Integer points = s.trendPercent < -50 ? 25 : 15;
                return new Factor(points, 'giving down ' + Math.abs(s.trendPercent) + '% year on year');
            }
            when else {
                return new Factor(25, 'no gifts in the last 2 years');
            }
        }
    }

    /** "<Band>: <top reason>; <second reason>." using only factors that added risk. */
    private static String explain(String band, List<Factor> factors) {
        List<Factor> contributing = new List<Factor>();
        for (Factor f : factors) {
            if (f.points > 0) {
                // Insertion sort by points, descending: at most three items.
                Integer i = 0;
                while (i < contributing.size() && contributing[i].points >= f.points) {
                    i++;
                }
                if (i == contributing.size()) {
                    contributing.add(f);
                } else {
                    contributing.add(i, f);
                }
            }
        }
        if (contributing.isEmpty()) {
            return band + ': gives regularly, gave recently and giving is growing.';
        }
        List<String> reasons = new List<String>();
        for (Integer i = 0; i < Math.min(2, contributing.size()); i++) {
            reasons.add(contributing[i].reason);
        }
        return band + ': ' + String.join(reasons, '; ') + '.';
    }

    @TestVisible
    private static String describeDays(Integer days) {
        if (days < 14) {
            return days + (days == 1 ? ' day' : ' days');
        }
        if (days < 60) {
            return Math.round(days / 7.0) + ' weeks';
        }
        return Math.round(days / 30.44) + ' months';
    }
}
