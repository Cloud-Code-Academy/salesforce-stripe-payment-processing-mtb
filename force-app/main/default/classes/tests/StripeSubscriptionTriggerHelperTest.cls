@IsTest
public class StripeSubscriptionTriggerHelperTest {
    private static User testUser;
    // Mock class for successful Stripe API callout
    private class StripeAPISubscriptionSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id": "sub_1SL0dlF3hNTtzVuGK5JQfCji", "object": "subscription", "application": null, "application_fee_percent": null}');
            res.setStatusCode(200);
            return res;
        }
    }
    private class StripeAPISessionSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id": "cs_test_a1APLw6wEYwl7TijcXg8BbeHzO4YFQJ3RYmUAFyMWab3YT4BSq9c9x3PlM", "object": "checkout.session", "url": "https://checkout.stripe.com/c/pay/cs_test_a1APLw6wEYwl7TijcXg8BbeHzO4YFQJ3RYmUAFyMWab3YT4BSq9c9x3PlM#fidnandhYHdWcXxpYCc%2FJ2FgY2RwaXEnKSdkdWxOYHwnPyd1blpxYHZxWjA0Vk03R1BDNm1LUXF%2FU3BCSWBxV2hyVEgzQF89YEB9YklSbmluNnxSa3c9N3REYU93c1R9NnRwUTR1V2lyPGx1ampNcGNvalIyMWN8TExValEyTGtXQ1xGNTVwXFYzX3R%2FNCcpJ2N3amhWYHdzYHcnP3F3cGApJ2dkZm5id2pwa2FGamlqdyc%2FJyZjY2NjY2MnKSdpZHxqcHFRfHVgJz8ndmxrYmlgWmxxYGgnKSdga2RnaWBVaWRmYG1qaWFgd3YnP3F3cGB4JSUl"}');
            res.setStatusCode(200);
            return res;
        }
    }
    @TestSetup
    static void setupTestData() {
        // Create test user with Stripe API Access permission set
        testUser = TestDataFactory.createUserWithPermissionSets(
            new List<String>{'Stripe_Customer_Contact_Access', 'Stripe_API_Access', 
                                'CustomMetadataAccess', 'Stripe_Integration_User', 
                                'PricingPlanAndPricingTier', 'StripeSubscription'}
        );
    }
    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'testuser%@testorg.com' LIMIT 1];
    }
    @IsTest
    static void processStripeSubscriptionAfterUpdate_SendSubscriptionToStripe_success(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Test.setMock(HttpCalloutMock.class, new StripeAPISubscriptionSuccessMock());
            Contact customerContact = new Contact(
                FirstName = 'Test',
                LastName = 'Testov'
            );
            insert customerContact;
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Customer_Email__c = 'test4@example.com',
                Customer_Phone__c = '+1234567894',
                Contact__c = customerContact.Id,
                Stripe_Customer_ID__c = 'cus_THZzLMvNDK5uWm',
                Default_Payment_Method__c = 'pm_1SLhFJF3hNTtzVuGpoRILACR'
            );
            insert customer;
            Stripe_Subscription__c subscriptionRec = new Stripe_Subscription__c(
                Stripe_Price_ID__c = 'price_1SL0u0F3hNTtzVuGs8NtCjiW',
                Stripe_Customer__c = customer.Id,
                Sync_Status__c = 'Send to Stripe'
            );
            insert subscriptionRec;
            subscriptionRec = [SELECT Id, Stripe_Price_ID__c, StripeCustomerId__c, CustomerDefaultPayment__c, Sync_Status__c
                                FROM Stripe_Subscription__c
                                WHERE Id = :subscriptionRec.Id];
            StripeCalloutQueueable queueable = new StripeCalloutQueueable(
                subscriptionRec.StripeCustomerId__c,
                subscriptionRec.Id,
                subscriptionRec.Stripe_Price_ID__c,
                subscriptionRec.CustomerDefaultPayment__c
            );
            Test.startTest();
            System.enqueueJob(queueable);
            Test.stopTest();
            Stripe_Subscription__c result = [SELECT Stripe_Subscription_ID__c, Sync_Status__c
                                                FROM Stripe_Subscription__c
                                                WHERE Id =: subscriptionRec.Id];
            System.assertEquals('sub_1SL0dlF3hNTtzVuGK5JQfCji',
                                result.Stripe_Subscription_ID__c,
                                'Stripe_Subscription_ID__c was assigned');
            System.assertEquals('Synced',
                                result.Sync_Status__c,
                                'Sync_Status__c was updated');

        }
    }
    @IsTest
    static void processStripeSubscriptionAfterUpdate_withUpdateOfSyncStatus_success(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Test.setMock(HttpCalloutMock.class, new StripeAPISubscriptionSuccessMock());
            Contact customerContact = new Contact(
                FirstName = 'Test',
                LastName = 'Testov'
            );
            insert customerContact;
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Customer_Email__c = 'test4@example.com',
                Customer_Phone__c = '+1234567894',
                Contact__c = customerContact.Id,
                Stripe_Customer_ID__c = 'cus_THZzLMvNDK5uWm',
                Default_Payment_Method__c = 'pm_1SLhFJF3hNTtzVuGpoRILACR'
            );
            insert customer;
            Stripe_Subscription__c subscriptionRec = new Stripe_Subscription__c(
                Stripe_Price_ID__c = 'price_1SL0u0F3hNTtzVuGs8NtCjiW',
                Stripe_Customer__c = customer.Id
            );
            insert subscriptionRec;
            subscriptionRec = [SELECT Id, Stripe_Price_ID__c, StripeCustomerId__c, CustomerDefaultPayment__c, Sync_Status__c
                                FROM Stripe_Subscription__c
                                WHERE Id = :subscriptionRec.Id];
            StripeCalloutQueueable queueable = new StripeCalloutQueueable(
                subscriptionRec.StripeCustomerId__c,
                subscriptionRec.Id,
                subscriptionRec.Stripe_Price_ID__c,
                subscriptionRec.CustomerDefaultPayment__c
            );
            Test.startTest();
            subscriptionRec.Sync_Status__c = 'Send to Stripe';
            update subscriptionRec;
            System.enqueueJob(queueable);
            Test.stopTest();
            Stripe_Subscription__c result = [SELECT Stripe_Subscription_ID__c, Sync_Status__c
                                                FROM Stripe_Subscription__c
                                                WHERE Id =: subscriptionRec.Id];
            System.assertEquals('sub_1SL0dlF3hNTtzVuGK5JQfCji',
                                result.Stripe_Subscription_ID__c,
                                'Stripe_Subscription_ID__c was assigned');
            System.assertEquals('Synced',
                                result.Sync_Status__c,
                                'Sync_Status__c was updated');

        }
    }
    @IsTest
    static void processStripeSubscriptionToCreateSession_createSessionInStripe_success(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Test.setMock(HttpCalloutMock.class, new StripeAPISessionSuccessMock());
            Contact customerContact = new Contact(
                FirstName = 'Test',
                LastName = 'Testov'
            );
            insert customerContact;
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Customer_Email__c = 'test4@example.com',
                Customer_Phone__c = '+1234567894',
                Contact__c = customerContact.Id,
                Stripe_Customer_ID__c = 'cus_THZzLMvNDK5uWm',
                Default_Payment_Method__c = 'pm_1SLhFJF3hNTtzVuGpoRILACR'
            );
            insert customer;
            Stripe_Subscription__c subscriptionRec = new Stripe_Subscription__c(
                Stripe_Price_ID__c = 'price_1SL0u0F3hNTtzVuGs8NtCjiW',
                Stripe_Customer__c = customer.Id,
                Sync_Status__c = 'Synced'
            );
            insert subscriptionRec;
            subscriptionRec = [SELECT Id, Stripe_Price_ID__c, StripeCustomerId__c, Sync_Status__c
                                FROM Stripe_Subscription__c
                                WHERE Id = :subscriptionRec.Id];
            StripeCalloutQueueable queueable = new StripeCalloutQueueable(
                subscriptionRec.StripeCustomerId__c,
                subscriptionRec.Stripe_Price_ID__c,
                subscriptionRec.Id
            );
            Test.startTest();
            System.enqueueJob(queueable);
            Test.stopTest();
            Stripe_Subscription__c result = [SELECT Stripe_Checkout_Session_ID__c, Sync_Status__c, Checkout_URL__c
                                                FROM Stripe_Subscription__c
                                                WHERE Id =: subscriptionRec.Id];
            System.assertEquals('cs_test_a1APLw6wEYwl7TijcXg8BbeHzO4YFQJ3RYmUAFyMWab3YT4BSq9c9x3PlM',
                                result.Stripe_Checkout_Session_ID__c,
                                'Stripe_Subscription_ID__c was assigned');
            System.assertNotEquals(null, result.Checkout_URL__c, 
                                    'Checkout_URL__c was also updated');

        }
    }
    @IsTest
    static void createPricingPlansUponSelection(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Contact customerContact = new Contact(
                FirstName = 'Test',
                LastName = 'Testov'
            );
            insert customerContact;
            Stripe_Customer__c customer = new Stripe_Customer__c(
                Customer_Email__c = 'test4@example.com',
                Customer_Phone__c = '+1234567894',
                Contact__c = customerContact.Id,
                Stripe_Customer_ID__c = 'cus_THZzLMvNDK5uWm',
                Default_Payment_Method__c = 'pm_1SLhFJF3hNTtzVuGpoRILACR'
            );
            insert customer;
            Stripe_Subscription__c subscriptionRec = new Stripe_Subscription__c(
                Stripe_Price_ID__c = 'price_1SL0u0F3hNTtzVuGs8NtCjiW',
                Stripe_Customer__c = customer.Id,
                Sync_Status__c = 'Synced'
            );
            insert subscriptionRec;
            subscriptionRec.PricingPlans__c = 'Basic_Week';
            Test.startTest();
            update subscriptionRec;
            Test.stopTest();
            Pricing_Plan__c result = [SELECT Name, Amount__c, Currency__c, Recurrency_Type__c 
                                            FROM Pricing_Plan__c 
                                            WHERE Stripe_Subscription__c =: subscriptionRec.Id];
            System.assertNotEquals(null, result.Name, 
                                    'Name was assigned');
            System.assertNotEquals(null, result.Amount__c, 
                                    'Amount__c was assigned');
            System.assertNotEquals(null, result.Currency__c, 
                                    'Name was assigned');
            System.assertNotEquals(null, result.Recurrency_Type__c, 
                                    'Name was assigned');
        }
        
        
    }
}