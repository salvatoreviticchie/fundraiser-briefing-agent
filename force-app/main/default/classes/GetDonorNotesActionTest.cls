@IsTest
private class GetDonorNotesActionTest {
    @TestSetup
    static void setup() {
        User officer = TestDataFactory.createGiftOfficer();
        System.runAs(officer) {
            Contact eleanor = TestDataFactory.createDonorWithHousehold('Eleanor', 'Hart', 'B');
            Date today = Date.newInstance(2026, 6, 30);
            List<Donor_Note__c> notes = new List<Donor_Note__c>();
            for (Integer i = 0; i < 7; i++) {
                notes.add(TestDataFactory.createNote(eleanor.Id, 'Meeting', today.addDays(-10 * i), 'Note number ' + i, false));
            }
            notes.add(TestDataFactory.createNote(eleanor.Id, 'Grant_Report', today.addDays(-1), 'x'.repeat(2000), false));
            insert notes;

            Contact other = TestDataFactory.createDonorWithHousehold('Tomas', 'Brenner', null);
            insert TestDataFactory.createNote(other.Id, 'Call', today, 'Private to Tomas', false);
            TestDataFactory.createDonorWithHousehold('Nina', 'Frei', null); // no notes
        }
    }

    private static User officer() {
        return [SELECT Id FROM User WHERE Email = 'gift.officer@lakeside.example' ORDER BY CreatedDate DESC LIMIT 1];
    }

    private static GetDonorNotesAction.Request request(String lastName, Integer maxNotes) {
        GetDonorNotesAction.Request req = new GetDonorNotesAction.Request();
        req.contactId = [SELECT Id FROM Contact WHERE LastName = :lastName LIMIT 1].Id;
        req.maxNotes = maxNotes;
        return req;
    }

    @IsTest
    static void returnsNewestNotesFirstUpToDefaultLimit() {
        System.runAs(officer()) {
            GetDonorNotesAction.Response res = GetDonorNotesAction.getNotes(
                new List<GetDonorNotesAction.Request>{ request('Hart', null) }
            )[0];

            Assert.areEqual(GetDonorNotesAction.DEFAULT_LIMIT, res.noteCount);
            List<String> blocks = res.notes.split('\n\n');
            Assert.areEqual(5, blocks.size());
            Assert.isTrue(blocks[0].startsWith('[2026-06-30 · Meeting]'), blocks[0]);
            Assert.isTrue(blocks[0].contains('Note number 0'), blocks[0]);
            Assert.isTrue(blocks[1].startsWith('[2026-06-29 · Grant Report]'), 'Picklist API name is made readable: ' + blocks[1]);
            Assert.isFalse(res.notes.contains('Private to Tomas'), 'Other donors\' notes must never leak');
        }
    }

    @IsTest
    static void truncatesLongNotesAndHonoursMaxNotes() {
        System.runAs(officer()) {
            GetDonorNotesAction.Response two = GetDonorNotesAction.getNotes(
                new List<GetDonorNotesAction.Request>{ request('Hart', 2) }
            )[0];
            Assert.areEqual(2, two.noteCount);
            String grantReport = two.notes.split('\n\n')[1];
            Assert.isTrue(grantReport.endsWith('…'), 'Long body should be truncated');
            Assert.isTrue(grantReport.length() < GetDonorNotesAction.MAX_BODY_CHARS + 80, String.valueOf(grantReport.length()));

            GetDonorNotesAction.Response capped = GetDonorNotesAction.getNotes(
                new List<GetDonorNotesAction.Request>{ request('Hart', 500) }
            )[0];
            Assert.areEqual(8, capped.noteCount, 'All 8 notes, since 8 is under the cap of 20');
        }
    }

    @IsTest
    static void handlesNoNotesNullsAndBatches() {
        System.runAs(officer()) {
            GetDonorNotesAction.Request empty = new GetDonorNotesAction.Request();
            List<GetDonorNotesAction.Request> batch = new List<GetDonorNotesAction.Request>{
                request('Frei', null),
                null,
                empty,
                request('Brenner', 0),
                request('Hart', 1)
            };

            Test.startTest();
            List<GetDonorNotesAction.Response> responses = GetDonorNotesAction.getNotes(batch);
            Integer queries = Limits.getQueries();
            Test.stopTest();

            Assert.areEqual(1, queries, 'One query for the whole batch');
            Assert.areEqual(0, responses[0].noteCount);
            Assert.areEqual('', responses[0].notes);
            Assert.areEqual(0, responses[1].noteCount);
            Assert.areEqual(0, responses[2].noteCount);
            Assert.areEqual(1, responses[3].noteCount, 'maxNotes 0 falls back to the default');
            Assert.isTrue(responses[3].notes.contains('Private to Tomas'));
            Assert.areEqual(1, responses[4].noteCount);
        }
    }

    @IsTest
    static void busyDonorCannotCrowdOutAnotherDonorsNotes() {
        System.runAs(officer()) {
            Contact quiet = TestDataFactory.createDonorWithHousehold('Quiet', 'Donor', null);
            insert TestDataFactory.createNote(quiet.Id, 'Call', Date.newInstance(2019, 1, 1), 'Only note, years old', false);

            List<GetDonorNotesAction.Response> responses = GetDonorNotesAction.getNotes(
                new List<GetDonorNotesAction.Request>{ request('Hart', 20), request('Donor', 1) }
            );

            Assert.areEqual(8, responses[0].noteCount);
            Assert.areEqual(1, responses[1].noteCount, 'The quiet donor still gets their note');
            Assert.isTrue(responses[1].notes.contains('Only note, years old'));
        }
    }

    @IsTest
    static void formatsUndatedUntypedNotes() {
        Donor_Note__c note = new Donor_Note__c(Name = 'Loose note', Body__c = '  spaced \n  out  ');
        Assert.areEqual('[undated · Note] Loose note\nspaced out', GetDonorNotesAction.format(note));
    }
}
