@IsTest
private class LapseRiskScorerTest {
    private static final Date AS_OF = Date.newInstance(2026, 6, 30);

    private static LapseRiskScorer.Result scoreOf(List<DonorGift> gifts) {
        return LapseRiskScorer.score(GivingSummary.fromGifts(gifts, AS_OF));
    }

    @IsTest
    static void noGiftsIsUnknown() {
        LapseRiskScorer.Result r = scoreOf(new List<DonorGift>());

        Assert.isNull(r.score);
        Assert.areEqual(LapseRiskScorer.BAND_UNKNOWN, r.band);
        Assert.isTrue(r.explanation.contains('prospect'));
    }

    @IsTest
    static void loyalGrowingMonthlyDonorIsLowWithZeroScore() {
        // 24 monthly gifts, the last 12 larger than the previous 12, latest gift today.
        List<DonorGift> gifts = TestDataFactory.giftSeries(150, AS_OF, 12, 1);
        gifts.addAll(TestDataFactory.giftSeries(100, AS_OF.addMonths(-12), 12, 1));

        LapseRiskScorer.Result r = scoreOf(gifts);

        Assert.areEqual(0, r.score);
        Assert.areEqual(LapseRiskScorer.BAND_LOW, r.band);
        Assert.areEqual('Low: gives regularly, gave recently and giving is growing.', r.explanation);
    }

    @IsTest
    static void silentMonthlyDonorIsHigh() {
        // Two years of monthly gifts that stopped 5 months ago: ~5x the usual gap,
        // and only 7 gifts in the last 12 months vs 12 the year before (-42%).
        List<DonorGift> gifts = TestDataFactory.giftSeries(100, AS_OF.addMonths(-5), 24, 1);

        LapseRiskScorer.Result r = scoreOf(gifts);

        Assert.areEqual(50, r.recencyPoints);
        Assert.areEqual(15, r.monetaryPoints);
        Assert.areEqual(65, r.score);
        Assert.areEqual(LapseRiskScorer.BAND_HIGH, r.band);
        Assert.areEqual(
            'High: last gift 5 months ago (usually gives every 4 weeks); giving down 42% year on year.',
            r.explanation
        );
    }

    @IsTest
    static void annualDonorWithinCadenceHasNoRecencyRisk() {
        // Annual donor, last gift 10 months ago: within their normal rhythm.
        LapseRiskScorer.Result r = scoreOf(TestDataFactory.giftSeries(1000, AS_OF.addMonths(-10), 4, 12));
        Assert.areEqual(0, r.recencyPoints);
    }

    @IsTest
    static void recencyRatioBands() {
        // Annual cadence (~365 days); vary how long since the last gift.
        Map<Integer, Integer> expectedPointsByMonthsSilent = new Map<Integer, Integer>{
            16 => 15, // ratio ~1.33
            22 => 30 // ratio ~1.83
        };
        for (Integer monthsSilent : expectedPointsByMonthsSilent.keySet()) {
            LapseRiskScorer.Result r = scoreOf(TestDataFactory.giftSeries(1000, AS_OF.addMonths(-monthsSilent), 3, 12));
            Assert.areEqual(expectedPointsByMonthsSilent.get(monthsSilent), r.recencyPoints, monthsSilent + ' months');
        }
        // Quarterly cadence: 8 months silent is ~2.7x, 12 months is ~4x.
        Assert.areEqual(40, scoreOf(TestDataFactory.giftSeries(200, AS_OF.addMonths(-8), 6, 3)).recencyPoints);
        Assert.areEqual(50, scoreOf(TestDataFactory.giftSeries(200, AS_OF.addMonths(-12), 6, 3)).recencyPoints);
    }

    @IsTest
    static void singleGiftUsesAbsoluteRecency() {
        Assert.areEqual(0, scoreOf(new List<DonorGift>{ new DonorGift(100, AS_OF.addMonths(-3)) }).recencyPoints);
        Assert.areEqual(15, scoreOf(new List<DonorGift>{ new DonorGift(100, AS_OF.addMonths(-9)) }).recencyPoints);
        Assert.areEqual(30, scoreOf(new List<DonorGift>{ new DonorGift(100, AS_OF.addMonths(-15)) }).recencyPoints);
        Assert.areEqual(40, scoreOf(new List<DonorGift>{ new DonorGift(100, AS_OF.addMonths(-20)) }).recencyPoints);
    }

