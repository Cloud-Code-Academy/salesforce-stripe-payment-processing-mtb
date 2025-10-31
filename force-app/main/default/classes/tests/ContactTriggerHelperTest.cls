@isTest
public class ContactTriggerHelperTest {
    private static User testUser;

    @TestSetup
    static void setupTestData() {
        // Create test user with necessary permission sets
        testUser = TestDataFactory.createUserWithPermissionSets(
            new List<String>{'Stripe_API_Access', 'CustomMetadataAccess', 'Stripe_Integration_User'}
        );
    }

    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'testuser%@testorg.com' LIMIT 1];
    }

    /**
     * @description Tests that inserting a Contact with both FirstName and LastName
     *              successfully creates a Stripe Customer record with properly formatted name
     */
    @IsTest
    static void processContactAfterInsert_insertContactWithLastNameAndFirstName_success() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create test data
            Contact cont = new Contact(
                FirstName = 'Test',
                LastName = 'Testov',
                Email = 'testovtest@gmail.com.au',
                Phone = '423423423423423'
            );

            Test.startTest();
            insert cont;
            Test.stopTest();

            // Verify the result
            List<Stripe_Customer__c> insertedStripeCustomers = [
                SELECT Customer_Name__c, Customer_Email__c, Customer_Phone__c, Contact__c
                FROM Stripe_Customer__c
                WHERE Contact__c = :cont.Id
            ];
            System.assertEquals(1, insertedStripeCustomers.size(), 'Stripe Customer should be inserted');
            System.assertEquals(cont.LastName + ' ' + cont.FirstName, insertedStripeCustomers[0].Customer_Name__c, 'Customer name should be LastName FirstName');
            System.assertEquals(cont.Email, insertedStripeCustomers[0].Customer_Email__c, 'Customer email should match Contact email');
            System.assertEquals(cont.Phone, insertedStripeCustomers[0].Customer_Phone__c, 'Customer phone should match Contact phone');
            System.assertEquals(cont.Id, insertedStripeCustomers[0].Contact__c, 'Customer should be linked to Contact');
        }
    }

    /**
     * @description Tests that inserting a Contact with only LastName
     *              successfully creates a Stripe Customer record with LastName only
     */
    @IsTest
    static void processContactAfterInsert_insertContactWithOnlyLastName_success() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create test data
            Contact cont = new Contact(
                LastName = 'Testov',
                Email = 'testovtest@gmail.com.au',
                Phone = '423423423423423'
            );

            Test.startTest();
            insert cont;
            Test.stopTest();

            // Verify the result
            List<Stripe_Customer__c> insertedStripeCustomers = [
                SELECT Customer_Name__c, Customer_Email__c, Customer_Phone__c, Contact__c
                FROM Stripe_Customer__c
                WHERE Contact__c = :cont.Id
            ];
            System.assertEquals(1, insertedStripeCustomers.size(), 'Stripe Customer should be inserted');
            System.assertEquals(cont.LastName, insertedStripeCustomers[0].Customer_Name__c, 'Customer name should be LastName only');
            System.assertEquals(cont.Email, insertedStripeCustomers[0].Customer_Email__c, 'Customer email should match Contact email');
            System.assertEquals(cont.Phone, insertedStripeCustomers[0].Customer_Phone__c, 'Customer phone should match Contact phone');
            System.assertEquals(cont.Id, insertedStripeCustomers[0].Contact__c, 'Customer should be linked to Contact');
        }
    }

    /**
     * @description Tests that inserting a Contact without phone
     *              successfully creates a Stripe Customer record with null phone
     */
    @IsTest
    static void processContactAfterInsert_insertContactWithoutPhone_success() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create test data without phone (email is required for Stripe_Customer__c)
            Contact cont = new Contact(
                LastName = 'MinimalContact',
                Email = 'minimal@example.com'
            );

            Test.startTest();
            insert cont;
            Test.stopTest();

            // Verify the result
            List<Stripe_Customer__c> insertedStripeCustomers = [
                SELECT Customer_Name__c, Customer_Email__c, Customer_Phone__c, Contact__c
                FROM Stripe_Customer__c
                WHERE Contact__c = :cont.Id
            ];
            System.assertEquals(1, insertedStripeCustomers.size(), 'Stripe Customer should be inserted');
            System.assertEquals(cont.LastName, insertedStripeCustomers[0].Customer_Name__c, 'Customer name should be LastName');
            System.assertEquals(cont.Email, insertedStripeCustomers[0].Customer_Email__c, 'Customer email should match Contact email');
            System.assertEquals(null, insertedStripeCustomers[0].Customer_Phone__c, 'Customer phone should be null when not provided');
        }
    }

    /**
     * @description Tests that inserting multiple Contacts in bulk
     *              successfully creates corresponding Stripe Customer records
     */
    @IsTest
    static void processContactAfterInsert_bulkInsertContacts_success() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create test data
            List<Contact> contacts = new List<Contact>();
            for (Integer i = 0; i < 200; i++) {
                contacts.add(new Contact(
                    FirstName = 'BulkTest',
                    LastName = 'Contact' + i,
                    Email = 'bulktest' + i + '@example.com',
                    Phone = '+1234567' + String.valueOf(i).leftPad(3, '0')
                ));
            }

            Test.startTest();
            insert contacts;
            Test.stopTest();

            // Verify the result
            List<Stripe_Customer__c> insertedStripeCustomers = [
                SELECT Id, Contact__c
                FROM Stripe_Customer__c
                WHERE Contact__c IN :contacts
            ];
            System.assertEquals(200, insertedStripeCustomers.size(), 'All 200 Stripe Customers should be created for bulk insert');

            // Verify each contact has exactly one Stripe Customer
            Set<Id> contactIds = new Set<Id>();
            for (Stripe_Customer__c customer : insertedStripeCustomers) {
                System.assert(!contactIds.contains(customer.Contact__c), 'Each Contact should have exactly one Stripe Customer');
                contactIds.add(customer.Contact__c);
            }
        }
    }

    /**
     * @description Tests that inserting Contacts with special characters in names
     *              successfully creates Stripe Customer records with properly handled names
     */
    @IsTest
    static void processContactAfterInsert_insertContactWithSpecialCharacters_success() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create test data with special characters
            Contact cont = new Contact(
                FirstName = 'José María',
                LastName = 'O\'Brien-Smith',
                Email = 'jose.obrien@example.com',
                Phone = '+1-555-123-4567'
            );

            Test.startTest();
            insert cont;
            Test.stopTest();

            // Verify the result
            List<Stripe_Customer__c> insertedStripeCustomers = [
                SELECT Customer_Name__c, Customer_Email__c, Customer_Phone__c
                FROM Stripe_Customer__c
                WHERE Contact__c = :cont.Id
            ];
            System.assertEquals(1, insertedStripeCustomers.size(), 'Stripe Customer should be inserted with special characters');
            System.assertEquals(cont.LastName + ' ' + cont.FirstName, insertedStripeCustomers[0].Customer_Name__c, 'Customer name should preserve special characters');
        }
    }
}