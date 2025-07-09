public class BatchDelete implements Database.Batchable<SObject> {
    public String query;

    // Constructor to accept the query
    public BatchDelete(String q) {
        query = q;
    }

    // Start method to return a QueryLocator
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(query);
    }

    // Execute method to process each batch and Added this line for understanding and hello
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        // Check if the scope is null or empty
        if (scope == null || scope.isEmpty()) {
            System.debug('No records to delete in this batch.');
            return;
        }

        // Log the count of records before deletion
        System.debug('Number of records to delete: ' + scope.size());

        // Perform deletion
        delete scope;

        // Log the count of records after deletion
        System.debug('Number of records deleted: ' + scope.size());

        // Empty the recycle bin
        Database.emptyRecycleBin(scope);
    }

    // Finish method to handle post-batch logic
    public void finish(Database.BatchableContext bc) {
        System.debug('Batch job completed successfully.');
    }
}



