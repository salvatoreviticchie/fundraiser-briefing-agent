// Removes every record created by the demo data generator (identified by Lakeside_Id__c).
// Children first; Donor_Note__c is also cascade-deleted with its Contact (master-detail).
delete [SELECT Id FROM Task WHERE Lakeside_Id__c != null];
delete [SELECT Id FROM Opportunity WHERE Lakeside_Id__c != null];
delete [SELECT Id FROM Donor_Note__c WHERE Lakeside_Id__c != null];
delete [SELECT Id FROM Contact WHERE Lakeside_Id__c != null];
delete [SELECT Id FROM Account WHERE Lakeside_Id__c != null];
System.debug('Lakeside demo data removed.');
