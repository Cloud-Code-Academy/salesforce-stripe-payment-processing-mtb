@isTest
public class TestDataFactory {
    /**
     * @description Creates a standard user and assigns a specific Permission Set.
     * @param permSetNames The API names of the Permission Sets to assign.
     * @return User The created user with assigned permission sets.
     */
    public static User createUserWithPermissionSets(List<String> permSetNames) {
        // A single profile is sufficient for all test users
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        // Create a unique user to avoid conflicts in tests
        User u = new User(
            Alias = 'testusr',
            Email = 'testuser' + System.currentTimeMillis() + '@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser' + System.currentTimeMillis() + '@testorg.com'
        );
        insert u;

        // Assign the specified permission set
        List<PermissionSet> pss = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :permSetNames
        ];

        List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();

        for (PermissionSet ps : pss) {
            PermissionSetAssignment psa = new PermissionSetAssignment(
                AssigneeId = u.Id,
                PermissionSetId = ps.Id
            );
            psas.add(psa);
        }
        // Insert Permission Set Assignments
        insert psas;

        return u;
    }

    /**
     * @description Creates test Contact records for testing purposes
     * @param numberOfContacts The number of contacts to create
     * @return List<Contact> List of created contacts
     */
    public static List<Contact> createContacts(Integer numberOfContacts) {
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < numberOfContacts; i++) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName = 'Contact ' + i,
                Email = 'test' + i + '@example.com',
                Phone = '+123456789' + i
            ));
        }
        insert contacts;
        return contacts;
    }

    /**
     * @description Creates test Stripe Customer records
     * @param numberOfCustomers The number of Stripe Customers to create
     * @param contactId The Contact Id to associate (optional)
     * @return List<Stripe_Customer__c> List of created Stripe Customers
     */
    public static List<Stripe_Customer__c> createStripeCustomers(Integer numberOfCustomers, Id contactId) {
        List<Stripe_Customer__c> customers = new List<Stripe_Customer__c>();
        for (Integer i = 0; i < numberOfCustomers; i++) {
            customers.add(new Stripe_Customer__c(
                Contact__c = contactId,
                Customer_Email__c = 'customer' + i + '@example.com',
                Customer_Phone__c = '+987654321' + i
            ));
        }
        insert customers;
        return customers;
    }
}
