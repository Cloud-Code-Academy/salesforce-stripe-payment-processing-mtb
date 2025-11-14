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
     * @description Creates test Contact records with Stripe customer data
     * @param numberOfCustomers The number of Contacts with Stripe data to create
     * @return List<Contact> List of created Contacts with Stripe customer data
     */
    public static List<Contact> createStripeCustomers(Integer numberOfCustomers) {
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < numberOfCustomers; i++) {
            contacts.add(new Contact(
                FirstName = 'Stripe',
                LastName = 'Customer ' + i,
                Email = 'customer' + i + '@example.com',
                Phone = '+987654321' + i,
                Customer_Email__c = 'customer' + i + '@example.com',
                Customer_Name__c = 'Stripe Customer ' + i,
                Customer_Phone__c = '+987654321' + i,
                Stripe_Customer_ID__c = 'cus_test' + i,
                Subscription_Status__c = 'None'
            ));
        }
        insert contacts;
        return contacts;
    }

    /**
     * @description Creates test Stripe_Subscription__c records
     * @param numberOfSubscriptions The number of subscriptions to create
     * @param contactId The Contact Id to associate with subscriptions
     * @return List<Stripe_Subscription__c> List of created subscriptions
     */
    public static List<Stripe_Subscription__c> createStripeSubscriptions(Integer numberOfSubscriptions, Id contactId) {
        List<Stripe_Subscription__c> subscriptions = new List<Stripe_Subscription__c>();
        for (Integer i = 0; i < numberOfSubscriptions; i++) {
            subscriptions.add(new Stripe_Subscription__c(
                Stripe_Customer__c = contactId,
                Stripe_Subscription_ID__c = 'sub_test' + i,
                Status__c = 'active',
                Product_Plan_Name__c = 'Test Plan ' + i
            ));
        }
        insert subscriptions;
        return subscriptions;
    }

    /**
     * @description Creates test Stripe_Invoice__c records
     * @param numberOfInvoices The number of invoices to create
     * @param subscriptionId The Stripe_Subscription__c Id to associate with invoices
     * @param status The status of the invoices
     * @return List<Stripe_Invoice__c> List of created invoices
     */
    public static List<Stripe_Invoice__c> createStripeInvoices(Integer numberOfInvoices, Id subscriptionId, String status) {
        // Get the subscription to find the contact
        Stripe_Subscription__c sub = [SELECT Stripe_Customer__c FROM Stripe_Subscription__c WHERE Id = :subscriptionId LIMIT 1];

        List<Stripe_Invoice__c> invoices = new List<Stripe_Invoice__c>();
        for (Integer i = 0; i < numberOfInvoices; i++) {
            invoices.add(new Stripe_Invoice__c(
                Stripe_Subscription__c = subscriptionId,
                Stripe_Customer__c = sub.Stripe_Customer__c,
                Stripe_Invoice_ID__c = 'inv_test' + i + '_' + System.now().getTime(),
                Amount__c = 29.99,
                Status__c = status,
                Due_Date__c = Date.today()
            ));
        }
        insert invoices;
        return invoices;
    }
}
