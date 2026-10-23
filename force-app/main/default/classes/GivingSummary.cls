/**
 * Descriptive statistics over a donor's gift history, computed "as of" a given
 * date so results are deterministic in tests and reproducible for any past day.
 *
 * Windows (all relative to asOf, end-inclusive):
 *   last 12 months  : (asOf - 12m, asOf]
 *   prior 12 months : (asOf - 24m, asOf - 12m]
 *   last 36 months  : (asOf - 36m, asOf]
 *
 * "Giving years" split the last 36 months into three 12-month windows. A window is
 * eligible once the donor has started giving, and active if it holds at least one gift.
 */
public with sharing class GivingSummary {
    public static final String TREND_INCREASING = 'Increasing';
    public static final String TREND_STABLE = 'Stable';
    public static final String TREND_DECLINING = 'Declining';
    public static final String TREND_NEW = 'New';
    public static final String TREND_INACTIVE = 'Inactive';

    /** +/- this percentage year on year counts as Stable. */
    @TestVisible
    private static final Decimal STABLE_BAND_PERCENT = 10;
    /** Cadence is measured over the most recent N gifts, so old habits don't mask new ones. */
    @TestVisible
    private static final Integer CADENCE_GIFT_WINDOW = 7;

    public Date asOf { get; private set; }
    public Integer giftCount { get; private set; }
    public Decimal totalGiven { get; private set; }
    public Date firstGiftDate { get; private set; }
    public Date lastGiftDate { get; private set; }
    public Decimal lastGiftAmount { get; private set; }
    public Decimal largestGiftEver { get; private set; }
    public Decimal largestGiftLast36Months { get; private set; }
    public Integer giftsLast36Months { get; private set; }
    /** Average gifts per year over the last 36 months. */
    public Decimal giftsPerYear { get; private set; }
    public Decimal givingLast12Months { get; private set; }
    public Decimal givingPrior12Months { get; private set; }
    public String trend { get; private set; }
    /** Year-on-year change in percent; null when there is no prior-year baseline. */
    public Decimal trendPercent { get; private set; }
    /** Typical days between gifts; null with fewer than two gifts. */
    public Integer averageIntervalDays { get; private set; }
    public Integer daysSinceLastGift { get; private set; }
    /** True when the most recent gift was a recurring (monthly) payment. */
    public Boolean lastGiftRecurring { get; private set; }
    /** How many of the last three 12-month windows fall after the donor's first gift (0-3). */
    public Integer eligibleGivingYears { get; private set; }
    /** How many of those eligible windows contain at least one gift. */
    public Integer activeGivingYears { get; private set; }

    public Boolean hasGifts() {
        return giftCount > 0;
    }

    public static GivingSummary fromGifts(List<DonorGift> gifts, Date asOf) {
        GivingSummary s = new GivingSummary();
        s.asOf = asOf;
        s.giftCount = 0;
        s.totalGiven = 0;
        s.giftsLast36Months = 0;
        s.givingLast12Months = 0;
        s.givingPrior12Months = 0;
        s.lastGiftRecurring = false;
        s.eligibleGivingYears = 0;
        s.activeGivingYears = 0;

        // Ignore incomplete records and anything dated after the as-of date.
        List<DonorGift> valid = new List<DonorGift>();
        for (DonorGift g : gifts == null ? new List<DonorGift>() : gifts) {
            if (g != null && g.amount != null && g.giftDate != null && g.giftDate <= asOf) {
                valid.add(g);
            }
        }
        valid.sort();

        Date start12 = asOf.addMonths(-12);
        Date start24 = asOf.addMonths(-24);
        Date start36 = asOf.addMonths(-36);

        for (DonorGift g : valid) {
            s.giftCount++;
            s.totalGiven += g.amount;
            s.largestGiftEver = max(s.largestGiftEver, g.amount);
            if (g.giftDate > start36) {
                s.giftsLast36Months++;
                s.largestGiftLast36Months = max(s.largestGiftLast36Months, g.amount);
            }
            if (g.giftDate > start12) {
                s.givingLast12Months += g.amount;
            } else if (g.giftDate > start24) {
                s.givingPrior12Months += g.amount;
            }
        }

        s.giftsPerYear = (Decimal.valueOf(s.giftsLast36Months) / 3).setScale(1, System.RoundingMode.HALF_UP);

        if (s.giftCount > 0) {
            DonorGift first = valid[0];
            DonorGift last = valid[valid.size() - 1];
            s.firstGiftDate = first.giftDate;
            s.lastGiftDate = last.giftDate;
            s.lastGiftAmount = last.amount;
            s.daysSinceLastGift = last.giftDate.daysBetween(asOf);
            s.averageIntervalDays = recentAverageInterval(valid);
            s.lastGiftRecurring = last.isRecurring();
            s.countGivingYears(valid);
        }

        s.computeTrend();
        return s;
    }

    private void countGivingYears(List<DonorGift> sortedGifts) {
        for (Integer i = 0; i < 3; i++) {
            Date windowEnd = asOf.addMonths(-12 * i);
            Date windowStart = asOf.addMonths(-12 * (i + 1));
            if (firstGiftDate > windowEnd) {
                continue; // the donor hadn't started giving yet, so this year can't count against them
            }
            eligibleGivingYears++;
            for (DonorGift g : sortedGifts) {
                if (g.giftDate > windowStart && g.giftDate <= windowEnd) {
                    activeGivingYears++;
                    break;
                }
            }
        }
    }

    private void computeTrend() {
        if (givingLast12Months == 0 && givingPrior12Months == 0) {
            trend = TREND_INACTIVE;
        } else if (givingPrior12Months == 0) {
            trend = TREND_NEW;
        } else {
            trendPercent = ((givingLast12Months - givingPrior12Months) / givingPrior12Months * 100)
                .setScale(0, System.RoundingMode.HALF_UP);
            if (trendPercent > STABLE_BAND_PERCENT) {
                trend = TREND_INCREASING;
            } else if (trendPercent < -STABLE_BAND_PERCENT) {
                trend = TREND_DECLINING;
            } else {
                trend = TREND_STABLE;
            }
        }
    }

    /** Mean gap between consecutive gifts across the most recent CADENCE_GIFT_WINDOW gifts. */
    private static Integer recentAverageInterval(List<DonorGift> sortedGifts) {
        Integer n = sortedGifts.size();
        if (n < 2) {
            return null;
        }
        Integer startIndex = Math.max(0, n - CADENCE_GIFT_WINDOW);
        Integer intervals = n - 1 - startIndex;
        Integer span = sortedGifts[startIndex].giftDate.daysBetween(sortedGifts[n - 1].giftDate);
        // Floor at 1 day so several gifts on the same day can't cause a divide-by-zero downstream.
        return Math.max(1, Math.round(Decimal.valueOf(span) / intervals));
    }

    private static Decimal max(Decimal current, Decimal candidate) {
        return (current == null || candidate > current) ? candidate : current;
    }
}
