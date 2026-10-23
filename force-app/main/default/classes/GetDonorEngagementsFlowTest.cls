/**
 * Tests the Get_Donor_Engagements autolaunched flow through Flow.Interview, the same
 * way the agent invokes it: Contact ID in, text and counts out.
 */
@IsTest
private class GetDonorEngagementsFlowTest {
    private static Map<String, Object> runFlow(Id contactId) {
        Flow.Interview interview = Flow.Interview.createInterview(
            'Get_Donor_Engagements',
            new Map<String, Object>{ 'contactId' => contactId }
        );
        interview.start();
        return new Map<String, Object>{
            'openTasksSummary' => interview.getVariableValue('openTasksSummary'),
            'openTaskCount' => interview.getVariableValue('openTaskCount'),
            'overdueTaskCount' => interview.getVariableValue('overdueTaskCount'),
            'lastEngagementSubject' => interview.getVariableValue('lastEngagementSubject'),
            'lastEngagementDate' => interview.getVariableValue('lastEngagementDate')
        };
    }

    private static Task task(Id contactId, String subject, String status, Date due) {
        return new Task(WhoId = contactId, Subject = subject, Status = status, Priority = 'Normal', ActivityDate = due);
    }

    @IsTest
    static void summarisesOpenOverdueAndLastEngagement() {
        Contact donor = TestDataFactory.createDonorWithHousehold('Eleanor', 'Hart', 'B');
        Date today = Date.today();
        insert new List<Task>{
            task(donor.Id, 'Send programme update', 'Not Started', today.addDays(7)),
            task(donor.Id, 'Confirm site visit', 'In Progress', today.addDays(-3)),
            task(donor.Id, 'Thank-you call', 'Completed', today.addDays(-40)),
            task(donor.Id, 'Stewardship visit', 'Completed', today.addDays(-10))
        };

        Map<String, Object> out = runFlow(donor.Id);

        Assert.areEqual(2, (Decimal) out.get('openTaskCount'));
        Assert.areEqual(1, (Decimal) out.get('overdueTaskCount'));
        List<String> lines = ((String) out.get('openTasksSummary')).trim().split('\n');
        String summary = String.join(lines, '\n');
        Assert.areEqual(2, lines.size(), 'One line per open task: ' + summary);
        Assert.isTrue(lines[0].startsWith('- OVERDUE'), 'Overdue task should come first: ' + summary);
        Assert.isTrue(lines[1].startsWith('- Due '), summary);
        Assert.isTrue(summary.contains('Confirm site visit'), summary);
        Assert.isTrue(summary.contains('Send programme update'), summary);
        Assert.isFalse(summary.contains('Thank-you call'), 'Completed tasks are not open tasks');
        Assert.areEqual('Stewardship visit', out.get('lastEngagementSubject'), 'Most recent completed task');
        Assert.areEqual(today.addDays(-10), out.get('lastEngagementDate'));
    }

    @IsTest
    static void donorWithNoActivityReturnsEmptyResults() {
        Contact donor = TestDataFactory.createDonorWithHousehold('Tomas', 'Brenner', null);
        // Another donor's task must not leak into this donor's results.
        Contact other = TestDataFactory.createDonorWithHousehold('Other', 'Donor', null);
        insert task(other.Id, 'Unrelated task', 'Not Started', Date.today());

        Map<String, Object> out = runFlow(donor.Id);

        Assert.areEqual(0, (Decimal) out.get('openTaskCount'));
        Assert.areEqual(0, (Decimal) out.get('overdueTaskCount'));
        Assert.isTrue(String.isBlank((String) out.get('openTasksSummary')));
        Assert.isNull(out.get('lastEngagementSubject'));
        Assert.isNull(out.get('lastEngagementDate'));
    }
}
