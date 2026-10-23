@IsTest
private class LapseRiskScorerTest {
    private static final Date AS_OF = Date.newInstance(2026, 6, 30);

    private static LapseRiskScorer.Result scoreOf(List<DonorGift> gifts) {
        return LapseRiskScorer.score(GivingSummary.fromGifts(gifts, AS_OF));
    }

    private static List<DonorGift> gifts(Decimal amount, List<Integer> monthsAgo) {
        List<DonorGift> result = new List<DonorGift>();
        for (Integer m : monthsAgo) {
            result.add(new DonorGift(amount, AS_OF.addMonths(-m)));
        }
        return result;
    }

    @IsTest
    static void noGiftsIsUnknown() {
        LapseRiskScorer.Result r = scoreOf(new List<DonorGift>());

        Assert.isNull(r.score);
        Assert.areEqual(LapseRiskScorer.BAND_UNKNOWN, r.band);
        Assert.isTrue(r.explanation.contains('prospect'));
    }

    // ---- Recency ---------------------------------------------------------------------------

    @IsTest
    static void silentMonthlyDonorIsHigh() {
        // Two years of monthly gifts that stopped 5 months ago: ~5x the usual gap,
        // and only 7 gifts in the last 12 months vs 12 the year before (-42%).
        LapseRiskScorer.Result r = scoreOf(TestDataFactory.giftSeries(100, AS_OF.addMonths(-5), 24, 1));

        Assert.areEqual(50, r.recencyPoints);
        Assert.areEqual(0, r.frequencyPoints, 'Gave in each of the last 3 years');
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
        Assert.areEqual(15, scoreOf(TestDataFactory.giftSeries(1000, AS_OF.addMonths(-16), 3, 12)).recencyPoints, '~1.33x');
        Assert.areEqual(30, scoreOf(TestDataFactory.giftSeries(1000, AS_OF.addMonths(-22), 3, 12)).recencyPoints, '~1.83x');
        // Quarterly cadence: 8 months silent is ~2.7x, 12 months is ~4x.
        Assert.areEqual(40, scoreOf(TestDataFactory.giftSeries(200, AS_OF.addMonths(-8), 6, 3)).recencyPoints);
        Assert.areEqual(50, scoreOf(TestDataFactory.giftSeries(200, AS_OF.addMonths(-12), 6, 3)).recencyPoints);
    }

    @IsTest
    static void singleGiftUsesAbsoluteRecency() {
        Assert.areEqual(0, scoreOf(gifts(100, new List<Integer>{ 3 })).recencyPoints);
        Assert.areEqual(15, scoreOf(gifts(100, new List<Integer>{ 9 })).recencyPoints);
        Assert.areEqual(30, scoreOf(gifts(100, new List<Integer>{ 15 })).recencyPoints);
        Assert.areEqual(40, scoreOf(gifts(100, new List<Integer>{ 20 })).recencyPoints);
    }

    @IsTest
    static void longSilenceIsAlwaysMaxRecencyAndHigh() {
        LapseRiskScorer.Result r = scoreOf(gifts(5000, new List<Integer>{ 30 }));

        Assert.areEqual(50, r.recencyPoints, 'Over 2 years of silence');
        Assert.areEqual(18, r.frequencyPoints, 'Gave in only 1 of the last 3 years');
        Assert.areEqual(25, r.monetaryPoints, 'Nothing in the last 2 years');
        Assert.areEqual(LapseRiskScorer.BAND_HIGH, r.band);
        Assert.areEqual('High: last gift 30 months ago; no gifts in the last 2 years.', r.explanation);
    }

    // ---- Frequency (giving consistency) ----------------------------------------------------

    @IsTest
    static void annualDonorGivingEveryYearHasNoFrequencyRisk() {
        LapseRiskScorer.Result r = scoreOf(gifts(1000, new List<Integer>{ 0, 12, 24 }));
        Assert.areEqual(0, r.frequencyPoints, 'Three gifts in three years is perfect for an annual donor');
    }

    @IsTest
    static void frequencyPenalisesMissedYears() {
        Assert.areEqual(10, scoreOf(gifts(10, new List<Integer>{ 0, 24 })).frequencyPoints, 'Skipped one year');
        Assert.areEqual(18, scoreOf(gifts(10, new List<Integer>{ 30 })).frequencyPoints, 'Gave in 1 of 3 years');
        Assert.areEqual(25, scoreOf(gifts(10, new List<Integer>{ 40 })).frequencyPoints, 'Nothing in 3 years');
    }

    @IsTest
    static void newDonorIsNotPenalisedForYearsBeforeTheyStarted() {
        Assert.areEqual(0, scoreOf(gifts(10, new List<Integer>{ 1 })).frequencyPoints);
    }

    // ---- Monetary --------------------------------------------------------------------------

