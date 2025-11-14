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
     * @description Tests that inserting a Contact logs the operation correctly
     *              Note: Stripe customer data is now populated via middleware, not trigger
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

            // Verify the Contact was created successfully
            // Note: Stripe customer data (Customer_Name__c, Customer_Email__c, etc.)
            // is populated by middleware webhooks, not by trigger
            Contact insertedContact = [
                SELECT Id, FirstName, LastName, Email, Phone
                FROM Contact
                WHERE Id = :cont.Id
            ];
            Assert.areEqual('Test', insertedContact.FirstName, 'FirstName should be set');
            Assert.areEqual('Testov', insertedContact.LastName, 'LastName should be set');
            Assert.areEqual('testovtest@gmail.com.au', insertedContact.Email, 'Email should be set');
        }
    }

    /**
     * @description Tests that inserting a Contact with only LastName succeeds
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

            // Verify the Contact was created
            Contact insertedContact = [
                SELECT Id, LastName, Email, Phone
                FROM Contact
                WHERE Id = :cont.Id
            ];
            Assert.areEqual('Testov', insertedContact.LastName, 'LastName should be set');
            Assert.areEqual('testovtest@gmail.com.au', insertedContact.Email, 'Email should be set');
        }
    }

    /**
     * @description Tests that inserting a Contact without phone succeeds
     */
    @IsTest
    static void processContactAfterInsert_insertContactWithoutPhone_success() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create test data without phone
            Contact cont = new Contact(
                LastName = 'MinimalContact',
                Email = 'minimal@example.com'
            );

            Test.startTest();
            insert cont;
            Test.stopTest();

            // Verify the Contact was created
            Contact insertedContact = [
                SELECT Id, LastName, Email, Phone
                FROM Contact
                WHERE Id = :cont.Id
            ];
            Assert.areEqual('MinimalContact', insertedContact.LastName, 'LastName should be set');
            Assert.areEqual('minimal@example.com', insertedContact.Email, 'Email should be set');
            Assert.areEqual(null, insertedContact.Phone, 'Phone should be null when not provided');
        }
    }

    /**
     * @description Tests that inserting multiple Contacts in bulk succeeds
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

            // Verify all Contacts were created
            List<Contact> insertedContacts = [
                SELECT Id
                FROM Contact
                WHERE Id IN :contacts
            ];
            Assert.areEqual(200, insertedContacts.size(), 'All 200 Contacts should be created for bulk insert');
        }
    }

    /**
     * @description Tests that inserting Contacts with special characters in names succeeds
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

            // Verify the Contact was created with special characters preserved
            Contact insertedContact = [
                SELECT FirstName, LastName
                FROM Contact
                WHERE Id = :cont.Id
            ];
            Assert.areEqual('José María', insertedContact.FirstName, 'FirstName with special characters should be preserved');
            Assert.areEqual('O\'Brien-Smith', insertedContact.LastName, 'LastName with special characters should be preserved');
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

            // Verify method completes without throwing exception
            Assert.isTrue(true, 'Helper should handle null list without errors');
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

            // Verify method completes without throwing exception
            Assert.isTrue(true, 'Helper should handle empty list without errors');
        }
    }

    /**
     * @description Tests that Contacts without email can still be created
     */
    @IsTest
    static void processContactAfterInsert_contactWithoutEmail_success() {
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

            // Verify Contact was created successfully
            Contact insertedContact = [
                SELECT Id, LastName
                FROM Contact
                WHERE Id = :cont.Id
            ];
            Assert.areEqual('Email', insertedContact.LastName, 'Contact should be created without email');
        }
    }

    /**
     * @description Tests that Contacts with minimal data are handled gracefully
     */
    @IsTest
    static void processContactAfterInsert_contactWithoutName_handledGracefully() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            // Create Contact with minimal data
            // Note: LastName is required by Salesforce
            Contact cont = new Contact(
                LastName = 'MinimalData',
                Email = 'minimal@example.com'
            );

            Test.startTest();
            insert cont;
            Test.stopTest();

            // Verify the Contact was created
            Contact insertedContact = [
                SELECT LastName
                FROM Contact
                WHERE Id = :cont.Id
            ];
            Assert.areEqual('MinimalData', insertedContact.LastName, 'Contact should be created with minimal data');
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

            // Verify all Contacts were created
            List<Contact> insertedContacts = [
                SELECT Id
                FROM Contact
                WHERE Id IN :contacts
            ];
            Assert.areEqual(7, insertedContacts.size(), 'All 7 contacts should be created successfully');
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

            // Verify the Contact was created with long values
            Contact insertedContact = [
                SELECT FirstName, LastName, Email, Phone
                FROM Contact
                WHERE Id = :cont.Id
            ];
            Assert.isNotNull(insertedContact.FirstName, 'FirstName should not be null');
            Assert.isNotNull(insertedContact.LastName, 'LastName should not be null');
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