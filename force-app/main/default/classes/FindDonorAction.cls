/**
 * Agentforce action: resolves the donor a gift officer names ("Eleanor Hart", "Dr Hart", "Marco")
 * to a single Contact ID, so the briefing and engagement actions can run.
 *
 * Matching: every word the officer typed must appear in the Contact's name or preferred name
 * (case-insensitive). Zero or several matches return found = false with a message the agent
 * relays, so it asks the officer rather than guessing a donor.
 *
 * Bulk-safe: one query for the whole batch (LIKE against a list of patterns), then per-request
 * matching in memory.
 */
public with sharing class FindDonorAction {
    @TestVisible
    private static final Integer MAX_CANDIDATES_LISTED = 5;
    private static final Integer QUERY_LIMIT = 200;

    public class Request {
        @InvocableVariable(
            label='Donor Name'
            description='Full or partial name of the donor as the gift officer said it, e.g. Eleanor Hart, Dr Hart or Marco.'
            required=true
        )
        public String donorName;
    }

    public class Response {
        @InvocableVariable(label='Found' description='True when exactly one donor matches.')
        public Boolean found = false;
        @InvocableVariable(label='Contact ID' description='Salesforce ID of the matched donor Contact. Pass it to the briefing and engagement actions.')
        public Id contactId;
        @InvocableVariable(label='Donor Name' description='Full name of the matched donor.')
        public String donorName;
        @InvocableVariable(label='Household' description='Household of the matched donor.')
        public String householdName;
        @InvocableVariable(label='Message' description='When not found: what to tell or ask the gift officer (lists candidates when several donors match).')
        public String message;
    }

    @InvocableMethod(
        label='Find Donor'
        description='Finds one donor Contact by full or partial name and returns their Contact ID.'
        category='Fundraising'
    )
    public static List<Response> findDonors(List<Request> requests) {
        // 1. Tokenise every request and collect one LIKE pattern per distinct token.
        List<List<String>> tokensPerRequest = new List<List<String>>();
        Set<String> patterns = new Set<String>();
        for (Request req : requests) {
            List<String> tokens = tokenise(req == null ? null : req.donorName);
            tokensPerRequest.add(tokens);
            for (String token : tokens) {
                patterns.add('%' + escapeLike(token) + '%');
            }
        }

        // 2. One query for the batch. User mode: officers only find donors they may see.
        List<Contact> candidates = patterns.isEmpty()
            ? new List<Contact>()
            : [
                  SELECT Id, Name, Preferred_Name__c, Account.Name
                  FROM Contact
                  WHERE Name LIKE :new List<String>(patterns) OR Preferred_Name__c LIKE :new List<String>(patterns)
                  WITH USER_MODE
                  ORDER BY Name
                  LIMIT :QUERY_LIMIT
              ];

        // 3. Match each request in memory: all of its tokens must appear.
        List<Response> responses = new List<Response>();
        for (Integer i = 0; i < requests.size(); i++) {
            responses.add(match(requests[i], tokensPerRequest[i], candidates));
        }
        return responses;
    }

    private static Response match(Request req, List<String> tokens, List<Contact> candidates) {
        Response res = new Response();
        if (tokens.isEmpty()) {
            res.message = 'Which donor is the meeting with? Please give their name.';
            return res;
        }
        String asked = req.donorName.trim();

        List<Contact> matches = new List<Contact>();
        for (Contact c : candidates) {
            String haystack = (c.Name + ' ' + (c.Preferred_Name__c == null ? '' : c.Preferred_Name__c)).toLowerCase();
            Boolean all = true;
            for (String token : tokens) {
                all = all && haystack.contains(token);
            }
            if (all) {
                matches.add(c);
            }
        }

        if (matches.size() == 1) {
            Contact donor = matches[0];
            res.found = true;
            res.contactId = donor.Id;
            res.donorName = donor.Name;
            res.householdName = donor.Account?.Name;
        } else if (matches.isEmpty()) {
            res.message = 'No donor named "' + asked + '" was found. Check the spelling or try their surname.';
        } else {
            List<String> names = new List<String>();
            for (Integer i = 0; i < Math.min(MAX_CANDIDATES_LISTED, matches.size()); i++) {
                names.add(matches[i].Name + (matches[i].Account == null ? '' : ' (' + matches[i].Account.Name + ')'));
            }
            res.message =
                matches.size() +
                ' donors match "' +
                asked +
                '": ' +
                String.join(names, ', ') +
                (matches.size() > MAX_CANDIDATES_LISTED ? ', ...' : '') +
                '. Which one do you mean?';
        }
        return res;
    }

    /** "  Dr  Hart " -> ["dr", "hart"]; null/blank -> []. */
    @TestVisible
    private static List<String> tokenise(String name) {
        List<String> tokens = new List<String>();
        if (String.isBlank(name)) {
            return tokens;
        }
        for (String part : name.trim().toLowerCase().split('\\s+')) {
            if (String.isNotBlank(part)) {
                tokens.add(part);
            }
        }
        return tokens;
    }

    /** Stop a typed % or _ acting as a SOQL wildcard. */
    private static String escapeLike(String token) {
        return token.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }
}
