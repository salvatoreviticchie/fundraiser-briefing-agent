/**
 * Builds Lakeside Community Trust test records. Each method returns the record(s);
 * pass doInsert = false to adjust fields before inserting yourself.
 */
@IsTest
public class TestDataFactory {
    /** Looked up rather than hard-coded so tests survive renamed or translated stages. */
    public static String wonStage {
        get {
            if (wonStage == null) {
                wonStage = [SELECT ApiName FROM OpportunityStage WHERE IsWon = TRUE AND IsActive = TRUE LIMIT 1]
                .ApiName;
            }
            return wonStage;
        }
        private set;
    }

    public static final String GIFT_OFFICER_PERMSET = 'Lakeside_Gift_Officer';

    /**
     * A gift officer on the most restrictive profile available, plus the project's permission set.
     * Running tests as this user proves the permission set alone is enough to use the agent's actions.
     */
    public static User createGiftOfficer() {
        Profile minimal = [
            SELECT Id
            FROM Profile
            WHERE Name IN ('Minimum Access - Salesforce', 'Standard User')
            ORDER BY Name
            LIMIT 1
        ];
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User officer = new User(
            ProfileId = minimal.Id,
            FirstName = 'Gift',
            LastName = 'Officer',
            Alias = 'giftoff',
            Email = 'gift.officer@lakeside.example',
            Username = 'gift.officer.' + unique + '@lakeside.example',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'de_CH',
            TimeZoneSidKey = 'Europe/Zurich'
        );
        insert officer;
        insert new PermissionSetAssignment(
            AssigneeId = officer.Id,
            PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :GIFT_OFFICER_PERMSET].Id
        );
        return officer;
    }

    public static Account createHousehold(String name, Boolean doInsert) {
        Account household = new Account(Name = name);
        if (doInsert) {
            insert household;
        }
        return household;
    }

    public static Contact createDonor(Id householdId, String firstName, String lastName, String capacityRating, Boolean doInsert) {
        Contact donor = new Contact(
            AccountId = householdId,
            FirstName = firstName,
            LastName = lastName,
            Capacity_Rating__c = capacityRating
        );
        if (doInsert) {
            insert donor;
        }
        return donor;
    }

    /** Household + donor in one call, for tests that only care about the donor. */
    public static Contact createDonorWithHousehold(String firstName, String lastName, String capacityRating) {
        Account household = createHousehold(lastName + ' Household', true);
        return createDonor(household.Id, firstName, lastName, capacityRating, true);
    }

    public static Opportunity buildGift(Contact donor, Decimal amount, Date giftDate) {
        return new Opportunity(
            Name = 'Gift ' + giftDate.format(),
            AccountId = donor.AccountId,
            ContactId = donor.Id,
            Amount = amount,
            CloseDate = giftDate,
            StageName = wonStage,
            Gift_Type__c = 'One_off'
        );
    }

    /**
     * Inserts `count` gifts of `amount`, one every `intervalMonths`, ending on `lastGiftDate`.
     * Handy for "monthly donor", "annual donor" style scenarios.
     */
    public static List<Opportunity> createGiftSeries(
        Contact donor,
        Decimal amount,
        Date lastGiftDate,
        Integer count,
        Integer intervalMonths
    ) {
        List<Opportunity> gifts = new List<Opportunity>();
        for (Integer i = 0; i < count; i++) {
            gifts.add(buildGift(donor, amount, lastGiftDate.addMonths(-i * intervalMonths)));
        }
        insert gifts;
        return gifts;
    }

    public static Donor_Note__c createNote(Id contactId, String noteType, Date noteDate, String body, Boolean doInsert) {
        Donor_Note__c note = new Donor_Note__c(
            Name = noteType + ' ' + noteDate.format(),
            Contact__c = contactId,
            Note_Type__c = noteType,
            Note_Date__c = noteDate,
            Body__c = body
        );
        if (doInsert) {
            insert note;
        }
        return note;
    }

    /** In-memory gift series for pure-logic tests (no DML). */
    public static List<DonorGift> giftSeries(Decimal amount, Date lastGiftDate, Integer count, Integer intervalMonths) {
        List<DonorGift> gifts = new List<DonorGift>();
        for (Integer i = 0; i < count; i++) {
            gifts.add(new DonorGift(amount, lastGiftDate.addMonths(-i * intervalMonths)));
        }
        return gifts;
    }
}
