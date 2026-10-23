@IsTest
private class GivingSummaryTest {
    private static final Date AS_OF = Date.newInstance(2026, 6, 30);

    @IsTest
    static void emptyHistoryIsInactive() {
        GivingSummary s = GivingSummary.fromGifts(new List<DonorGift>(), AS_OF);

        Assert.isFalse(s.hasGifts());
        Assert.areEqual(0, s.totalGiven);
        Assert.areEqual(GivingSummary.TREND_INACTIVE, s.trend);
        Assert.isNull(s.lastGiftDate);
        Assert.isNull(s.averageIntervalDays);
        Assert.areEqual(0, s.giftsPerYear);
    }

    @IsTest
    static void nullListIsTreatedAsEmpty() {
        GivingSummary s = GivingSummary.fromGifts(null, AS_OF);
        Assert.areEqual(0, s.giftCount);
    }

    @IsTest
    static void computesTotalsLastGiftAndLargest() {
        List<DonorGift> gifts = new List<DonorGift>{
            new DonorGift(500, Date.newInstance(2026, 3, 1)),
            new DonorGift(2000, Date.newInstance(2021, 1, 15)),
            new DonorGift(1000, Date.newInstance(2025, 9, 1))
        };

        GivingSummary s = GivingSummary.fromGifts(gifts, AS_OF);

        Assert.areEqual(3, s.giftCount);
        Assert.areEqual(3500, s.totalGiven);
        Assert.areEqual(Date.newInstance(2021, 1, 15), s.firstGiftDate);
        Assert.areEqual(Date.newInstance(2026, 3, 1), s.lastGiftDate, 'Input order must not matter');
        Assert.areEqual(500, s.lastGiftAmount);
        Assert.areEqual(2000, s.largestGiftEver);
        Assert.areEqual(1000, s.largestGiftLast36Months, 'The 2021 gift is outside the 36-month window');
        Assert.areEqual(2, s.giftsLast36Months);
        Assert.areEqual(Date.newInstance(2026, 3, 1).daysBetween(AS_OF), s.daysSinceLastGift);
    }

    @IsTest
    static void ignoresFutureAndIncompleteGifts() {
        List<DonorGift> gifts = new List<DonorGift>{
            new DonorGift(100, AS_OF),
            new DonorGift(999, AS_OF.addDays(1)),
            new DonorGift(null, AS_OF.addDays(-5)),
            new DonorGift(50, null),
            null
        };

        GivingSummary s = GivingSummary.fromGifts(gifts, AS_OF);

        Assert.areEqual(1, s.giftCount);
        Assert.areEqual(100, s.totalGiven);
        Assert.areEqual(0, s.daysSinceLastGift);
    }

    @IsTest
    static void trendIncreasing() {
        GivingSummary s = GivingSummary.fromGifts(
            new List<DonorGift>{ new DonorGift(1500, AS_OF.addMonths(-2)), new DonorGift(1000, AS_OF.addMonths(-14)) },
            AS_OF
        );
        Assert.areEqual(GivingSummary.TREND_INCREASING, s.trend);
        Assert.areEqual(50, s.trendPercent);
    }

    @IsTest
    static void trendDeclining() {
        GivingSummary s = GivingSummary.fromGifts(
            new List<DonorGift>{ new DonorGift(400, AS_OF.addMonths(-2)), new DonorGift(1000, AS_OF.addMonths(-14)) },
            AS_OF
        );
        Assert.areEqual(GivingSummary.TREND_DECLINING, s.trend);
        Assert.areEqual(-60, s.trendPercent);
    }

    @IsTest
    static void trendStableWithinTenPercent() {
        GivingSummary s = GivingSummary.fromGifts(
            new List<DonorGift>{ new DonorGift(1100, AS_OF.addMonths(-2)), new DonorGift(1000, AS_OF.addMonths(-14)) },
            AS_OF
        );
        Assert.areEqual(GivingSummary.TREND_STABLE, s.trend, 'Exactly +10% is still Stable');
    }

