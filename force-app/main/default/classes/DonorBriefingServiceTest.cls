/**
 * Integration tests: real records through the invocable entry point.
 * Scoring edge cases live in the pure-logic test classes; these tests prove the
 * wiring (queries, filtering, mapping, bulk safety, error handling).
 *
 * Every test runs as a gift officer with only the Lakeside_Gift_Officer permission
 * set, because the service queries WITH USER_MODE (CRUD + FLS enforced).
 */
@IsTest
private class DonorBriefingServiceTest {
    private static final Date AS_OF = Date.newInstance(2026, 6, 30);

    @TestSetup
    static void setup() {
        User officer = TestDataFactory.createGiftOfficer();
        // runAs also separates setup-object DML (User) from data DML, avoiding MIXED_DML_OPERATION.
        System.runAs(officer) {
            createDonors();
        }
    }

    private static void createDonors() {
        // Annual donor, growing: 4'000, 4'000, then 5'000 two months before AS_OF.
        Contact eleanor = TestDataFactory.createDonorWithHousehold('Eleanor', 'Hart', 'C');
        eleanor.Preferred_Name__c = 'Dr Hart';
        update eleanor;
        List<Opportunity> gifts = new List<Opportunity>{
            TestDataFactory.buildGift(eleanor, 5000, Date.newInstance(2026, 4, 30)),
            TestDataFactory.buildGift(eleanor, 4000, Date.newInstance(2025, 4, 30)),
            TestDataFactory.buildGift(eleanor, 4000, Date.newInstance(2024, 4, 30))
        };
        // An open (not yet won) opportunity must not count as a gift.
        Opportunity pending = TestDataFactory.buildGift(eleanor, 50000, Date.newInstance(2026, 6, 1));
        pending.StageName = [SELECT ApiName FROM OpportunityStage WHERE IsClosed = FALSE AND IsActive = TRUE LIMIT 1]
        .ApiName;
        gifts.add(pending);
        insert gifts;

        TestDataFactory.createDonorWithHousehold('Tomas', 'Brenner', null);

        // Monthly donor: 12 recurring gifts of 40, the latest on AS_OF.
        Contact marta = TestDataFactory.createDonorWithHousehold('Marta', 'Frei', 'C');
        TestDataFactory.createGiftSeries(marta, 40, AS_OF, 12, 1, 'Recurring');
    }

    private static User officer() {
        return [SELECT Id FROM User WHERE Email = 'gift.officer@lakeside.example' ORDER BY CreatedDate DESC LIMIT 1];
    }

    private static Contact donorByLastName(String lastName) {
        return [SELECT Id FROM Contact WHERE LastName = :lastName LIMIT 1];
    }

    private static DonorBriefingService.Request request(Id contactId) {
        DonorBriefingService.Request req = new DonorBriefingService.Request();
        req.contactId = contactId;
        req.asOfDate = AS_OF;
        return req;
    }

    @IsTest
    static void buildsBriefingForDonorWithHistory() {
        System.runAs(officer()) {
            Id eleanorId = donorByLastName('Hart').Id;

            Test.startTest();
            DonorBriefingService.Response res = DonorBriefingService.getBriefings(
                new List<DonorBriefingService.Request>{ request(eleanorId) }
            )[0];
            Test.stopTest();

            String cur = UserInfo.getDefaultCurrency();
            Assert.isNull(res.errorMessage);
            Assert.areEqual('Eleanor Hart', res.donorName);
            Assert.areEqual('Dr Hart', res.preferredName);
            Assert.areEqual('Hart Household', res.householdName);
            Assert.areEqual(cur, res.currencyCode);

            Assert.areEqual(13000, res.totalGiven, 'The open opportunity must be excluded');
            Assert.areEqual(3, res.giftCount);
            Assert.areEqual(Date.newInstance(2026, 4, 30), res.lastGiftDate);
            Assert.areEqual(5000, res.lastGiftAmount);
            Assert.areEqual(GivingSummary.TREND_INCREASING, res.givingTrend);
            Assert.areEqual(25, res.givingTrendPercent);

            // Recency 0 (within annual cadence) + frequency 0 (gave in each of the last 3 years) + monetary 0 (increasing).
            Assert.areEqual(0, res.lapseRiskScore);
            Assert.areEqual(LapseRiskScorer.BAND_LOW, res.lapseRiskBand);

            // (1.5 + 0.1) x 5'000 = 8'000, below the C cap of 25'000.
            Assert.areEqual(8000, res.suggestedAskAmount);
            Assert.areEqual(AskAmountCalculator.FREQUENCY_ONE_OFF, res.suggestedAskFrequency);
            Assert.isTrue(res.suggestedAskReasoning.contains('bonus for increasing giving'), res.suggestedAskReasoning);

            Assert.isTrue(res.briefingSummary.startsWith('Briefing: Eleanor Hart'), res.briefingSummary);
            Assert.isTrue(res.briefingSummary.contains(CurrencyFormatter.format(13000, cur) + ' across 3 gifts since 2024'));
            Assert.isTrue(res.briefingSummary.contains('Trend: Increasing (+25% YoY)'), res.briefingSummary);
            Assert.isTrue(res.briefingSummary.contains('Lapse risk: 0/100'), res.briefingSummary);
            Assert.isTrue(res.briefingSummary.contains('Suggested ask: ' + CurrencyFormatter.format(8000, cur)));
        }
    }

