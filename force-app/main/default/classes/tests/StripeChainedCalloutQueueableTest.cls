@IsTest
public class StripeChainedCalloutQueueableTest {
    private static User testUser;
    // Mock class for successful Stripe API callout
    private class StripeAPIPaymentMethodSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{ "id": "pm_1SL0s9F3hNTtzVuGZuInzLMb", "object": "payment_method"}');
            res.setStatusCode(200);
            return res;
        }
    }

    // Test data setup method
    @TestSetup
    static void setupTestData() {
        // Create test user with required permission sets
        testUser = TestDataFactory.createUserWithPermissionSets(
            new List<String>{'Stripe_API_Access', 'CustomMetadataAccess','Stripe_Integration_User','PricingPlanAndPricingTier'}
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
    @IsTest
    static void createDefaultPaymentMethod_success(){
        User testUser = getTestUser();
        System.runAs(testUser){
            // Set mock for HTTP callout
            Test.setMock(HttpCalloutMock.class, new StripeAPIPaymentMethodSuccessMock());
            Contact testContact = new Contact(
                FirstName = 'Test',
                LastName = 'Testov'
            );
            insert testContact;
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Contact__c = testContact.Id,
                Customer_Email__c = 'test2@example.com',
                Customer_Phone__c = '+1234567892',
                Stripe_Customer_ID__c = 'cus_existing123'
            );
            insert customer;
            StripeChainedCalloutQueueable callout = new StripeChainedCalloutQueueable(
                'cus_THZzLMvNDK5uWm', customer.Id
            );
            Test.startTest();
            System.enqueueJob(callout);
            Test.stopTest();
            Stripe_Customer__c result = [SELECT Default_Payment_Method__c
                                            FROM Stripe_Customer__c
                                            WHERE Id =: customer.Id];
            System.assertEquals('pm_1SL0s9F3hNTtzVuGZuInzLMb', 
                                result.Default_Payment_Method__c, 
                                'Default method is created');
        }
    }
    @IsTest
    static void StripeFinalCalloutQueueable_attachPaymentMethod_success(){
        User testUser = getTestUser();
        System.runAs(testUser){
            StripeFinalCalloutQueueable callout = new StripeFinalCalloutQueueable(
                'cus_jandsfljk',
                'pm_1SL0s9F3hNTtzVuGZuInzLMb'
            );
            Test.startTest();
            System.enqueueJob(callout);
            Test.stopTest();
        }
    }

}