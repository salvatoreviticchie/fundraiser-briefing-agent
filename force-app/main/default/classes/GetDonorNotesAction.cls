/**
 * Agentforce action: returns a donor's most recent notes (meeting notes, call notes,
 * grant reports) as agent-ready text.
 *
 * Complements the Data 360 retriever rather than replacing it:
 *   - this action: the latest N notes for one donor, straight from CRM, so a note typed
 *     minutes before a meeting is included and record sharing applies (user mode)
 *   - Data 360 retriever: semantic search across all of a donor's notes ("anything about
 *     legacy giving?"), refreshed on the data stream's schedule
 */
public with sharing class GetDonorNotesAction {
    @TestVisible
    private static final Integer DEFAULT_LIMIT = 5;
    @TestVisible
    private static final Integer MAX_LIMIT = 20;
    /** Keeps the agent prompt small; long grant reports are cut with an ellipsis. */
    @TestVisible
    private static final Integer MAX_BODY_CHARS = 1200;

    public class Request {
        @InvocableVariable(label='Donor Contact ID' description='Salesforce ID of the donor Contact.' required=true)
        public Id contactId;
        @InvocableVariable(label='Max Notes' description='Optional. How many recent notes to return (default 5, max 20).')
        public Integer maxNotes;
    }

    public class Response {
        @InvocableVariable(label='Notes' description='One block per note, newest first: date, type and subject, then the note text. Blank when there are no notes.')
        public String notes = '';
        @InvocableVariable(label='Note Count' description='Number of notes returned.')
        public Integer noteCount = 0;
    }

    @InvocableMethod(
        label='Get Donor Notes'
        description='Returns the most recent meeting notes, call notes and grant reports for a donor, newest first.'
        category='Fundraising'
    )
    public static List<Response> getNotes(List<Request> requests) {
        Set<Id> contactIds = new Set<Id>();
        Integer largestLimit = 0;
        for (Request req : requests) {
            if (req != null && req.contactId != null) {
                contactIds.add(req.contactId);
                largestLimit = Math.max(largestLimit, limitFor(req));
            }
        }

        // One query for the batch. The LIMIT inside a parent-child subquery applies per donor, so a
        // donor with many recent notes can never crowd another donor's notes out of the result.
        Map<Id, List<Donor_Note__c>> notesByDonor = new Map<Id, List<Donor_Note__c>>();
        Integer perDonorLimit = Math.max(1, largestLimit);
        for (Contact donor : [
            SELECT
                Id,
                (
                    SELECT Name, Note_Type__c, Note_Date__c, Body__c
                    FROM Donor_Notes__r
                    ORDER BY Note_Date__c DESC NULLS LAST, CreatedDate DESC
                    LIMIT :perDonorLimit
                )
            FROM Contact
            WHERE Id IN :contactIds
            WITH USER_MODE
        ]) {
            notesByDonor.put(donor.Id, donor.Donor_Notes__r);
        }

        List<Response> responses = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            List<Donor_Note__c> notes = (req == null || req.contactId == null) ? null : notesByDonor.get(req.contactId);
            if (notes != null) {
                List<String> blocks = new List<String>();
                for (Integer i = 0; i < Math.min(limitFor(req), notes.size()); i++) {
                    blocks.add(format(notes[i]));
                }
                res.notes = String.join(blocks, '\n\n');
                res.noteCount = blocks.size();
            }
            responses.add(res);
        }
        return responses;
    }

    private static Integer limitFor(Request req) {
        if (req.maxNotes == null || req.maxNotes < 1) {
            return DEFAULT_LIMIT;
        }
        return Math.min(req.maxNotes, MAX_LIMIT);
    }

    @TestVisible
    private static String format(Donor_Note__c note) {
        String body = note.Body__c == null ? '' : note.Body__c.normalizeSpace();
        if (body.length() > MAX_BODY_CHARS) {
            body = body.left(MAX_BODY_CHARS - 1) + '…';
        }
        String type = note.Note_Type__c == null ? 'Note' : note.Note_Type__c.replace('_', ' ');
        String day = note.Note_Date__c == null ? 'undated' : String.valueOf(note.Note_Date__c);
        return '[' + day + ' · ' + type + '] ' + note.Name + '\n' + body;
    }
}
