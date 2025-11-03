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
                Customer_Phone__c = '+987654321' + i,
                Stripe_Customer_ID__c = 'cus_test' + i
            ));
        }
        insert customers;
        return customers;
    }

    /**
     * @description Creates test Stripe Subscription records
     * @param numberOfSubscriptions The number of Stripe Subscriptions to create
     * @param customerId The Stripe Customer Id to associate
     * @return List<Stripe_Subscription__c> List of created Stripe Subscriptions
     */
    public static List<Stripe_Subscription__c> createStripeSubscriptions(Integer numberOfSubscriptions, Id customerId) {
        List<Stripe_Subscription__c> subscriptions = new List<Stripe_Subscription__c>();
        for (Integer i = 0; i < numberOfSubscriptions; i++) {
            subscriptions.add(new Stripe_Subscription__c(
                Stripe_Customer__c = customerId,
                Stripe_Subscription_ID__c = 'sub_test' + i,
                Status__c = 'active',
                Amount__c = 29.99,
                Currency__c = 'USD',
                Current_Period_Start__c = Date.today(),
                Current_Period_End__c = Date.today().addMonths(1)
            ));
        }
        insert subscriptions;
        return subscriptions;
    }

    /**
     * @description Creates test Stripe Invoice records
     * Note: Customer relationship is established through the Subscription relationship,
     * not directly on the Invoice. Invoices relate to Customers via:
     * Invoice → Subscription → Customer
     * @param numberOfInvoices The number of Stripe Invoices to create
     * @param subscriptionId The Stripe Subscription Id to associate
     * @param status The invoice status (default: 'paid')
     * @return List<Stripe_Invoice__c> List of created Stripe Invoices
     */
    public static List<Stripe_Invoice__c> createStripeInvoices(
        Integer numberOfInvoices,
        Id subscriptionId,
        String status
    ) {
        List<Stripe_Invoice__c> invoices = new List<Stripe_Invoice__c>();
        for (Integer i = 0; i < numberOfInvoices; i++) {
            invoices.add(new Stripe_Invoice__c(
                Stripe_Subscription__c = subscriptionId,
                Stripe_Invoice_ID__c = 'inv_test' + i,
                Amount__c = 29.99,
                Status__c = (status != null) ? status : 'paid',
                Dunning_Status__c = (status == 'uncollectible') ? 'exhausted' : 'none',
                Tax_Amount__c = 2.50,
                Discounts_Applied__c = 5.00,
                Due_Date__c = Date.today().addDays(30),
                Period_Start__c = Date.today(),
                Period_End__c = Date.today().addMonths(1)
            ));
        }
        insert invoices;
        return invoices;
    }
}
