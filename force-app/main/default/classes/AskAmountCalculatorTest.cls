@IsTest
private class AskAmountCalculatorTest {
    private static final Date AS_OF = Date.newInstance(2026, 6, 30);

    private static GivingSummary summaryOf(List<DonorGift> gifts) {
        return GivingSummary.fromGifts(gifts, AS_OF);
    }

    private static LapseRiskScorer.Result riskOf(String band) {
        LapseRiskScorer.Result r = new LapseRiskScorer.Result();
        r.band = band;
        return r;
    }

    /** Same amount this year and last, so the trend is Stable and no bonus applies. */
    private static GivingSummary stableDonor(Decimal amount) {
        return summaryOf(
            new List<DonorGift>{ new DonorGift(amount, AS_OF.addMonths(-1)), new DonorGift(amount, AS_OF.addMonths(-13)) }
        );
    }

    @IsTest
    static void noGiftsSuggestsDiscoveryConversation() {
        GivingSummary s = summaryOf(new List<DonorGift>());
        LapseRiskScorer.Result risk = LapseRiskScorer.score(s);

        AskAmountCalculator.Result withoutRating = AskAmountCalculator.suggest(s, risk, null, 'CHF');
        AskAmountCalculator.Result withRating = AskAmountCalculator.suggest(s, risk, 'B', 'CHF');

        Assert.isNull(withoutRating.amount);
        Assert.isTrue(withoutRating.reasoning.startsWith('No giving history'));
        Assert.isFalse(withoutRating.reasoning.contains('Capacity'));
        Assert.isTrue(withRating.reasoning.contains('Capacity rating B'));
    }

    @IsTest
    static void lowRiskGetsUpgradeAsk() {
        AskAmountCalculator.Result r = AskAmountCalculator.suggest(stableDonor(10000), riskOf('Low'), 'A', 'CHF');

        Assert.areEqual(15000, r.amount);
        Assert.areEqual(
            '1.5x largest gift in the last 3 years (CHF 10\'000): upgrade ask for a low-risk donor.',
            r.reasoning
        );
    }

    @IsTest
    static void increasingTrendAddsBonus() {
        GivingSummary s = summaryOf(
            new List<DonorGift>{ new DonorGift(2000, AS_OF.addMonths(-1)), new DonorGift(1000, AS_OF.addMonths(-13)) }
        );

        AskAmountCalculator.Result r = AskAmountCalculator.suggest(s, riskOf('Medium'), null, 'CHF');

        Assert.areEqual(2500, r.amount, '1.3 x 2000 = 2600, rounded to the nearest 250');
        Assert.isTrue(r.reasoning.startsWith('1.3x'), r.reasoning);
        Assert.isTrue(r.reasoning.contains('bonus for increasing giving'), r.reasoning);
    }

    @IsTest
    static void highRiskGetsRenewalAsk() {
        AskAmountCalculator.Result r = AskAmountCalculator.suggest(stableDonor(4321), riskOf('High'), null, 'CHF');

        Assert.areEqual(4250, r.amount);
        Assert.isTrue(r.reasoning.contains('renewal ask'), r.reasoning);
    }

    @IsTest
    static void capacityRatingCapsTheAsk() {
        AskAmountCalculator.Result r = AskAmountCalculator.suggest(stableDonor(10000), riskOf('Low'), 'D', 'CHF');

        Assert.areEqual(5000, r.amount);
        Assert.isTrue(r.reasoning.contains('capped at capacity rating D (CHF 5\'000)'), r.reasoning);
    }

    @IsTest
    static void askBelowCapIsNotCapped() {
        AskAmountCalculator.Result r = AskAmountCalculator.suggest(stableDonor(1000), riskOf('Low'), 'C', 'CHF');

        Assert.areEqual(1500, r.amount);
        Assert.isFalse(r.reasoning.contains('capped'));
    }

    @IsTest
    static void fallsBackToLargestEverGiftWhenNothingRecent() {
        GivingSummary s = summaryOf(new List<DonorGift>{ new DonorGift(3000, AS_OF.addMonths(-40)) });

        AskAmountCalculator.Result r = AskAmountCalculator.suggest(s, riskOf('High'), null, 'CHF');

        Assert.areEqual(3000, r.amount);
        Assert.isTrue(r.reasoning.contains('largest gift (over 3 years ago)'), r.reasoning);
    }

    @IsTest
    static void roundsToNaturalFigures() {
        Assert.areEqual(50, AskAmountCalculator.roundToNatural(10), 'Never below one step');
        Assert.areEqual(750, AskAmountCalculator.roundToNatural(740));
        Assert.areEqual(1250, AskAmountCalculator.roundToNatural(1234));
        Assert.areEqual(100000, AskAmountCalculator.roundToNatural(99999));
        Assert.areEqual(125000, AskAmountCalculator.roundToNatural(123456));
    }
}
