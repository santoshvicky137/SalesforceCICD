public with sharing class AccountandCaseDeletion {
    @AuraEnabled
    public static String deleteAccounts(List<String> accountIds) {
        try {
            // Fetch related cases
            List<Case> casesToDelete = [SELECT Id FROM Case WHERE AccountId IN :accountIds];
            delete casesToDelete;

            // Delete accounts
            List<Account> accountsToDelete = [SELECT Id FROM Account WHERE Id IN :accountIds];
            delete accountsToDelete;

            return 'Accounts and related cases deleted successfully!';
        } catch (DmlException e) {
            return 'Error deleting accounts/cases: ' + e.getMessage();
        }
    }
}