    @IsTest
    static void recurringDonorGetsMonthlyAsk() {
        System.runAs(officer()) {
            DonorBriefingService.Response res = DonorBriefingService.getBriefings(
                new List<DonorBriefingService.Request>{ request(donorByLastName('Frei').Id) }
            )[0];

            Assert.areEqual(12, res.giftCount);
            Assert.areEqual(LapseRiskScorer.BAND_LOW, res.lapseRiskBand);
            Assert.areEqual(AskAmountCalculator.FREQUENCY_MONTHLY, res.suggestedAskFrequency, 'Gift_Type__c must reach the scoring');
            Assert.areEqual(60, res.suggestedAskAmount, '1.5 x 40 per month');
            Assert.isTrue(
                res.briefingSummary.contains('Suggested ask: ' + CurrencyFormatter.format(60, res.currencyCode) + ' per month.'),
                res.briefingSummary
            );
        }
    }

    @IsTest
    static void donorWithoutGiftsGetsProspectBriefing() {
        System.runAs(officer()) {
            DonorBriefingService.Response res = DonorBriefingService.getBriefings(
                new List<DonorBriefingService.Request>{ request(donorByLastName('Brenner').Id) }
            )[0];

            Assert.isNull(res.errorMessage);
            Assert.areEqual(0, res.giftCount);
            Assert.isNull(res.lapseRiskScore);
            Assert.areEqual(LapseRiskScorer.BAND_UNKNOWN, res.lapseRiskBand);
            Assert.isNull(res.suggestedAskAmount);
            Assert.isTrue(res.briefingSummary.contains('Giving: no gifts on record.'), res.briefingSummary);
            Assert.isTrue(res.briefingSummary.contains('Lapse risk: n/a'), res.briefingSummary);
            Assert.isTrue(res.briefingSummary.contains('Suggested ask: none'), res.briefingSummary);
        }
    }

    @IsTest
    static void defaultsAsOfDateToToday() {
        System.runAs(officer()) {
            DonorBriefingService.Request req = request(donorByLastName('Hart').Id);
            req.asOfDate = null;

            DonorBriefingService.Response res = DonorBriefingService.getBriefings(
                new List<DonorBriefingService.Request>{ req }
            )[0];

            Assert.isNull(res.errorMessage);
            Assert.areEqual(3, res.giftCount, 'All gifts are in the past relative to today');
        }
    }

    @IsTest
    static void returnsErrorsInsteadOfThrowing() {
        System.runAs(officer()) {
            Contact gone = TestDataFactory.createDonorWithHousehold('Former', 'Supporter', null);
            Id goneId = gone.Id;
            delete gone;

            List<DonorBriefingService.Response> responses = DonorBriefingService.getBriefings(
                new List<DonorBriefingService.Request>{ null, request(null), request(goneId) }
            );

            Assert.areEqual(3, responses.size());
            Assert.areEqual('A donor Contact ID is required.', responses[0].errorMessage);
            Assert.areEqual('A donor Contact ID is required.', responses[1].errorMessage);
            Assert.isTrue(responses[2].errorMessage.startsWith('No donor found with ID'), responses[2].errorMessage);
            Assert.isNull(responses[2].briefingSummary);
        }
    }

    @IsTest
    static void isBulkSafeAndPreservesRequestOrder() {
        System.runAs(officer()) {
            Id eleanorId = donorByLastName('Hart').Id;
            Id tomasId = donorByLastName('Brenner').Id;
            List<DonorBriefingService.Request> requests = new List<DonorBriefingService.Request>();
            for (Integer i = 0; i < 100; i++) {
                requests.add(request(Math.mod(i, 2) == 0 ? eleanorId : tomasId));
            }

            Test.startTest();
            List<DonorBriefingService.Response> responses = DonorBriefingService.getBriefings(requests);
            Integer queriesUsed = Limits.getQueries();
            Test.stopTest();

            Assert.areEqual(100, responses.size());
            Assert.areEqual(2, queriesUsed, 'Query count must not grow with batch size');
            Assert.areEqual('Eleanor Hart', responses[0].donorName);
            Assert.areEqual('Tomas Brenner', responses[1].donorName);
            Assert.areEqual('Eleanor Hart', responses[98].donorName);
        }
    }
}
