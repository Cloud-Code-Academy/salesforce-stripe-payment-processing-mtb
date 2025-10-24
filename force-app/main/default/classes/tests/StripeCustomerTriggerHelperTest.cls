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
}
