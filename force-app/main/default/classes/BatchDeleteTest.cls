@isTest
public class BatchDeleteTest {
    @isTest
    static void testBatchDelete() {
        // Step 1: Create test data
        List<NS_Audit__Netskope_Audit_Log__c> testRecords = new List<NS_Audit__Netskope_Audit_Log__c>();
        for (Integer i = 0; i < 5; i++) { // Create fewer records than the batch size
            NS_Audit__Netskope_Audit_Log__c record = new NS_Audit__Netskope_Audit_Log__c();
            record.Name = 'Test Audit Log ' + i; // Replace 'Name' with a required field for your object
            testRecords.add(record);
        }
        insert testRecords;

        // Step 2: Verify the test data is inserted
        System.assertEquals(5, [SELECT COUNT() FROM NS_Audit__Netskope_Audit_Log__c]);

        // Step 3: Define the query for the batch
        String query = 'SELECT Id FROM NS_Audit__Netskope_Audit_Log__c';

        // Step 4: Instantiate the batch class
        BatchDelete batch = new BatchDelete(query);

        // Step 5: Execute the batch
        Test.startTest();
        Database.executeBatch(batch, 10); // Batch size is larger than the number of records and
        Test.stopTest();

        // Step 6: Verify the records are deleted
        System.assertEquals(0, [SELECT COUNT() FROM NS_Audit__Netskope_Audit_Log__c]);
    }

    @isTest
    static void testEmptyQuery() {
        // Step 1: Define a query that returns no records
        String query = 'SELECT Id FROM NS_Audit__Netskope_Audit_Log__c WHERE Name = \'Nonexistent Audit Log\'';

        // Step 2: Instantiate the batch class
        BatchDelete batch = new BatchDelete(query);

        // Step 3: Execute the batch
        Test.startTest();
        Database.executeBatch(batch, 5); // Batch size of 5
        Test.stopTest();

        // Step 4: Verify no records were deleted
        System.assertEquals(0, [SELECT COUNT() FROM NS_Audit__Netskope_Audit_Log__c]);
    }
}