    @IsTest
    static void longSilenceIsAlwaysMaxRecencyAndHigh() {
        LapseRiskScorer.Result r = scoreOf(new List<DonorGift>{ new DonorGift(5000, AS_OF.addMonths(-30)) });

        Assert.areEqual(50, r.recencyPoints, 'Over 2 years of silence');
        Assert.areEqual(20, r.frequencyPoints, 'One gift still inside the 3-year window');
        Assert.areEqual(25, r.monetaryPoints, 'Nothing in the last 2 years');
        Assert.areEqual(LapseRiskScorer.BAND_HIGH, r.band);
    }

    @IsTest
    static void frequencyPoints() {
        Assert.areEqual(0, scoreOf(TestDataFactory.giftSeries(10, AS_OF, 6, 6)).frequencyPoints);
        Assert.areEqual(8, scoreOf(TestDataFactory.giftSeries(10, AS_OF, 3, 6)).frequencyPoints);
        Assert.areEqual(15, scoreOf(TestDataFactory.giftSeries(10, AS_OF, 2, 6)).frequencyPoints);
        Assert.areEqual(20, scoreOf(TestDataFactory.giftSeries(10, AS_OF, 1, 6)).frequencyPoints);
        Assert.areEqual(25, scoreOf(new List<DonorGift>{ new DonorGift(10, AS_OF.addMonths(-40)) }).frequencyPoints);
    }

    @IsTest
    static void monetaryPoints() {
        Date recent = AS_OF.addMonths(-1);
        Date priorYear = AS_OF.addMonths(-13);
        Assert.areEqual(0, scoreOf(new List<DonorGift>{ new DonorGift(200, recent), new DonorGift(100, priorYear) }).monetaryPoints);
        Assert.areEqual(5, scoreOf(new List<DonorGift>{ new DonorGift(100, recent), new DonorGift(100, priorYear) }).monetaryPoints);
        Assert.areEqual(5, scoreOf(new List<DonorGift>{ new DonorGift(100, recent) }).monetaryPoints);
        Assert.areEqual(15, scoreOf(new List<DonorGift>{ new DonorGift(70, recent), new DonorGift(100, priorYear) }).monetaryPoints);
        Assert.areEqual(25, scoreOf(new List<DonorGift>{ new DonorGift(40, recent), new DonorGift(100, priorYear) }).monetaryPoints);
        Assert.areEqual(25, scoreOf(new List<DonorGift>{ new DonorGift(100, AS_OF.addMonths(-26)) }).monetaryPoints);
    }

    @IsTest
    static void explanationLeadsWithLargestFactor() {
        // Declining by 60% (25 pts) and 2 gifts in 3 years (15 pts); recent last gift (0 pts).
        LapseRiskScorer.Result r = scoreOf(
            new List<DonorGift>{ new DonorGift(400, AS_OF.addMonths(-1)), new DonorGift(1000, AS_OF.addMonths(-13)) }
        );
        Assert.areEqual(LapseRiskScorer.BAND_MEDIUM, r.band, 'Score was ' + r.score);
        Assert.areEqual('Medium: giving down 60% year on year; only 2 gifts in the last 3 years.', r.explanation);
    }

    @IsTest
    static void bandThresholds() {
        Assert.areEqual(LapseRiskScorer.BAND_LOW, LapseRiskScorer.bandFor(LapseRiskScorer.MEDIUM_THRESHOLD - 1));
        Assert.areEqual(LapseRiskScorer.BAND_MEDIUM, LapseRiskScorer.bandFor(LapseRiskScorer.MEDIUM_THRESHOLD));
        Assert.areEqual(LapseRiskScorer.BAND_MEDIUM, LapseRiskScorer.bandFor(LapseRiskScorer.HIGH_THRESHOLD - 1));
        Assert.areEqual(LapseRiskScorer.BAND_HIGH, LapseRiskScorer.bandFor(LapseRiskScorer.HIGH_THRESHOLD));
    }

    @IsTest
    static void describeDaysUsesReadableUnits() {
        Assert.areEqual('1 day', LapseRiskScorer.describeDays(1));
        Assert.areEqual('10 days', LapseRiskScorer.describeDays(10));
        Assert.areEqual('3 weeks', LapseRiskScorer.describeDays(21));
        Assert.areEqual('3 months', LapseRiskScorer.describeDays(91));
    }
}
