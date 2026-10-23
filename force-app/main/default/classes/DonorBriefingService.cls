/**
 * Agentforce action: computes the structured part of a donor meeting briefing.
 *
 * Responsibility split (deliberate):
 *   - This class: data access (bulk-safe, user mode) and assembly.
 *   - GivingSummary / LapseRiskScorer / AskAmountCalculator: pure, unit-tested logic.
 *   - The LLM: turns these facts into prose. It never computes numbers itself.
 *
 * Gifts are Closed Won Opportunities whose primary Contact (Opportunity.ContactId)
 * is the donor. Amounts are in the org currency (CHF for Lakeside Community Trust).
 */
public with sharing class DonorBriefingService {
    public class Request {
        @InvocableVariable(
            label='Donor Contact ID'
            description='Salesforce ID of the donor Contact to prepare a briefing for.'
            required=true
        )
        public Id contactId;

        @InvocableVariable(
            label='As-of Date'
            description='Optional. Compute the briefing as of this date. Defaults to today.'
        )
        public Date asOfDate;
    }

    public class Response {
        @InvocableVariable(label='Donor Name' description='Full name of the donor.')
        public String donorName;
        @InvocableVariable(label='Preferred Name' description='How the donor likes to be addressed, if recorded.')
        public String preferredName;
        @InvocableVariable(label='Household' description='Household account the donor belongs to.')
        public String householdName;
        @InvocableVariable(label='Currency' description='ISO currency code for all amounts.')
        public String currencyCode;

        @InvocableVariable(label='Total Given' description='Lifetime total of received gifts.')
        public Decimal totalGiven;
        @InvocableVariable(label='Gift Count' description='Number of received gifts.')
        public Integer giftCount;
        @InvocableVariable(label='Last Gift Date' description='Date of the most recent gift.')
        public Date lastGiftDate;
        @InvocableVariable(label='Last Gift Amount' description='Amount of the most recent gift.')
        public Decimal lastGiftAmount;
        @InvocableVariable(label='Gifts Per Year' description='Average number of gifts per year over the last 3 years.')
        public Decimal giftsPerYear;
        @InvocableVariable(
            label='Giving Trend'
            description='Last 12 months vs the prior 12: Increasing, Stable, Declining, New or Inactive.'
        )
        public String givingTrend;
        @InvocableVariable(label='Giving Trend Percent' description='Year-on-year change in percent; blank if no baseline.')
        public Decimal givingTrendPercent;

        @InvocableVariable(label='Lapse Risk Score' description='0-100, higher means more likely to stop giving. Blank if no gifts.')
        public Integer lapseRiskScore;
        @InvocableVariable(label='Lapse Risk Band' description='Low, Medium, High or Unknown.')
        public String lapseRiskBand;
        @InvocableVariable(label='Lapse Risk Explanation' description='One-line reason for the lapse-risk score.')
        public String lapseRiskExplanation;

        @InvocableVariable(label='Suggested Ask Amount' description='Recommended amount to ask for. Blank if no history.')
        public Decimal suggestedAskAmount;
        @InvocableVariable(label='Suggested Ask Reasoning' description='How the suggested ask was calculated.')
        public String suggestedAskReasoning;

        @InvocableVariable(
            label='Briefing Summary'
            description='Pre-formatted plain-text summary of all the above, ready to show to the gift officer.'
        )
        public String briefingSummary;
        @InvocableVariable(label='Error Message' description='Set when the briefing could not be produced; other fields are then blank.')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Get Donor Briefing'
        description='Returns giving history, lapse-risk score and a suggested ask amount for a donor Contact.'
        category='Fundraising'
    )
    public static List<Response> getBriefings(List<Request> requests) {
        Set<Id> contactIds = new Set<Id>();
        for (Request req : requests) {
            if (req != null && req.contactId != null) {
                contactIds.add(req.contactId);
            }
        }

        // Two queries regardless of batch size: bulk-safe when Flow or the agent sends many requests.
        Map<Id, Contact> contacts = new Map<Id, Contact>(
            [
                SELECT Id, Name, Preferred_Name__c, Capacity_Rating__c, Account.Name
                FROM Contact
                WHERE Id IN :contactIds
                WITH USER_MODE
            ]
        );
        Map<Id, List<DonorGift>> giftsByContact = new Map<Id, List<DonorGift>>();
        for (Opportunity opp : [
            SELECT ContactId, Amount, CloseDate
            FROM Opportunity
            WHERE ContactId IN :contacts.keySet() AND IsWon = TRUE AND Amount != NULL
            WITH USER_MODE
        ]) {
            if (!giftsByContact.containsKey(opp.ContactId)) {
                giftsByContact.put(opp.ContactId, new List<DonorGift>());
            }
            giftsByContact.get(opp.ContactId).add(new DonorGift(opp.Amount, opp.CloseDate));
        }

        String currencyCode = UserInfo.getDefaultCurrency();
        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            responses.add(buildResponse(req, contacts, giftsByContact, currencyCode));
        }
        return responses;
    }

    private static Response buildResponse(
        Request req,
        Map<Id, Contact> contacts,
        Map<Id, List<DonorGift>> giftsByContact,
        String currencyCode
    ) {
        Response res = new Response();
        if (req == null || req.contactId == null) {
            res.errorMessage = 'A donor Contact ID is required.';
            return res;
        }
        Contact donor = contacts.get(req.contactId);
        if (donor == null) {
            res.errorMessage = 'No donor found with ID ' + req.contactId + ', or you do not have access to it.';
            return res;
        }

        Date asOf = req.asOfDate != null ? req.asOfDate : Date.today();
        GivingSummary summary = GivingSummary.fromGifts(giftsByContact.get(donor.Id), asOf);
        LapseRiskScorer.Result risk = LapseRiskScorer.score(summary);
        AskAmountCalculator.Result ask = AskAmountCalculator.suggest(
            summary,
            risk,
            donor.Capacity_Rating__c,
            currencyCode
        );

        res.donorName = donor.Name;
        res.preferredName = donor.Preferred_Name__c;
        res.householdName = donor.Account?.Name;
        res.currencyCode = currencyCode;
        res.totalGiven = summary.totalGiven;
        res.giftCount = summary.giftCount;
        res.lastGiftDate = summary.lastGiftDate;
        res.lastGiftAmount = summary.lastGiftAmount;
        res.giftsPerYear = summary.giftsPerYear;
        res.givingTrend = summary.trend;
        res.givingTrendPercent = summary.trendPercent;
        res.lapseRiskScore = risk.score;
        res.lapseRiskBand = risk.band;
        res.lapseRiskExplanation = risk.explanation;
        res.suggestedAskAmount = ask.amount;
        res.suggestedAskReasoning = ask.reasoning;
        res.briefingSummary = formatSummary(res, summary);
        return res;
    }

    @TestVisible
    private static String formatSummary(Response res, GivingSummary summary) {
        String cur = res.currencyCode;
        List<String> lines = new List<String>{ 'Briefing: ' + res.donorName };

        if (summary.hasGifts()) {
            lines.add(
                'Giving: ' +
                CurrencyFormatter.format(res.totalGiven, cur) +
                ' across ' +
                res.giftCount +
                (res.giftCount == 1 ? ' gift' : ' gifts') +
                ' since ' +
                summary.firstGiftDate.year() +
                '; last gift ' +
                CurrencyFormatter.format(res.lastGiftAmount, cur) +
                ' on ' +
                String.valueOf(res.lastGiftDate) +
                '.'
            );
            lines.add(
                'Frequency: ' +
                res.giftsPerYear +
                ' gifts/year (last 3 years). Trend: ' +
                res.givingTrend +
                (res.givingTrendPercent == null ? '' : ' (' + signed(res.givingTrendPercent) + '% YoY)') +
                '.'
            );
        } else {
            lines.add('Giving: no gifts on record.');
        }

        lines.add(
            'Lapse risk: ' +
            (res.lapseRiskScore == null ? 'n/a' : res.lapseRiskScore + '/100') +
            '. ' +
            res.lapseRiskExplanation
        );
        lines.add(
            'Suggested ask: ' +
            (res.suggestedAskAmount == null ? 'none' : CurrencyFormatter.format(res.suggestedAskAmount, cur)) +
            '. ' +
            res.suggestedAskReasoning
        );
        return String.join(lines, '\n');
    }

    private static String signed(Decimal value) {
        return (value > 0 ? '+' : '') + value;
    }
}
