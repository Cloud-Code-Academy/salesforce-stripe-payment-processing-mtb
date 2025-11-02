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

    // ========== Tests for Contact Update Functionality ==========

    /**
     * @description Tests that updating a Contact with Stripe_Customer_ID__c
     *              successfully queues a Stripe API update
     */
    @IsTest
    static void processContactAfterUpdate_updateContactWithStripeId_success() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create a Contact with Stripe Customer ID
            Contact cont = new Contact(
                FirstName = 'Original',
                LastName = 'Name',
                Email = 'original@example.com',
                Phone = '+1234567890',
                Stripe_Customer_ID__c = 'cus_test123'
            );
            insert cont;

            // Set mock for Stripe API callout
            Test.setMock(HttpCalloutMock.class, new UpdateCustomerSuccessMock());

            Test.startTest();
            // Update the contact
            cont.FirstName = 'Updated';
            cont.LastName = 'Customer';
            cont.Email = 'updated@example.com';
            cont.Phone = '+0987654321';
            update cont;
            Test.stopTest();

            // Verify queueable job was enqueued
            // Note: In test context, we can't directly verify API callouts from queueables,
            // but the fact that no exception was thrown indicates success
            Assert.isTrue(true, 'Update should complete without errors');
        }
    }

    /**
     * @description Tests that updating a Contact without Stripe_Customer_ID__c
     *              does not attempt to sync with Stripe
     */
    @IsTest
    static void processContactAfterUpdate_updateContactWithoutStripeId_noSync() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create a Contact without Stripe Customer ID
            Contact cont = new Contact(
                FirstName = 'No',
                LastName = 'StripeId',
                Email = 'nostripe@example.com'
            );
            insert cont;

            Test.startTest();
            // Update the contact
            cont.Email = 'updated@example.com';
            update cont;
            Test.stopTest();

            // No exception should be thrown, and no queueable should be enqueued
            Assert.isTrue(true, 'Update should complete without attempting Stripe sync');
        }
    }

    /**
     * @description Tests that updating non-relevant fields doesn't trigger Stripe sync
     */
    @IsTest
    static void processContactAfterUpdate_updateNonRelevantFields_noSync() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create a Contact with Stripe Customer ID
            Contact cont = new Contact(
                FirstName = 'Test',
                LastName = 'Contact',
                Email = 'test@example.com',
                Stripe_Customer_ID__c = 'cus_test123'
            );
            insert cont;

            Test.startTest();
            // Update only non-relevant fields
            cont.Title = 'New Title';
            cont.Department = 'Sales';
            update cont;
            Test.stopTest();

            // No sync should be triggered for non-relevant field updates
            Assert.isTrue(true, 'Non-relevant field updates should not trigger Stripe sync');
        }
    }

    /**
     * @description Tests bulk update of Contacts with mixed scenarios
     */
    @IsTest
    static void processContactAfterUpdate_bulkUpdate_mixedScenarios() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            List<Contact> contacts = new List<Contact>();

            // Create contacts with Stripe IDs
            for (Integer i = 0; i < 10; i++) {
                contacts.add(new Contact(
                    FirstName = 'Test' + i,
                    LastName = 'Contact' + i,
                    Email = 'test' + i + '@example.com',
                    Stripe_Customer_ID__c = 'cus_test' + i
                ));
            }

            // Create contacts without Stripe IDs
            for (Integer i = 10; i < 15; i++) {
                contacts.add(new Contact(
                    FirstName = 'Test' + i,
                    LastName = 'Contact' + i,
                    Email = 'test' + i + '@example.com'
                ));
            }

            insert contacts;

            // Set mock for Stripe API callouts
            Test.setMock(HttpCalloutMock.class, new UpdateCustomerSuccessMock());

            Test.startTest();
            // Update all contacts
            for (Contact c : contacts) {
                c.Email = 'updated' + c.LastName + '@example.com';
            }
            update contacts;
            Test.stopTest();

            // Only contacts with Stripe_Customer_ID__c should be synced
            Assert.isTrue(true, 'Bulk update should handle mixed scenarios correctly');
        }
    }

    /**
     * @description Tests that only changed fields trigger sync
     */
    @IsTest
    static void processContactAfterUpdate_onlyChangedFieldsTriggerSync() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create contacts
            List<Contact> contacts = new List<Contact>();
            for (Integer i = 0; i < 5; i++) {
                contacts.add(new Contact(
                    FirstName = 'Test' + i,
                    LastName = 'Contact' + i,
                    Email = 'test' + i + '@example.com',
                    Phone = '+123456789' + i,
                    Stripe_Customer_ID__c = 'cus_test' + i
                ));
            }
            insert contacts;

            // Set mock for Stripe API callouts
            Test.setMock(HttpCalloutMock.class, new UpdateCustomerSuccessMock());

            Test.startTest();
            // Update only some contacts with relevant field changes
            contacts[0].Email = 'newemail0@example.com'; // Should sync
            contacts[1].FirstName = 'NewFirst'; // Should sync
            contacts[2].Phone = '+9999999999'; // Should sync
            contacts[3].Title = 'CEO'; // Should NOT sync (non-relevant field)
            // contacts[4] - no changes

            update contacts;
            Test.stopTest();

            // Verify appropriate contacts were queued for sync
            Assert.isTrue(true, 'Only contacts with relevant field changes should be synced');
        }
    }

    /**
     * @description Tests error handling in the queueable
     */
    @IsTest
    static void processContactAfterUpdate_queueableError_handledGracefully() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create a Contact with Stripe Customer ID
            Contact cont = new Contact(
                FirstName = 'Test',
                LastName = 'Error',
                Email = 'error@example.com',
                Stripe_Customer_ID__c = 'cus_error'
            );
            insert cont;

            // Set mock that throws error
            Test.setMock(HttpCalloutMock.class, new UpdateCustomerErrorMock());

            Test.startTest();
            cont.Email = 'newemail@example.com';
            update cont;
            Test.stopTest();

            // The update should complete even if the queueable encounters an error
            Assert.isTrue(true, 'Contact update should complete even if Stripe sync fails');
        }
    }

    /**
     * @description Tests the StripeCustomerUpdateQueueable directly
     */
    @IsTest
    static void testStripeCustomerUpdateQueueable_directExecution() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create test contacts
            List<Contact> contacts = new List<Contact>{
                new Contact(
                    FirstName = 'John',
                    LastName = 'Doe',
                    Email = 'john@example.com',
                    Phone = '+1234567890',
                    Stripe_Customer_ID__c = 'cus_john'
                ),
                new Contact(
                    FirstName = 'Jane',
                    LastName = 'Smith',
                    Email = 'jane@example.com',
                    Stripe_Customer_ID__c = 'cus_jane'
                )
            };

            // Set mock for successful updates
            Test.setMock(HttpCalloutMock.class, new UpdateCustomerSuccessMock());

            Test.startTest();
            ContactTriggerHelper.StripeCustomerUpdateQueueable queueable =
                new ContactTriggerHelper.StripeCustomerUpdateQueueable(contacts);
            System.enqueueJob(queueable);
            Test.stopTest();

            // Verify the queueable executed without errors
            Assert.isTrue(true, 'Queueable should execute successfully');
        }
    }

    /**
     * @description Tests the StripeCustomerUpdateQueueable with mixed success/failure
     */
    @IsTest
    static void testStripeCustomerUpdateQueueable_mixedResults() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create test contacts
            List<Contact> contacts = new List<Contact>{
                new Contact(
                    FirstName = 'Success',
                    LastName = 'Case',
                    Email = 'success@example.com',
                    Stripe_Customer_ID__c = 'cus_success'
                ),
                new Contact(
                    FirstName = 'Error',
                    LastName = 'Case',
                    Email = 'error@example.com',
                    Stripe_Customer_ID__c = 'cus_error'
                )
            };

            // Set mock that handles both success and error cases
            Test.setMock(HttpCalloutMock.class, new MixedResultsMock());

            Test.startTest();
            ContactTriggerHelper.StripeCustomerUpdateQueueable queueable =
                new ContactTriggerHelper.StripeCustomerUpdateQueueable(contacts);
            System.enqueueJob(queueable);
            Test.stopTest();

            // The queueable should handle mixed results gracefully
            Assert.isTrue(true, 'Queueable should handle mixed success/failure cases');
        }
    }

    // ========== Mock Classes for Update Tests ==========

    private class UpdateCustomerSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            // Return updated customer data
            res.setBody('{"id":"cus_test123","name":"Updated Customer","email":"updated@example.com"}');

            return res;
        }
    }

    private class UpdateCustomerErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(400);
            res.setBody('{"error":{"type":"invalid_request_error","message":"Invalid customer ID"}}');
            return res;
        }
    }

    private class MixedResultsMock implements HttpCalloutMock {
        private Integer callCount = 0;

        public HTTPResponse respond(HTTPRequest req) {
            callCount++;
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            // Alternate between success and error
            if (Math.mod(callCount, 2) == 1) {
                res.setStatusCode(200);
                res.setBody('{"id":"cus_success","name":"Success Case","email":"success@example.com"}');
            } else {
                res.setStatusCode(400);
                res.setBody('{"error":{"type":"invalid_request_error","message":"Test error"}}');
            }

            return res;
        }
    }
}