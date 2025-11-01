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
            Assert.areEqual(1, insertedStripeCustomers.size(), 'Stripe Customer should be inserted');
            Assert.areEqual(cont.LastName + ' ' + cont.FirstName, insertedStripeCustomers[0].Customer_Name__c, 'Customer name should be LastName FirstName');
            Assert.areEqual(cont.Email, insertedStripeCustomers[0].Customer_Email__c, 'Customer email should match Contact email');
            Assert.areEqual(cont.Phone, insertedStripeCustomers[0].Customer_Phone__c, 'Customer phone should match Contact phone');
            Assert.areEqual(cont.Id, insertedStripeCustomers[0].Contact__c, 'Customer should be linked to Contact');
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
            Assert.areEqual(1, insertedStripeCustomers.size(), 'Stripe Customer should be inserted');
            Assert.areEqual(cont.LastName, insertedStripeCustomers[0].Customer_Name__c, 'Customer name should be LastName only');
            Assert.areEqual(cont.Email, insertedStripeCustomers[0].Customer_Email__c, 'Customer email should match Contact email');
            Assert.areEqual(cont.Phone, insertedStripeCustomers[0].Customer_Phone__c, 'Customer phone should match Contact phone');
            Assert.areEqual(cont.Id, insertedStripeCustomers[0].Contact__c, 'Customer should be linked to Contact');
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
            Assert.areEqual(1, insertedStripeCustomers.size(), 'Stripe Customer should be inserted');
            Assert.areEqual(cont.LastName, insertedStripeCustomers[0].Customer_Name__c, 'Customer name should be LastName');
            Assert.areEqual(cont.Email, insertedStripeCustomers[0].Customer_Email__c, 'Customer email should match Contact email');
            Assert.areEqual(null, insertedStripeCustomers[0].Customer_Phone__c, 'Customer phone should be null when not provided');
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
            Assert.areEqual(200, insertedStripeCustomers.size(), 'All 200 Stripe Customers should be created for bulk insert');

            // Verify each contact has exactly one Stripe Customer
            Set<Id> contactIds = new Set<Id>();
            for (Stripe_Customer__c customer : insertedStripeCustomers) {
                Assert.isTrue(!contactIds.contains(customer.Contact__c), 'Each Contact should have exactly one Stripe Customer');
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
            Assert.areEqual(1, insertedStripeCustomers.size(), 'Stripe Customer should be inserted with special characters');
            Assert.areEqual(cont.LastName + ' ' + cont.FirstName, insertedStripeCustomers[0].Customer_Name__c, 'Customer name should preserve special characters');
        }
    }

    // ========== High Priority Error Handling Tests ==========

    /**
     * @description Tests that the helper gracefully handles null newList parameter
     */
    @IsTest
    static void processContactAfterInsert_nullNewList_noError() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.startTest();
            // Should not throw exception when called with null
            ContactTriggerHelper.processContactAfterInsert(null);
            Test.stopTest();

            // Verify no Stripe Customers were created
            List<Stripe_Customer__c> customers = [SELECT Id FROM Stripe_Customer__c];
            Assert.areEqual(0, customers.size(), 'No Stripe Customers should be created for null list');
        }
    }

    /**
     * @description Tests that the helper gracefully handles empty newList parameter
     */
    @IsTest
    static void processContactAfterInsert_emptyNewList_noError() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.startTest();
            // Should not throw exception when called with empty list
            ContactTriggerHelper.processContactAfterInsert(new List<Contact>());
            Test.stopTest();

            // Verify no Stripe Customers were created
            List<Stripe_Customer__c> customers = [SELECT Id FROM Stripe_Customer__c];
            Assert.areEqual(0, customers.size(), 'No Stripe Customers should be created for empty list');
        }
    }

    /**
     * @description Tests that Contacts without email are skipped (email is required for Stripe_Customer__c)
     *              This test verifies the helper handles missing required fields gracefully
     */
    @IsTest
    static void processContactAfterInsert_contactWithoutEmail_skipped() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create Contact without email
            Contact cont = new Contact(
                FirstName = 'No',
                LastName = 'Email',
                Phone = '+1234567890'
            );

            Test.startTest();
            insert cont;
            Test.stopTest();

            // Since Customer_Email__c is required on Stripe_Customer__c,
            // the helper should skip this contact and not attempt to create a Stripe Customer
            List<Stripe_Customer__c> insertedStripeCustomers = [
                SELECT Id
                FROM Stripe_Customer__c
                WHERE Contact__c = :cont.Id
            ];

            // Verify no customer was created (contact without email is skipped)
            Assert.areEqual(0, insertedStripeCustomers.size(),
                'No Stripe Customer should be created for Contact without email');
        }
    }

    /**
     * @description Tests that Contacts without any name are handled gracefully
     */
    @IsTest
    static void processContactAfterInsert_contactWithoutName_handledGracefully() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create Contact with only email (no FirstName or LastName)
            // Note: LastName is required by Salesforce, so this test demonstrates
            // how the helper would handle a Contact with minimal data
            Contact cont = new Contact(
                LastName = 'MinimalData',
                Email = 'minimal@example.com'
            );

            Test.startTest();
            insert cont;
            Test.stopTest();

            // Verify the result - should create customer with LastName as name
            List<Stripe_Customer__c> insertedStripeCustomers = [
                SELECT Customer_Name__c
                FROM Stripe_Customer__c
                WHERE Contact__c = :cont.Id
            ];
            Assert.areEqual(1, insertedStripeCustomers.size(), 'Stripe Customer should be created');
            Assert.areEqual('MinimalData', insertedStripeCustomers[0].Customer_Name__c, 'Customer name should be LastName when FirstName is null');
        }
    }

    /**
     * @description Tests bulk insert with mixed valid and potentially problematic records
     *              Verifies that some successful records don't prevent others from processing
     */
    @IsTest
    static void processContactAfterInsert_mixedValidInvalidRecords_partialSuccess() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create mix of valid and edge-case contacts
            List<Contact> contacts = new List<Contact>();

            // Valid contacts
            for (Integer i = 0; i < 5; i++) {
                contacts.add(new Contact(
                    FirstName = 'Valid',
                    LastName = 'Contact' + i,
                    Email = 'valid' + i + '@example.com',
                    Phone = '+123456789' + i
                ));
            }

            // Edge case: Contact without phone (should still work)
            contacts.add(new Contact(
                LastName = 'NoPhone',
                Email = 'nophone@example.com'
            ));

            // Edge case: Contact with only LastName
            contacts.add(new Contact(
                LastName = 'OnlyLastName',
                Email = 'onlylast@example.com'
            ));

            Test.startTest();
            insert contacts;
            Test.stopTest();

            // Verify all or most customers were created
            List<Stripe_Customer__c> insertedStripeCustomers = [
                SELECT Id, Contact__c, Customer_Name__c, Customer_Email__c
                FROM Stripe_Customer__c
                WHERE Contact__c IN :contacts
            ];

            // All contacts with email should have Stripe Customers created
            Assert.isTrue(insertedStripeCustomers.size() >= 5, 'At least the valid contacts should have Stripe Customers created');
        }
    }

    /**
     * @description Tests behavior when Contact with extremely long field values is inserted
     *              Verifies that field truncation or validation is handled appropriately
     */
    @IsTest
    static void processContactAfterInsert_extremelyLongValues_handledGracefully() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create Contact with very long values (at field limits)
            String longName = 'A'.repeat(80); // Salesforce Name field limit is typically 80 chars
            String longEmail = 'a'.repeat(67) + '@example.com'; // Email max length is 80 chars (67 + 13 = 80)
            String longPhone = '+1' + '9'.repeat(38); // Phone can be up to 40 chars

            Contact cont = new Contact(
                FirstName = longName.substring(0, 40), // FirstName limit is 40
                LastName = longName.substring(0, 80),  // LastName limit is 80
                Email = longEmail,
                Phone = longPhone
            );

            Test.startTest();
            insert cont;
            Test.stopTest();

            // Verify the result - should handle long values appropriately
            List<Stripe_Customer__c> insertedStripeCustomers = [
                SELECT Customer_Name__c, Customer_Email__c, Customer_Phone__c
                FROM Stripe_Customer__c
                WHERE Contact__c = :cont.Id
            ];

            Assert.areEqual(1, insertedStripeCustomers.size(), 'Stripe Customer should be created even with long values');
            Assert.isNotNull(insertedStripeCustomers[0].Customer_Name__c, 'Customer name should not be null');
        }
    }
}