    @IsTest
    static void monetaryPoints() {
        Assert.areEqual(0, scoreOf(new List<DonorGift>{ new DonorGift(200, AS_OF.addMonths(-1)), new DonorGift(100, AS_OF.addMonths(-13)) }).monetaryPoints);
        Assert.areEqual(5, scoreOf(gifts(100, new List<Integer>{ 1, 13 })).monetaryPoints, 'Stable');
        Assert.areEqual(5, scoreOf(gifts(100, new List<Integer>{ 1 })).monetaryPoints, 'New');
        Assert.areEqual(15, scoreOf(new List<DonorGift>{ new DonorGift(70, AS_OF.addMonths(-1)), new DonorGift(100, AS_OF.addMonths(-13)) }).monetaryPoints);
        Assert.areEqual(25, scoreOf(new List<DonorGift>{ new DonorGift(40, AS_OF.addMonths(-1)), new DonorGift(100, AS_OF.addMonths(-13)) }).monetaryPoints);
        Assert.areEqual(25, scoreOf(gifts(100, new List<Integer>{ 26 })).monetaryPoints, 'Inactive');
    }

    // ---- Explanations ----------------------------------------------------------------------

    @IsTest
    static void riskExplanationLeadsWithLargestFactor() {
        // Down 60% (25 pts), skipped a year (10 pts), last gift recent (0 pts).
        LapseRiskScorer.Result r = scoreOf(
            new List<DonorGift>{
                new DonorGift(400, AS_OF.addMonths(-1)),
                new DonorGift(1000, AS_OF.addMonths(-13)),
                new DonorGift(1000, AS_OF.addMonths(-37))
            }
        );
        Assert.areEqual(35, r.score);
        Assert.areEqual(LapseRiskScorer.BAND_MEDIUM, r.band);
        Assert.areEqual('Medium: giving down 60% year on year; gave in only 2 of the last 3 years.', r.explanation);
    }

    @IsTest
    static void lowBandExplainsWhatIsGoingWell() {
        // 24 monthly gifts, last one today, giving up 50% year on year.
        List<DonorGift> history = TestDataFactory.giftSeries(150, AS_OF, 12, 1);
        history.addAll(TestDataFactory.giftSeries(100, AS_OF.addMonths(-12), 12, 1));

        LapseRiskScorer.Result r = scoreOf(history);

        Assert.areEqual(0, r.score);
        Assert.areEqual(LapseRiskScorer.BAND_LOW, r.band);
        Assert.isTrue(r.explanation.startsWith('Low: last gift today, in line with their usual rhythm (every '), r.explanation);
        Assert.isTrue(r.explanation.endsWith('gave in each of the last 2 years; giving up 50% year on year.'), r.explanation);
    }

    @IsTest
    static void lowBandOmitsSmallRiskFactors() {
        // Stable annual donor: monetary scores 5, which is below the watch threshold.
        LapseRiskScorer.Result r = scoreOf(gifts(100, new List<Integer>{ 1, 13 }));

        Assert.areEqual(5, r.score);
        Assert.areEqual(
            'Low: last gift 4 weeks ago, in line with their usual rhythm (every 12 months); gave in each of the last 2 years.',
            r.explanation
        );
    }

    @IsTest
    static void lowBandFlagsOneFactorWorthWatching() {
        LapseRiskScorer.Result declining = scoreOf(
            new List<DonorGift>{ new DonorGift(800, AS_OF.addMonths(-1)), new DonorGift(1000, AS_OF.addMonths(-13)) }
        );
        Assert.areEqual(LapseRiskScorer.BAND_LOW, declining.band, 'Score was ' + declining.score);
        Assert.areEqual(
            'Low: last gift 4 weeks ago, in line with their usual rhythm (every 12 months); gave in each of the last 2 years; watch: giving down 20% year on year.',
            declining.explanation
        );

        LapseRiskScorer.Result quiet = scoreOf(gifts(100, new List<Integer>{ 9 }));
        Assert.areEqual(LapseRiskScorer.BAND_LOW, quiet.band, 'Score was ' + quiet.score);
        Assert.areEqual('Low: watch: last gift 9 months ago.', quiet.explanation);
    }

    @IsTest
    static void bandThresholds() {
        Assert.areEqual(LapseRiskScorer.BAND_LOW, LapseRiskScorer.bandFor(LapseRiskScorer.MEDIUM_THRESHOLD - 1));
        Assert.areEqual(LapseRiskScorer.BAND_MEDIUM, LapseRiskScorer.bandFor(LapseRiskScorer.MEDIUM_THRESHOLD));
        Assert.areEqual(LapseRiskScorer.BAND_MEDIUM, LapseRiskScorer.bandFor(LapseRiskScorer.HIGH_THRESHOLD - 1));
        Assert.areEqual(LapseRiskScorer.BAND_HIGH, LapseRiskScorer.bandFor(LapseRiskScorer.HIGH_THRESHOLD));
    }

    @IsTest
    static void durationsUseReadableUnits() {
        Assert.areEqual('1 day', LapseRiskScorer.describeDuration(1));
        Assert.areEqual('10 days', LapseRiskScorer.describeDuration(10));
        Assert.areEqual('3 weeks', LapseRiskScorer.describeDuration(21));
        Assert.areEqual('3 months', LapseRiskScorer.describeDuration(91));
        Assert.areEqual('today', LapseRiskScorer.describeAgo(0));
        Assert.areEqual('10 days ago', LapseRiskScorer.describeAgo(10));
    }
}