    @IsTest
    static void trendNewWhenNoPriorYear() {
        GivingSummary s = GivingSummary.fromGifts(new List<DonorGift>{ new DonorGift(250, AS_OF.addMonths(-1)) }, AS_OF);
        Assert.areEqual(GivingSummary.TREND_NEW, s.trend);
        Assert.isNull(s.trendPercent);
    }

    @IsTest
    static void trendInactiveWhenOnlyOldGifts() {
        GivingSummary s = GivingSummary.fromGifts(new List<DonorGift>{ new DonorGift(250, AS_OF.addMonths(-30)) }, AS_OF);
        Assert.areEqual(GivingSummary.TREND_INACTIVE, s.trend);
        Assert.areEqual(1, s.giftCount);
    }

    @IsTest
    static void cadenceUsesMostRecentGiftsOnly() {
        // Monthly for the last 12 months, plus one gift 10 years ago that must not distort cadence.
        List<DonorGift> gifts = TestDataFactory.giftSeries(50, AS_OF, 12, 1);
        gifts.add(new DonorGift(50, AS_OF.addYears(-10)));

        GivingSummary s = GivingSummary.fromGifts(gifts, AS_OF);

        Assert.isTrue(
            s.averageIntervalDays >= 28 && s.averageIntervalDays <= 32,
            'Expected a monthly cadence, got ' + s.averageIntervalDays
        );
        Assert.areEqual(4.0, s.giftsPerYear, '12 gifts in 36 months');
    }

    @IsTest
    static void sameDayGiftsDoNotProduceZeroInterval() {
        GivingSummary s = GivingSummary.fromGifts(
            new List<DonorGift>{ new DonorGift(10, AS_OF), new DonorGift(20, AS_OF) },
            AS_OF
        );
        Assert.areEqual(1, s.averageIntervalDays);
    }

    @IsTest
    static void countsGivingYearsSinceFirstGift() {
        GivingSummary everyYear = GivingSummary.fromGifts(TestDataFactory.giftSeries(100, AS_OF, 3, 12), AS_OF);
        Assert.areEqual(3, everyYear.eligibleGivingYears);
        Assert.areEqual(3, everyYear.activeGivingYears);

        GivingSummary skippedYear = GivingSummary.fromGifts(
            new List<DonorGift>{ new DonorGift(100, AS_OF), new DonorGift(100, AS_OF.addMonths(-24)) },
            AS_OF
        );
        Assert.areEqual(3, skippedYear.eligibleGivingYears);
        Assert.areEqual(2, skippedYear.activeGivingYears);

        GivingSummary newDonor = GivingSummary.fromGifts(new List<DonorGift>{ new DonorGift(100, AS_OF.addMonths(-2)) }, AS_OF);
        Assert.areEqual(1, newDonor.eligibleGivingYears, 'Years before the first gift do not count');
        Assert.areEqual(1, newDonor.activeGivingYears);

        GivingSummary none = GivingSummary.fromGifts(new List<DonorGift>(), AS_OF);
        Assert.areEqual(0, none.eligibleGivingYears);
    }

    @IsTest
    static void flagsRecurringDonorFromLatestGift() {
        GivingSummary recurring = GivingSummary.fromGifts(
            new List<DonorGift>{
                new DonorGift(500, AS_OF.addMonths(-20), 'One_off'),
                new DonorGift(40, AS_OF, DonorGift.TYPE_RECURRING)
            },
            AS_OF
        );
        Assert.isTrue(recurring.lastGiftRecurring);

        GivingSummary switchedBack = GivingSummary.fromGifts(
            new List<DonorGift>{
                new DonorGift(40, AS_OF.addMonths(-3), DonorGift.TYPE_RECURRING),
                new DonorGift(500, AS_OF)
            },
            AS_OF
        );
        Assert.isFalse(switchedBack.lastGiftRecurring, 'Untyped gifts are treated as one-off');
        Assert.isFalse(GivingSummary.fromGifts(null, AS_OF).lastGiftRecurring);
    }
}
