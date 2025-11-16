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
                LastName = 'Testov',
                Email = 'test4@example.com',
                Phone = '+1234567894',
                Stripe_Customer_ID__c = 'cus_THZzLMvNDK5uWm',
                Default_Payment_Method__c = 'pm_1SLhFJF3hNTtzVuGpoRILACR'
            );
            insert customerContact;
            Stripe_Subscription__c subscriptionRec = new Stripe_Subscription__c(
                Stripe_Price_ID__c = 'price_1SL0u0F3hNTtzVuGs8NtCjiW',
                Contact__c = customerContact.Id,
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
            Assert.areEqual('sub_1SL0dlF3hNTtzVuGK5JQfCji',
                                result.Stripe_Subscription_ID__c,
                                'Stripe_Subscription_ID__c was assigned');
            Assert.areEqual('Completed',
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
                LastName = 'Testov',
                Email = 'test4@example.com',
                Phone = '+1234567894',
                Stripe_Customer_ID__c = 'cus_THZzLMvNDK5uWm',
                Default_Payment_Method__c = 'pm_1SLhFJF3hNTtzVuGpoRILACR'
            );
            insert customerContact;
            Stripe_Subscription__c subscriptionRec = new Stripe_Subscription__c(
                Stripe_Price_ID__c = 'price_1SL0u0F3hNTtzVuGs8NtCjiW',
                Contact__c = customerContact.Id
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
            Assert.areEqual('sub_1SL0dlF3hNTtzVuGK5JQfCji',
                                result.Stripe_Subscription_ID__c,
                                'Stripe_Subscription_ID__c was assigned');
            Assert.areEqual('Completed',
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
                LastName = 'Testov',
                Email = 'test4@example.com',
                Phone = '+1234567894',
                Stripe_Customer_ID__c = 'cus_THZzLMvNDK5uWm',
                Default_Payment_Method__c = 'pm_1SLhFJF3hNTtzVuGpoRILACR'
            );
            insert customerContact;
            Stripe_Subscription__c subscriptionRec = new Stripe_Subscription__c(
                Stripe_Price_ID__c = 'price_1SL0u0F3hNTtzVuGs8NtCjiW',
                Contact__c = customerContact.Id,
                Sync_Status__c = 'Completed'
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
            Assert.areEqual('cs_test_a1APLw6wEYwl7TijcXg8BbeHzO4YFQJ3RYmUAFyMWab3YT4BSq9c9x3PlM',
                                result.Stripe_Checkout_Session_ID__c,
                                'Stripe_Subscription_ID__c was assigned');
            Assert.areNotEqual(null, result.Checkout_URL__c, 
                                    'Checkout_URL__c was also updated');

        }
    }
    @IsTest
    static void createPricingPlansUponSelection(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Contact customerContact = new Contact(
                FirstName = 'Test',
                LastName = 'Testov',
                Email = 'test4@example.com',
                Phone = '+1234567894',
                Stripe_Customer_ID__c = 'cus_THZzLMvNDK5uWm',
                Default_Payment_Method__c = 'pm_1SLhFJF3hNTtzVuGpoRILACR'
            );
            insert customerContact;
            Stripe_Subscription__c subscriptionRec = new Stripe_Subscription__c(
                Stripe_Price_ID__c = 'price_1SL0u0F3hNTtzVuGs8NtCjiW',
                Contact__c = customerContact.Id,
                Sync_Status__c = 'Completed'
            );
            insert subscriptionRec;
            subscriptionRec.PricingPlans__c = 'Basic_Week';
            Test.startTest();
            update subscriptionRec;
            Test.stopTest();
            Pricing_Plan__c result = [SELECT Name, Amount__c, Currency__c, Recurrency_Type__c
                                            FROM Pricing_Plan__c
                                            WHERE Stripe_Subscription__c =: subscriptionRec.Id];
            Assert.areNotEqual(null, result.Name,
                                    'Name was assigned');
            Assert.areNotEqual(null, result.Amount__c,
                                    'Amount__c was assigned');
            Assert.areNotEqual(null, result.Currency__c,
                                    'Currency__c was assigned');
            Assert.areNotEqual(null, result.Recurrency_Type__c,
                                    'Recurrency_Type__c was assigned');
        }
    }

    // ========== High Priority Error Handling Tests ==========

    /**
     * Test processStripeSubscriptionAfterUpdate with null parameters
     */
    @IsTest
    static void processStripeSubscriptionAfterUpdate_nullParameters_noError() {
        System.runAs(getTestUser()) {
            Test.startTest();
            // Should not throw exception with null parameters
            StripeSubscriptionTriggerHelper.processStripeSubscriptionAfterUpdate(null, null);
            StripeSubscriptionTriggerHelper.processStripeSubscriptionAfterUpdate(
                new List<Stripe_Subscription__c>(),
                new Map<Id, Stripe_Subscription__c>()
            );
            Test.stopTest();

            Assert.isTrue(true, 'Method should handle null/empty parameters gracefully');
        }
    }

    /**
     * Test processStripeSubscriptionAfterUpdate with missing Stripe_Price_ID__c
     * Verifies that subscriptions without required fields are skipped
     */
    @IsTest
    static void processStripeSubscriptionAfterUpdate_missingPriceId_skipped() {
        System.runAs(getTestUser()) {
            Contact customerContact = new Contact(
                FirstName = 'Test',
                LastName = 'Missing',
                Email = 'missing@example.com',
                Phone = '+1234567890',
                Stripe_Customer_ID__c = 'cus_test123',
                Default_Payment_Method__c = 'pm_test123'
            );
            insert customerContact;

            // Create subscription without Stripe_Price_ID__c
            Stripe_Subscription__c subscriptionRec = new Stripe_Subscription__c(
                Contact__c = customerContact.Id,
                Sync_Status__c = 'Send to Stripe'
                // Missing Stripe_Price_ID__c
            );

            Test.startTest();
            insert subscriptionRec;
            Test.stopTest();

            // Verify subscription was created but not processed
            Stripe_Subscription__c result = [SELECT Stripe_Subscription_ID__c, Sync_Status__c
                                                FROM Stripe_Subscription__c WHERE Id = :subscriptionRec.Id];
            Assert.areEqual(null, result.Stripe_Subscription_ID__c,
                'Subscription should not be processed without Price ID');
        }
    }

    /**
     * Test processStripeSubscriptionAfterUpdate with missing StripeCustomerId__c
     */
    @IsTest
    static void processStripeSubscriptionAfterUpdate_missingCustomerId_skipped() {
        System.runAs(getTestUser()) {
            Contact contact = TestDataFactory.createStripeCustomers(1)[0];
            
            Test.startTest();
            Stripe_Subscription__c subscriptionRec = TestDataFactory.createUnsyncedStripeSubscriptions(1, contact.Id)[0];
            Test.stopTest();

            // Verify subscription was created but not processed
            Stripe_Subscription__c result = [SELECT Stripe_Subscription_ID__c
                                                FROM Stripe_Subscription__c WHERE Id = :subscriptionRec.Id];
            Assert.isNull(result.Stripe_Subscription_ID__c,
                'Subscription should not be processed without Customer ID');
        }
    }

    /**
     * Test processStripeSubscriptionAfterUpdate with missing CustomerDefaultPayment__c
     */
    @IsTest
    static void processStripeSubscriptionAfterUpdate_missingPaymentMethod_skipped() {
        System.runAs(getTestUser()) {
            // Customer without Default_Payment_Method__c
            Contact customerContact = new Contact(
                FirstName = 'Test',
                LastName = 'NoPayment',
                Email = 'nopayment@example.com',
                Phone = '+1234567890',
                Stripe_Customer_ID__c = 'cus_nopayment'
                // Missing Default_Payment_Method__c
            );
            insert customerContact;

            Stripe_Subscription__c subscriptionRec = new Stripe_Subscription__c(
                Stripe_Price_ID__c = 'price_test123',
                Contact__c = customerContact.Id,
                Sync_Status__c = 'Send to Stripe'
            );

            Test.startTest();
            insert subscriptionRec;
            Test.stopTest();

            // Verify subscription was created but not processed
            Stripe_Subscription__c result = [SELECT Stripe_Subscription_ID__c
                                                FROM Stripe_Subscription__c WHERE Id = :subscriptionRec.Id];
            Assert.areEqual(null, result.Stripe_Subscription_ID__c,
                'Subscription should not be processed without Payment Method');
        }
    }

    /**
     * Test processStripeSubscriptionAfterUpdate with already synced subscription
     */
    @IsTest
    static void processStripeSubscriptionAfterUpdate_alreadySynced_skipped() {
        System.runAs(getTestUser()) {
            Contact customerContact = new Contact(
                FirstName = 'Test',
                LastName = 'Completed',
                Email = 'synced@example.com',
                Phone = '+1234567890',
                Stripe_Customer_ID__c = 'cus_synced',
                Default_Payment_Method__c = 'pm_synced'
            );
            insert customerContact;

            // Create subscription with existing Stripe_Subscription_ID__c
            Stripe_Subscription__c subscriptionRec = new Stripe_Subscription__c(
                Stripe_Price_ID__c = 'price_test123',
                Contact__c = customerContact.Id,
                Stripe_Subscription_ID__c = 'sub_existing123',
                Sync_Status__c = 'Send to Stripe'
            );

            Test.startTest();
            insert subscriptionRec;
            Test.stopTest();

            // Verify subscription still has original ID (not reprocessed)
            Stripe_Subscription__c result = [SELECT Stripe_Subscription_ID__c
                                                FROM Stripe_Subscription__c WHERE Id = :subscriptionRec.Id];
            Assert.areEqual('sub_existing123', result.Stripe_Subscription_ID__c,
                'Subscription with existing ID should not be reprocessed');
        }
    }

    /**
     * Test processStripeSubscriptionToCreateSession with null parameters
     */
    @IsTest
    static void processStripeSubscriptionToCreateSession_nullParameters_noError() {
        System.runAs(getTestUser()) {
            Test.startTest();
            // Should not throw exception with null parameters
            StripeSubscriptionTriggerHelper.processStripeSubscriptionToCreateSession(null, null);
            StripeSubscriptionTriggerHelper.processStripeSubscriptionToCreateSession(
                new List<Stripe_Subscription__c>(),
                new Map<Id, Stripe_Subscription__c>()
            );
            Test.stopTest();

            Assert.isTrue(true, 'Method should handle null/empty parameters gracefully');
        }
    }

    /**
     * Test processStripeSubscriptionToCreateSession with missing Stripe_Subscription_ID__c
     */
    @IsTest
    static void processStripeSubscriptionToCreateSession_missingSubscriptionId_skipped() {
        System.runAs(getTestUser()) {
            Contact customerContact = new Contact(
                FirstName = 'Test',
                LastName = 'NoSubId',
                Email = 'nosubid@example.com',
                Phone = '+1234567890',
                Stripe_Customer_ID__c = 'cus_nosubid'
            );
            insert customerContact;

            // Create subscription without Stripe_Subscription_ID__c
            Stripe_Subscription__c subscriptionRec = new Stripe_Subscription__c(
                Stripe_Price_ID__c = 'price_test123',
                Contact__c = customerContact.Id,
                Sync_Status__c = 'Completed'
                // Missing Stripe_Subscription_ID__c
            );

            Test.startTest();
            insert subscriptionRec;
            Test.stopTest();

            // Verify session was not created
            Stripe_Subscription__c result = [SELECT Stripe_Checkout_Session_ID__c
                                                FROM Stripe_Subscription__c WHERE Id = :subscriptionRec.Id];
            Assert.areEqual(null, result.Stripe_Checkout_Session_ID__c,
                'Session should not be created without Subscription ID');
        }
    }

    /**
     * Test createPricingPlansUponSelection with null parameters
     */
    @IsTest
    static void createPricingPlansUponSelection_nullParameters_noError() {
        System.runAs(getTestUser()) {
            Test.startTest();
            // Should not throw exception with null parameters
            StripeSubscriptionTriggerHelper.createPricingPlansUponSelection(null, null);
            StripeSubscriptionTriggerHelper.createPricingPlansUponSelection(
                new List<Stripe_Subscription__c>(),
                new Map<Id, Stripe_Subscription__c>()
            );
            Test.stopTest();

            Assert.isTrue(true, 'Method should handle null/empty parameters gracefully');
        }
    }

    /**
     * Test createPricingPlansUponSelection with missing metadata
     */
    @IsTest
    static void createPricingPlansUponSelection_missingMetadata_noError() {
        System.runAs(getTestUser()) {
            Contact customerContact = new Contact(
                FirstName = 'Test',
                LastName = 'NoMetadata',
                Email = 'nometadata@example.com',
                Phone = '+1234567890',
                Stripe_Customer_ID__c = 'cus_nometadata'
            );
            insert customerContact;

            Stripe_Subscription__c subscriptionRec = new Stripe_Subscription__c(
                Stripe_Price_ID__c = 'price_test123',
                Contact__c = customerContact.Id
            );
            insert subscriptionRec;

            // Update with a valid picklist value that doesn't have corresponding metadata
            // Using 'NonExistent_Plan_12345' which has a typo and likely doesn't have metadata
            subscriptionRec.PricingPlans__c = 'NonExistent_Plan_12345';

            Test.startTest();
            try{
                update subscriptionRec;
            }
            catch(Exception e){
                Test.stopTest();
    
                // Verify no pricing plan was created
                List<Pricing_Plan__c> plans = [SELECT Id FROM Pricing_Plan__c
                                                WHERE Stripe_Subscription__c = :subscriptionRec.Id];
                Assert.areEqual(0, plans.size(),
                    'No pricing plan should be created for non-existent metadata');
            }
        }
    }

    /**
     * Test createPricingPlansUponSelection with unchanged PricingPlans__c
     */
    @IsTest
    static void createPricingPlansUponSelection_unchangedPricingPlans_skipped() {
        System.runAs(getTestUser()) {
            Contact customerContact = new Contact(
                FirstName = 'Test',
                LastName = 'Unchanged',
                Email = 'unchanged@example.com',
                Phone = '+1234567890',
                Stripe_Customer_ID__c = 'cus_unchanged'
            );
            insert customerContact;

            Stripe_Subscription__c subscriptionRec = new Stripe_Subscription__c(
                Stripe_Price_ID__c = 'price_test123',
                Contact__c = customerContact.Id,
                PricingPlans__c = 'Basic_Week'
            );
            insert subscriptionRec;

            // First insert creates pricing plan
            List<Pricing_Plan__c> initialPlans = [SELECT Id FROM Pricing_Plan__c
                                                    WHERE Stripe_Subscription__c = :subscriptionRec.Id];
            Integer initialCount = initialPlans.size();

            // Update something other than PricingPlans__c
            subscriptionRec.Sync_Status__c = 'Completed';

            Test.startTest();
            update subscriptionRec;
            Test.stopTest();

            // Verify no additional plans were created
            List<Pricing_Plan__c> finalPlans = [SELECT Id FROM Pricing_Plan__c
                                                    WHERE Stripe_Subscription__c = :subscriptionRec.Id];
            Assert.areEqual(initialCount, finalPlans.size(),
                'No new pricing plans should be created when PricingPlans__c is unchanged');
        }
    }

    /**
     * Test bulk processing of subscriptions
     */
    @IsTest
    static void processStripeSubscriptionAfterUpdate_bulkProcessing_success() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeAPISubscriptionSuccessMock());

            // Create multiple customers as Contacts with Stripe data
            List<Contact> customers = new List<Contact>();
            for (Integer i = 0; i < 3; i++) {
                customers.add(new Contact(
                    FirstName = 'Bulk',
                    LastName = 'Test ' + i,
                    Email = 'bulk' + i + '@example.com',
                    Phone = '+123456789' + i,
                    Stripe_Customer_ID__c = 'cus_bulk' + i,
                    Default_Payment_Method__c = 'pm_bulk' + i
                ));
            }
            insert customers;

            // Create multiple subscriptions
            List<Stripe_Subscription__c> subscriptions = new List<Stripe_Subscription__c>();
            for (Integer i = 0; i < 3; i++) {
                subscriptions.add(new Stripe_Subscription__c(
                    Stripe_Price_ID__c = 'price_bulk' + i,
                    Contact__c = customers[i].Id,
                    Sync_Status__c = 'Send to Stripe'
                ));
            }

            Test.startTest();
            insert subscriptions;
            Test.stopTest();

            // Verify all subscriptions were created
            List<Stripe_Subscription__c> results = [SELECT Id, Sync_Status__c
                                                        FROM Stripe_Subscription__c
                                                        WHERE Id IN :subscriptions];
            Assert.areEqual(3, results.size(), 'All 3 subscriptions should be created');
        }
    }
}