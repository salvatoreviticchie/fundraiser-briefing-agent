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

    private static AskAmountCalculator.Result ask(GivingSummary s, String band, String capacity) {
        return AskAmountCalculator.suggest(s, riskOf(band), capacity, 'CHF');
    }

    /** Same amount this year and last, so the trend is Stable and no bonus applies. */
    private static GivingSummary stableDonor(Decimal amount) {
        return summaryOf(
            new List<DonorGift>{ new DonorGift(amount, AS_OF.addMonths(-1)), new DonorGift(amount, AS_OF.addMonths(-13)) }
        );
    }

    private static GivingSummary monthlyDonor(Decimal amount) {
        List<DonorGift> gifts = new List<DonorGift>();
        for (Integer i = 0; i < 12; i++) {
            gifts.add(new DonorGift(amount, AS_OF.addMonths(-i), DonorGift.TYPE_RECURRING));
        }
        return summaryOf(gifts);
    }

    // ---- 1. No history ---------------------------------------------------------------------

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

    // ---- 2. Lapsed -------------------------------------------------------------------------

    @IsTest
    static void lapsedDonorGetsReactivationAsk() {
        AskAmountCalculator.Result r = ask(summaryOf(new List<DonorGift>{ new DonorGift(3000, AS_OF.addMonths(-40)) }), 'High', null);

        Assert.areEqual(1500, r.amount);
        Assert.areEqual(AskAmountCalculator.FREQUENCY_ONE_OFF, r.frequency);
        Assert.areEqual(
            'Lapsed for 40 months: reactivation ask at 50% of their last gift (CHF 3\'000) to rebuild the relationship.',
            r.reasoning
        );
    }

    // ---- 3. Recurring ----------------------------------------------------------------------

    @IsTest
    static void recurringDonorGetsMonthlyUpgrade() {
        AskAmountCalculator.Result r = ask(monthlyDonor(50), 'Low', null);

        Assert.areEqual(75, r.amount);
        Assert.areEqual(AskAmountCalculator.FREQUENCY_MONTHLY, r.frequency);
        Assert.areEqual('1.5x current monthly gift (CHF 50): upgrade ask for a low-risk donor.', r.reasoning);
    }

    @IsTest
    static void highRiskRecurringDonorIsAskedToContinue() {
        AskAmountCalculator.Result r = ask(monthlyDonor(50), 'High', null);

        Assert.areEqual(50, r.amount);
        Assert.isTrue(r.reasoning.startsWith('1.0x current monthly gift'), r.reasoning);
    }

    @IsTest
    static void monthlyAskIsCappedOnAnnualBasis() {
        // 1.5 x 1'000 = 1'500/month = 18'000/year, above D's 5'000/year -> 416/month, rounded down to 400.
        AskAmountCalculator.Result r = ask(monthlyDonor(1000), 'Low', 'D');

        Assert.areEqual(400, r.amount);
        Assert.isTrue(r.reasoning.contains('capped at capacity rating D (CHF 5\'000 a year)'), r.reasoning);
    }

    // ---- 4. Declining ----------------------------------------------------------------------

    @IsTest
    static void decliningDonorRenewsAtLast12MonthsLevel() {
        GivingSummary s = summaryOf(
            new List<DonorGift>{ new DonorGift(3000, AS_OF.addMonths(-1)), new DonorGift(5250, AS_OF.addMonths(-13)) }
        );

        AskAmountCalculator.Result r = ask(s, 'Low', null);

        Assert.areEqual(3000, r.amount, 'No upgrade on top of a declining trend, even at low risk');
        Assert.areEqual(
            'Giving is down 43% year on year, so renew at the last 12 months\' level (CHF 3\'000) rather than ask for an upgrade.',
            r.reasoning
        );
    }

    @IsTest
    static void decliningDonorWithNothingThisYearRenewsAtLastGift() {
        GivingSummary s = summaryOf(
            new List<DonorGift>{ new DonorGift(2000, AS_OF.addMonths(-14)), new DonorGift(4000, AS_OF.addMonths(-26)) }
        );

        AskAmountCalculator.Result r = ask(s, 'Medium', null);

        Assert.areEqual(2000, r.amount);
        Assert.isTrue(r.reasoning.contains('the level of their last gift (CHF 2\'000)'), r.reasoning);
    }

    // ---- 5. Standard -----------------------------------------------------------------------

    @IsTest
    static void lowRiskGetsUpgradeAsk() {
        AskAmountCalculator.Result r = ask(stableDonor(10000), 'Low', 'A');

        Assert.areEqual(15000, r.amount);
        Assert.areEqual(AskAmountCalculator.FREQUENCY_ONE_OFF, r.frequency);
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

        AskAmountCalculator.Result r = ask(s, 'Medium', null);

        Assert.areEqual(2500, r.amount, '1.3 x 2000 = 2600, rounded to the nearest 250');
        Assert.isTrue(r.reasoning.startsWith('1.3x'), r.reasoning);
        Assert.isTrue(r.reasoning.contains('bonus for increasing giving'), r.reasoning);
    }

    @IsTest
    static void highRiskGetsRenewalAsk() {
        AskAmountCalculator.Result r = ask(stableDonor(4321), 'High', null);

        Assert.areEqual(4250, r.amount);
        Assert.isTrue(r.reasoning.startsWith('1.0x'), r.reasoning);
        Assert.isTrue(r.reasoning.contains('renewal ask'), r.reasoning);
    }

    @IsTest
    static void capacityRatingCapsTheAsk() {
        AskAmountCalculator.Result r = ask(stableDonor(10000), 'Low', 'D');

        Assert.areEqual(5000, r.amount);
        Assert.isTrue(r.reasoning.contains('capped at capacity rating D (CHF 5\'000)'), r.reasoning);
        Assert.isFalse(r.reasoning.contains('a year'), 'One-off caps need no "a year" qualifier');
    }

    @IsTest
    static void askBelowCapIsNotCapped() {
        AskAmountCalculator.Result r = ask(stableDonor(1000), 'Low', 'C');

        Assert.areEqual(1500, r.amount);
        Assert.isFalse(r.reasoning.contains('capped'));
    }

    // ---- Rounding --------------------------------------------------------------------------

    @IsTest
    static void roundsToNaturalFigures() {
        Assert.areEqual(50, AskAmountCalculator.roundToNatural(10, false), 'Never below one step');
        Assert.areEqual(750, AskAmountCalculator.roundToNatural(740, false));
        Assert.areEqual(1250, AskAmountCalculator.roundToNatural(1234, false));
        Assert.areEqual(100000, AskAmountCalculator.roundToNatural(99999, false));
        Assert.areEqual(125000, AskAmountCalculator.roundToNatural(123456, false));
    }

    @IsTest
    static void monthlyAmountsRoundMoreFinely() {
        Assert.areEqual(70, AskAmountCalculator.roundToNatural(72, true));
        Assert.areEqual(425, AskAmountCalculator.roundToNatural(430, true));
        Assert.areEqual(1500, AskAmountCalculator.roundToNatural(1490, true));
    }
}
