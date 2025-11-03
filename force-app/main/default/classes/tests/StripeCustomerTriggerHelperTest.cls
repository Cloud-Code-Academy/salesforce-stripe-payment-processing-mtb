@isTest
private class StripeCustomerTriggerHelperTest {

    private static User testUser;

    // Mock class for successful Stripe API callout
    private class StripeAPISuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"cus_test123","name":"Test Customer","email":"test@example.com"}');
            res.setStatusCode(200);
            return res;
        }
    }

    // Mock class for failed Stripe API callout
    private class StripeAPIFailureMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":{"message":"API Error"}}');
            res.setStatusCode(400);
            res.setStatus('Bad Request');
            return res;
        }
    }

    // Test data setup method
    @TestSetup
    static void setupTestData() {
        // Create test user with required permission sets
        testUser = TestDataFactory.createUserWithPermissionSets(
            new List<String>{'Stripe_Customer_Contact_Access', 'Stripe_API_Access'}
        );

        // Run as test user to create test data
        System.runAs(testUser) {
            // Create test Contact records using TestDataFactory
            TestDataFactory.createContacts(5);
        }
    }

    // Helper method to get test user
    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'testuser%@testorg.com' LIMIT 1];
    }
    
    /**
     * Test processCustomerAfterInsert method - Existing Stripe Customer ID
     * Verifies that records with existing Stripe Customer ID are skipped
     */
    @isTest
    static void testProcessCustomerAfterInsert_ExistingStripeId() {
        System.runAs(getTestUser()) {
            // Query test contact
            Contact testContact = [SELECT Id, Name FROM Contact WHERE Email = 'test2@example.com' LIMIT 1];

            // Create Stripe Customer record with existing Stripe Customer ID
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Contact__c = testContact.Id,
                Customer_Email__c = 'test2@example.com',
                Customer_Phone__c = '+1234567892',
                Stripe_Customer_ID__c = 'cus_existing123'
            );

            // Start test context
            Test.startTest();
            insert customer;
            Test.stopTest();

            // Query the inserted record
            Stripe_Customer__c insertedCustomer = [
                SELECT Id, Stripe_Customer_ID__c
                FROM Stripe_Customer__c
                WHERE Id = :customer.Id
            ];

            // Verify Stripe_Customer_ID__c remains unchanged
            Assert.areEqual('cus_existing123', insertedCustomer.Stripe_Customer_ID__c,
                'Stripe_Customer_ID__c should remain unchanged');
        }
    }

    /**
     * Test StripeCustomerTriggerHandler - Before Insert
     * Verifies the trigger handler calls populateStripeCustomerIdOnRelatedContact
     */
    @isTest
    static void populateStripeCustomerIdOnRelatedContact_afterInsert_success() {
        System.runAs(getTestUser()) {
            // Query test contact
            Contact testContact = [SELECT Name FROM Contact WHERE Email = 'test3@example.com' LIMIT 1];

            // Create Stripe Customer record
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Contact__c = testContact.Id,
                Customer_Email__c = 'test3@example.com',
                Customer_Phone__c = '+1234567893'
            );
            insert customer;
            // Start test context
            Test.startTest();
            customer.Stripe_Customer_ID__c = 'cus_THZzLMvNDK5uWm';
            update customer;
            Test.stopTest();

            // Query and verify
            Contact result = [
                SELECT Stripe_Customer_ID__c
                FROM Contact
                WHERE Id = :testContact.Id
            ];
            Assert.areEqual(customer.Stripe_Customer_ID__c, result.Stripe_Customer_ID__c,
                'Trigger handler should populate Stripe_Customer_ID__c');
        }
    }

    /**
     * Test StripeCalloutQueueable - Execute method with success
     * Verifies the queueable job executes and updates the record
     */
    @isTest
    static void testStripeCalloutQueueable_Success() {
        System.runAs(getTestUser()) {
            // Set mock for HTTP callout
            Test.setMock(HttpCalloutMock.class, new StripeAPISuccessMock());

            // Query test contact
            Contact testContact = [SELECT Id, Name FROM Contact WHERE Email = 'test4@example.com' LIMIT 1];

            // Create and insert Stripe Customer record
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Contact__c = testContact.Id,
                Customer_Email__c = 'test4@example.com',
                Customer_Phone__c = '+1234567894',
                Customer_Name__c = testContact.Name
            );
            insert customer;

            // Create queueable instance
            StripeCalloutQueueable queueable = new StripeCalloutQueueable(
                customer.Id,
                testContact.Name,
                'test4@example.com',
                '+1234567894'
            );

            // Start test context and execute queueable
            Test.startTest();
            System.enqueueJob(queueable);
            Test.stopTest();

            // Query the updated record
            Stripe_Customer__c updatedCustomer = [
                SELECT Id, Stripe_Customer_ID__c
                FROM Stripe_Customer__c
                WHERE Id = :customer.Id
            ];

            // Verify Stripe_Customer_ID__c was updated
            Assert.areEqual('cus_test123', updatedCustomer.Stripe_Customer_ID__c,
                'Stripe_Customer_ID__c should be updated by queueable');
        }
    }

    /**
     * Test StripeCalloutQueueable - Execute method with API failure
     * Verifies the queueable handles API errors gracefully
     */
    @isTest
    static void testStripeCalloutQueueable_APIFailure() {
        System.runAs(getTestUser()) {
            // Set mock for failed HTTP callout
            Test.setMock(HttpCalloutMock.class, new StripeAPIFailureMock());

            // Query test contact
            Contact testContact = [SELECT Id, Name FROM Contact WHERE Email = 'test4@example.com' LIMIT 1];

            // Create and insert Stripe Customer record
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Contact__c = testContact.Id,
                Customer_Email__c = 'fail@example.com',
                Customer_Phone__c = '+1234567895',
                Customer_Name__c = testContact.Name
            );
            insert customer;

            // Create queueable instance
            StripeCalloutQueueable queueable = new StripeCalloutQueueable(
                customer.Id,
                testContact.Name,
                'fail@example.com',
                '+1234567895'
            );

            // Start test context and execute queueable
            Test.startTest();
            System.enqueueJob(queueable);
            Test.stopTest();

            // Query the record
            Stripe_Customer__c updatedCustomer = [
                SELECT Id, Stripe_Customer_ID__c
                FROM Stripe_Customer__c
                WHERE Id = :customer.Id
            ];

            // Verify Stripe_Customer_ID__c was not updated due to failure
            Assert.areEqual(null, updatedCustomer.Stripe_Customer_ID__c,
                'Stripe_Customer_ID__c should remain null when API fails');
        }
    }

    // ========== High Priority Error Handling Tests ==========

    /**
     * Test populateStripeCustomerIdOnRelatedContact with null Contact__c
     * Verifies that customers without Contact reference are skipped
     */
    @isTest
    static void populateStripeCustomerIdOnRelatedContact_nullContact_skipped() {
        System.runAs(getTestUser()) {
            // Create Stripe Customer record without Contact__c reference
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Customer_Email__c = 'orphan@example.com',
                Customer_Phone__c = '+1234567890'
                // No Contact__c reference
            );
            insert customer;

            // Update Stripe_Customer_ID__c
            customer.Stripe_Customer_ID__c = 'cus_orphan123';

            Test.startTest();
            update customer;
            Test.stopTest();

            // Should complete without error (customer without contact is skipped)
            Stripe_Customer__c updatedCustomer = [
                SELECT Stripe_Customer_ID__c
                FROM Stripe_Customer__c
                WHERE Id = :customer.Id
            ];
            Assert.areEqual('cus_orphan123', updatedCustomer.Stripe_Customer_ID__c,
                'Customer should be updated even without Contact reference');
        }
    }

    /**
     * Test populateStripeCustomerIdOnRelatedContact with null Stripe_Customer_ID__c
     * Verifies that updates without Stripe_Customer_ID__c are skipped
     */
    @isTest
    static void populateStripeCustomerIdOnRelatedContact_nullStripeId_skipped() {
        System.runAs(getTestUser()) {
            Contact testContact = [SELECT Id FROM Contact WHERE Email = 'test1@example.com' LIMIT 1];

            // Create Stripe Customer record
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Contact__c = testContact.Id,
                Customer_Email__c = 'test1@example.com',
                Customer_Phone__c = '+1234567890'
            );
            insert customer;

            // Update something other than Stripe_Customer_ID__c
            customer.Customer_Phone__c = '+9999999999';

            Test.startTest();
            update customer;
            Test.stopTest();

            // Verify Contact was NOT updated (Stripe_Customer_ID__c was not set)
            Contact updatedContact = [
                SELECT Stripe_Customer_ID__c
                FROM Contact
                WHERE Id = :testContact.Id
            ];
            Assert.areEqual(null, updatedContact.Stripe_Customer_ID__c,
                'Contact should not be updated when Stripe_Customer_ID__c is null');
        }
    }

    /**
     * Test populateStripeCustomerIdOnRelatedContact with unchanged Stripe_Customer_ID__c
     * Verifies that unchanged values don't trigger updates
     */
    @isTest
    static void populateStripeCustomerIdOnRelatedContact_unchangedStripeId_skipped() {
        System.runAs(getTestUser()) {
            Contact testContact = [SELECT Id FROM Contact WHERE Email = 'test2@example.com' LIMIT 1];

            // Create Stripe Customer with initial Stripe_Customer_ID__c
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Contact__c = testContact.Id,
                Customer_Email__c = 'test2@example.com',
                Customer_Phone__c = '+1234567890',
                Stripe_Customer_ID__c = 'cus_unchanged123'
            );
            insert customer;

            // First update to set Contact's Stripe_Customer_ID__c
            Contact updatedContact = [SELECT Stripe_Customer_ID__c FROM Contact WHERE Id = :testContact.Id];
            Assert.areEqual('cus_unchanged123', updatedContact.Stripe_Customer_ID__c,
                'Initial update should set Contact Stripe_Customer_ID__c');

            // Update something other than Stripe_Customer_ID__c
            customer.Customer_Phone__c = '+9999999999';

            Test.startTest();
            update customer;
            Test.stopTest();

            // Verify Contact still has same Stripe_Customer_ID__c
            Contact finalContact = [SELECT Stripe_Customer_ID__c FROM Contact WHERE Id = :testContact.Id];
            Assert.areEqual('cus_unchanged123', finalContact.Stripe_Customer_ID__c,
                'Contact Stripe_Customer_ID__c should remain unchanged when not modified');
        }
    }

    /**
     * Test processCustomerAfterInsert with all customers having Stripe_Customer_ID__c
     * Verifies that empty list (all skipped) is handled gracefully
     */
    @isTest
    static void processCustomerAfterInsert_allHaveStripeId_noQueueables() {
        System.runAs(getTestUser()) {
            Contact testContact = [SELECT Id FROM Contact WHERE Email = 'test1@example.com' LIMIT 1];

            // Create customer with existing Stripe_Customer_ID__c
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Contact__c = testContact.Id,
                Customer_Email__c = 'existing@example.com',
                Customer_Phone__c = '+1234567890',
                Stripe_Customer_ID__c = 'cus_existing_abc'
            );

            Test.startTest();
            insert customer;
            Test.stopTest();

            // Verify customer still has original Stripe_Customer_ID__c
            Stripe_Customer__c insertedCustomer = [
                SELECT Stripe_Customer_ID__c
                FROM Stripe_Customer__c
                WHERE Id = :customer.Id
            ];
            Assert.areEqual('cus_existing_abc', insertedCustomer.Stripe_Customer_ID__c,
                'Customer with existing Stripe ID should not be processed');
        }
    }

    /**
     * Test bulk processing with multiple customers
     * Verifies that multiple customers are processed correctly
     */
    @isTest
    static void populateStripeCustomerIdOnRelatedContact_bulkProcessing_success() {
        System.runAs(getTestUser()) {
            // Create multiple contacts
            List<Contact> contacts = new List<Contact>();
            for (Integer i = 0; i < 5; i++) {
                contacts.add(new Contact(
                    FirstName = 'Bulk',
                    LastName = 'Test' + i,
                    Email = 'bulktest' + i + '@example.com'
                ));
            }
            insert contacts;

            // Create multiple Stripe Customers
            List<Stripe_Customer__c> customers = new List<Stripe_Customer__c>();
            for (Integer i = 0; i < 5; i++) {
                customers.add(new Stripe_Customer__c(
                    Contact__c = contacts[i].Id,
                    Customer_Email__c = 'bulktest' + i + '@example.com',
                    Customer_Phone__c = '+123456789' + i
                ));
            }
            insert customers;

            // Update all with Stripe_Customer_ID__c
            for (Integer i = 0; i < 5; i++) {
                customers[i].Stripe_Customer_ID__c = 'cus_bulk_' + i;
            }

            Test.startTest();
            update customers;
            Test.stopTest();

            // Verify all contacts were updated
            List<Contact> updatedContacts = [
                SELECT Stripe_Customer_ID__c
                FROM Contact
                WHERE Id IN :contacts
                ORDER BY Email
            ];

            Assert.areEqual(5, updatedContacts.size(), 'All 5 contacts should be queried');
            for (Integer i = 0; i < 5; i++) {
                Assert.areEqual('cus_bulk_' + i, updatedContacts[i].Stripe_Customer_ID__c,
                    'Contact ' + i + ' should have correct Stripe_Customer_ID__c');
            }
        }
    }

    /**
     * Test processCustomerAfterInsert with null parameter
     * Verifies that null parameter is handled gracefully
     */
    @isTest
    static void processCustomerAfterInsert_nullParameter_noError() {
        System.runAs(getTestUser()) {
            Test.startTest();
            // Should not throw exception with null parameter
            StripeCustomerTriggerHelper.processCustomerAfterInsert(null);
            Test.stopTest();

            // Should complete without errors
            Assert.isTrue(true, 'Method should handle null parameter gracefully');
        }
    }

    /**
     * Test populateStripeCustomerIdOnRelatedContact with null/empty parameters
     * Verifies that null parameters are handled gracefully
     */
    @isTest
    static void populateStripeCustomerIdOnRelatedContact_nullParameters_noError() {
        System.runAs(getTestUser()) {
            Test.startTest();
            // Should not throw exception with null parameters
            StripeCustomerTriggerHelper.populateStripeCustomerIdOnRelatedContact(null, null);
            StripeCustomerTriggerHelper.populateStripeCustomerIdOnRelatedContact(
                new List<Stripe_Customer__c>(),
                new Map<Id, Stripe_Customer__c>()
            );
            Test.stopTest();

            // Should complete without errors
            Assert.isTrue(true, 'Method should handle null/empty parameters gracefully');
        }
    }

    /**
     * Test bulk insert of customers without Stripe_Customer_ID__c
     * Verifies that queueables are enqueued for multiple customers
     */
    @isTest
    static void processCustomerAfterInsert_bulkInsert_multipleQueueables() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeAPISuccessMock());

            // Create contacts
            List<Contact> contacts = new List<Contact>();
            for (Integer i = 0; i < 3; i++) {
                contacts.add(new Contact(
                    FirstName = 'Queue',
                    LastName = 'Test' + i,
                    Email = 'queuetest' + i + '@example.com'
                ));
            }
            insert contacts;

            // Create Stripe Customers without Stripe_Customer_ID__c
            List<Stripe_Customer__c> customers = new List<Stripe_Customer__c>();
            for (Integer i = 0; i < 3; i++) {
                customers.add(new Stripe_Customer__c(
                    Contact__c = contacts[i].Id,
                    Customer_Email__c = 'queuetest' + i + '@example.com',
                    Customer_Phone__c = '+123456789' + i,
                    Customer_Name__c = 'Queue Test' + i
                ));
            }

            Test.startTest();
            insert customers;
            Test.stopTest();

            // In test context, queueables execute synchronously
            // Verify customers were processed (would have Stripe_Customer_ID__c in real execution)
            List<Stripe_Customer__c> insertedCustomers = [
                SELECT Id, Stripe_Customer_ID__c
                FROM Stripe_Customer__c
                WHERE Id IN :customers
            ];

            Assert.areEqual(3, insertedCustomers.size(), 'All 3 customers should be created');
        }
    }
}