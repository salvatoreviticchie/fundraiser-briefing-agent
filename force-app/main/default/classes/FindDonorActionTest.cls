@IsTest
private class FindDonorActionTest {
    @TestSetup
    static void setup() {
        User officer = TestDataFactory.createGiftOfficer();
        System.runAs(officer) {
            Contact eleanor = TestDataFactory.createDonorWithHousehold('Eleanor', 'Hart', 'B');
            eleanor.Preferred_Name__c = 'Dr Hart';
            update eleanor;
            TestDataFactory.createDonorWithHousehold('Simon', 'Lombardi', null);
            TestDataFactory.createDonorWithHousehold('Simon', 'Steiner', null);
        }
    }

    private static User officer() {
        return [SELECT Id FROM User WHERE Email = 'gift.officer@lakeside.example' ORDER BY CreatedDate DESC LIMIT 1];
    }

    private static FindDonorAction.Response find(String name) {
        FindDonorAction.Request req = new FindDonorAction.Request();
        req.donorName = name;
        return FindDonorAction.findDonors(new List<FindDonorAction.Request>{ req })[0];
    }

    @IsTest
    static void findsByFullPartialAndPreferredName() {
        System.runAs(officer()) {
            Id eleanorId = [SELECT Id FROM Contact WHERE LastName = 'Hart'].Id;

            for (String asked : new List<String>{ 'Eleanor Hart', '  eleanor   HART ', 'Hart', 'Dr Hart', 'Ele' }) {
                FindDonorAction.Response res = find(asked);
                Assert.isTrue(res.found, asked + ': ' + res.message);
                Assert.areEqual(eleanorId, res.contactId, asked);
                Assert.areEqual('Eleanor Hart', res.donorName);
                Assert.areEqual('Hart Household', res.householdName);
                Assert.isNull(res.message);
            }
        }
    }

    @IsTest
    static void severalMatchesAsksWhichOne() {
        System.runAs(officer()) {
            FindDonorAction.Response res = find('Simon');

            Assert.isFalse(res.found);
            Assert.isNull(res.contactId);
            Assert.areEqual(
                '2 donors match "Simon": Simon Lombardi (Lombardi Household), Simon Steiner (Steiner Household). Which one do you mean?',
                res.message
            );
            Assert.isTrue(find('Simon Steiner').found, 'Adding the surname disambiguates');
        }
    }

    @IsTest
    static void listsAtMostFiveCandidates() {
        System.runAs(officer()) {
            List<Contact> many = new List<Contact>();
            Account household = TestDataFactory.createHousehold('Keller Household', true);
            for (Integer i = 0; i < 7; i++) {
                many.add(TestDataFactory.createDonor(household.Id, 'Person' + i, 'Keller', null, false));
            }
            insert many;

            FindDonorAction.Response res = find('Keller');

            Assert.isTrue(res.message.startsWith('7 donors match "Keller"'), res.message);
            Assert.isTrue(res.message.contains(', ...'), 'Truncated list should say so: ' + res.message);
        }
    }

    @IsTest
    static void noMatchAndBlankInput() {
        System.runAs(officer()) {
            FindDonorAction.Response missing = find('Nobody Atall');
            Assert.isFalse(missing.found);
            Assert.isTrue(missing.message.startsWith('No donor named "Nobody Atall"'), missing.message);

            Assert.isTrue(find('   ').message.startsWith('Which donor'));
            Assert.isTrue(find(null).message.startsWith('Which donor'));

            // A typed wildcard must not match everyone.
            Assert.isFalse(find('%').found);
            Assert.isTrue(find('%').message.startsWith('No donor named'));
        }
    }

    @IsTest
    static void handlesNullRequestAndBatchesInOneQuery() {
        System.runAs(officer()) {
            List<FindDonorAction.Request> batch = new List<FindDonorAction.Request>{ null };
            for (String name : new List<String>{ 'Eleanor', 'Lombardi', 'Steiner', 'Hart' }) {
                FindDonorAction.Request req = new FindDonorAction.Request();
                req.donorName = name;
                batch.add(req);
            }

            Test.startTest();
            List<FindDonorAction.Response> responses = FindDonorAction.findDonors(batch);
            Integer queries = Limits.getQueries();
            Test.stopTest();

            Assert.areEqual(1, queries, 'One query regardless of batch size');
            Assert.isFalse(responses[0].found);
            Assert.areEqual('Simon Lombardi', responses[2].donorName);
            Assert.areEqual(responses[1].contactId, responses[4].contactId, 'Eleanor and Hart are the same donor');
        }
    }

    @IsTest
    static void tokenisesWhitespace() {
        Assert.areEqual(new List<String>{ 'dr', 'hart' }, FindDonorAction.tokenise('  Dr \t Hart '));
        Assert.areEqual(0, FindDonorAction.tokenise('').size());
    }
}
