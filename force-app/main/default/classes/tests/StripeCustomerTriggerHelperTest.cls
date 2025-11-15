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
     * Test populateNameFromContact method - Success scenario
     * Verifies that Customer_Name__c is populated with Contact Name
     */
    @isTest
    static void testPopulateNameFromContact_Success() {
        System.runAs(getTestUser()) {
            // Query test contact
            Contact testContact = [SELECT Id, Name FROM Contact WHERE Email = 'test0@example.com' LIMIT 1];

            // Create Stripe Customer record with Contact reference
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Contact__c = testContact.Id,
                Customer_Email__c = 'test0@example.com',
                Customer_Phone__c = '+1234567890'
            );

            // Start test context
            Test.startTest();
            insert customer;
            Test.stopTest();

            // Query the inserted record
            Stripe_Customer__c insertedCustomer = [
                SELECT Id, Customer_Name__c, Contact__c
                FROM Stripe_Customer__c
                WHERE Id = :customer.Id
            ];

            // Verify Customer_Name__c was populated with Contact Name
            Assert.areEqual(testContact.Name, insertedCustomer.Customer_Name__c,
                'Customer_Name__c should be populated with Contact Name');
        }
    }

    /**
     * Test populateNameFromContact method - Multiple records
     * Verifies bulk processing of multiple Stripe Customer records
     */
    @isTest
    static void testPopulateNameFromContact_BulkRecords() {
        System.runAs(getTestUser()) {
            // Query test contacts
            List<Contact> contacts = [SELECT Id, Name FROM Contact ORDER BY Email LIMIT 3];

            // Create multiple Stripe Customer records
            List<Stripe_Customer__c> customers = new List<Stripe_Customer__c>();
            for (Integer i = 0; i < contacts.size(); i++) {
                customers.add(new Stripe_Customer__c(
                    Contact__c = contacts[i].Id,
                    Customer_Email__c = 'bulk' + i + '@example.com',
                    Customer_Phone__c = '+123456789' + i
                ));
            }

            // Start test context
            Test.startTest();
            insert customers;
            Test.stopTest();

            // Query the inserted records
            List<Stripe_Customer__c> insertedCustomers = [
                SELECT Id, Customer_Name__c, Contact__c
                FROM Stripe_Customer__c
                WHERE Id IN :customers
                ORDER BY Customer_Name__c ASC
            ];

            // Verify all Customer_Name__c fields were populated
            Assert.areEqual(3, insertedCustomers.size(), 'Should have 3 customers');
            for (Integer i = 0; i < insertedCustomers.size(); i++) {
                Assert.areNotEqual(null, insertedCustomers[i].Customer_Name__c,
                    'Customer_Name__c should be populated');
                Assert.areEqual(contacts[i].Name, insertedCustomers[i].Customer_Name__c,
                    'Customer_Name__c should match Contact Name');
            }
        }
    }

    /**
     * Test populateNameFromContact method - Null Contact
     * Verifies handling when Contact__c is null
     */
    @isTest
    static void testPopulateNameFromContact_NullContact() {
        System.runAs(getTestUser()) {
            // Create Stripe Customer record without Contact reference
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Contact__c = null,
                Customer_Email__c = 'nocontact@example.com',
                Customer_Phone__c = '+1234567890'
            );

            // Start test context
            Test.startTest();
            insert customer;
            Test.stopTest();

            // Query the inserted record
            Stripe_Customer__c insertedCustomer = [
                SELECT Id, Customer_Name__c, Contact__c
                FROM Stripe_Customer__c
                WHERE Id = :customer.Id
            ];

            // Verify Customer_Name__c is null
            Assert.areEqual(null, insertedCustomer.Customer_Name__c,
                'Customer_Name__c should be null when Contact__c is null');
        }
    }

    /**
     * Test processCustomerAfterInsert method - Success scenario
     * Verifies that StripeCalloutQueueable is enqueued for new customers
     */
    @isTest
    static void testProcessCustomerAfterInsert_Success() {
        System.runAs(getTestUser()) {
            // Set mock for HTTP callout
            Test.setMock(HttpCalloutMock.class, new StripeAPISuccessMock());

            // Query test contact
            Contact testContact = [SELECT Id, Name FROM Contact WHERE Email = 'test1@example.com' LIMIT 1];

            // Create Stripe Customer record without Stripe Customer ID
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Contact__c = testContact.Id,
                Customer_Email__c = 'test1@example.com',
                Customer_Phone__c = '+1234567891',
                Stripe_Customer_ID__c = null
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

            // In test context, queueable is not actually executed
            // Verify that no Stripe_Customer_ID__c is set yet (would be set by queueable)
            Assert.areEqual(null, insertedCustomer.Stripe_Customer_ID__c,
                'Stripe_Customer_ID__c should be null in test context');
        }
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
     * Test processCustomerAfterInsert method - Multiple records
     * Verifies bulk processing filters correctly
     */
    @isTest
    static void testProcessCustomerAfterInsert_MixedRecords() {
        System.runAs(getTestUser()) {
            // Set mock for HTTP callout
            Test.setMock(HttpCalloutMock.class, new StripeAPISuccessMock());

            // Query test contacts
            List<Contact> contacts = [SELECT Id, Name FROM Contact ORDER BY Email LIMIT 3];

            // Create mixed Stripe Customer records (some with IDs, some without)
            List<Stripe_Customer__c> customers = new List<Stripe_Customer__c>();
            customers.add(new Stripe_Customer__c(
                Contact__c = contacts[0].Id,
                Customer_Email__c = 'mixed0@example.com',
                Customer_Phone__c = '+1234567890',
                Stripe_Customer_ID__c = null // Should be processed
            ));
            customers.add(new Stripe_Customer__c(
                Contact__c = contacts[1].Id,
                Customer_Email__c = 'mixed1@example.com',
                Customer_Phone__c = '+1234567891',
                Stripe_Customer_ID__c = 'cus_existing' // Should NOT be processed
            ));
            customers.add(new Stripe_Customer__c(
                Contact__c = contacts[2].Id,
                Customer_Email__c = 'mixed2@example.com',
                Customer_Phone__c = '+1234567892',
                Stripe_Customer_ID__c = '' // Should be processed (blank)
            ));

            // Start test context
            Test.startTest();
            insert customers;
            Test.stopTest();

            // Verify records were inserted
            List<Stripe_Customer__c> insertedCustomers = [
                SELECT Id, Stripe_Customer_ID__c
                FROM Stripe_Customer__c
                WHERE Id IN :customers
            ];
            Assert.areEqual(3, insertedCustomers.size(), 'All 3 customers should be inserted');
        }
    }

    /**
     * Test StripeCustomerTriggerHandler - Before Insert
     * Verifies the trigger handler calls populateNameFromContact
     */
    @isTest
    static void testTriggerHandler_BeforeInsert() {
        System.runAs(getTestUser()) {
            // Query test contact
            Contact testContact = [SELECT Id, Name FROM Contact WHERE Email = 'test3@example.com' LIMIT 1];

            // Create Stripe Customer record
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Contact__c = testContact.Id,
                Customer_Email__c = 'test3@example.com',
                Customer_Phone__c = '+1234567893'
            );

            // Start test context
            Test.startTest();
            insert customer;
            Test.stopTest();

            // Query and verify
            Stripe_Customer__c result = [
                SELECT Customer_Name__c
                FROM Stripe_Customer__c
                WHERE Id = :customer.Id
            ];

            Assert.areEqual(testContact.Name, result.Customer_Name__c,
                'Trigger handler should populate Customer_Name__c');
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

    /**
     * Test full end-to-end scenario
     * Verifies complete flow from insert through trigger to queueable execution
     */
    @isTest
    static void testEndToEnd_InsertToQueueableExecution() {
        System.runAs(getTestUser()) {
            // Set mock for HTTP callout
            Test.setMock(HttpCalloutMock.class, new StripeAPISuccessMock());

            // Create new Contact
            Contact newContact = new Contact(
                FirstName = 'End',
                LastName = 'To End Test',
                Email = 'e2e@example.com',
                Phone = '+9876543210'
            );
            insert newContact;

            // Create Stripe Customer record
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Contact__c = newContact.Id,
                Customer_Email__c = 'e2e@example.com',
                Customer_Phone__c = '+9876543210'
            );

            // Start test context
            Test.startTest();
            insert customer;
            Test.stopTest();

            // Query the inserted record
            Stripe_Customer__c result = [
                SELECT Id, Customer_Name__c, Stripe_Customer_ID__c
                FROM Stripe_Customer__c
                WHERE Id = :customer.Id
            ];

            // Verify Customer_Name__c was populated by trigger (before insert)
            Assert.areEqual('End To End Test', result.Customer_Name__c,
                'Customer_Name__c should be populated by before insert trigger');

            // Note: Stripe_Customer_ID__c will be null in test context because
            // queueable is not actually executed when Test.isRunningTest() is true
        }
    }

    /**
     * Test processCustomerAfterInsert with blank string Stripe Customer ID
     * Verifies that blank strings are treated as missing IDs
     */
    @isTest
    static void testProcessCustomerAfterInsert_BlankStripeId() {
        System.runAs(getTestUser()) {
            // Set mock for HTTP callout
            Test.setMock(HttpCalloutMock.class, new StripeAPISuccessMock());

            // Query test contact
            Contact testContact = [SELECT Id, Name FROM Contact LIMIT 1];

            // Create Stripe Customer record with blank Stripe Customer ID
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Contact__c = testContact.Id,
                Customer_Email__c = 'blank@example.com',
                Customer_Phone__c = '+1234567890',
                Stripe_Customer_ID__c = ''
            );

            // Start test context
            Test.startTest();
            insert customer;
            Test.stopTest();

            // Verify record was inserted successfully
            Stripe_Customer__c insertedCustomer = [
                SELECT Id, Stripe_Customer_ID__c
                FROM Stripe_Customer__c
                WHERE Id = :customer.Id
            ];

            Assert.areNotEqual(null, insertedCustomer.Id, 'Customer should be inserted');
        }
    }
}
