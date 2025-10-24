@isTest
public class PricingPlanTriggerHelperTest {
    private static User testUser;
    // Mock class for successful Stripe API callout
    private class StripeAPIPriceSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id": "price_1SL0u0F3hNTtzVuGs8NtCjiW", "object": "price", "active": true}');
            res.setStatusCode(200);
            return res;
        }
    }
    @TestSetup
    static void setupTestData() {
        // Create test user with Stripe API Access permission set
        testUser = TestDataFactory.createUserWithPermissionSets(
            new List<String>{'Stripe_API_Access', 'CustomMetadataAccess','Stripe_Integration_User','PricingPlanAndPricingTier'}
        );
    }
    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'testuser%@testorg.com' LIMIT 1];
    }
    @IsTest
    static void updateStripePriceIdOnRelatedSubscription_insertAndUpdatePriceId_success(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Test.setMock(HttpCalloutMock.class, new StripeAPIPriceSuccessMock());
            // Create test data
            Stripe_Subscription__c subscription = new Stripe_Subscription__c(
                Product_Plan_Name__c = 'Orange'
            );
            insert subscription;
            Pricing_Plan__c pricePlan = new Pricing_Plan__c(
                Stripe_Subscription__c = subscription.Id,
                Currency__c = 'usd',
                Recurrency_Type__c = 'week',
                Amount__c = 400
            );
            insert pricePlan;
            String requestBody = 'currency=' + EncodingUtil.urlEncode(pricePlan.Currency__c, 'UTF-8') +
                                        '&recurring[interval]=' + EncodingUtil.urlEncode(pricePlan.Recurrency_Type__c.toLowerCase(), 'UTF-8') +
                                        '&unit_amount=' + String.valueOf(pricePlan.Amount__c.longValue()) +
                                        '&product=' + EncodingUtil.urlEncode('prod_THa4qnfsETOFa2', 'UTF-8');
                // Create queueable instance
            StripeCalloutQueueable queueable = new StripeCalloutQueueable(
                pricePlan.Id,
                pricePlan.Currency__c,
                pricePlan.Recurrency_Type__c.toString().replace('ily','y').replace('ly',''),
                pricePlan.Amount__c,
                pricePlan.ProductName__c
            );
            StripeChainedCalloutQueueable secondQueueable = new StripeChainedCalloutQueueable(
                pricePlan.Id,
                requestBody
            );
            Test.startTest();
            System.enqueueJob(queueable);
            System.enqueueJob(secondQueueable);
            Test.stopTest();
            Pricing_Plan__c pricingPlanWithId = [SELECT Stripe_Price_ID__c FROM Pricing_Plan__c WHERE Id =: pricePlan.Id];
            // Verify the result
            System.assertEquals('price_1SL0u0F3hNTtzVuGs8NtCjiW', pricingPlanWithId.Stripe_Price_ID__c, 'Stripe_Price_ID__c is updated');
        }
        
    }

    @IsTest
    static void updateAmountOnRelatedSubscription_insertAndUpdateAmount_success(){
        User testUser = getTestUser();
        System.runAs(testUser){
             // Create test data
            Stripe_Subscription__c subscription = new Stripe_Subscription__c(
                Product_Plan_Name__c = 'Orange'
            );
            insert subscription;
            Pricing_Plan__c pricePlan = new Pricing_Plan__c(
                Stripe_Price_ID__c = 'i98u098u09',
                Stripe_Subscription__c = subscription.Id,
                Currency__c = 'usd',
                Recurrency_Type__c = 'week'
            );
            insert pricePlan;
            pricePlan.Amount__c = 24;
            Test.startTest();
            update pricePlan;
            Test.stopTest();
            // Verify the result
            List<Stripe_Subscription__c> updatedSubscription = [SELECT Amount__c FROM Stripe_Subscription__c WHERE Id =: subscription.Id];
            System.assertEquals(24, updatedSubscription[0].Amount__c, 'Stripe_Price_ID__c is updated on related Stripe_Subscription__c');
        }
        
    }

    @IsTest
    static void createPricingTier_insertPricingPlanWithProperName_success(){
         User testUser = getTestUser();
        System.runAs(testUser){
            // Create test data
            Pricing_Plan__c pricePlan = new Pricing_Plan__c(
                Stripe_Price_ID__c = 'i98u098u09',
                Currency__c = 'usd',
                Recurrency_Type__c = 'week',
                Name = 'Basic_Month'
            );
            Test.startTest();
            insert pricePlan;
            Test.stopTest();
            // Verify the result
            List<Pricing_Tier__c> createdPricingTiers = [SELECT Tier_Number__c, Discount__c, Unit_Price__c FROM Pricing_Tier__c WHERE Pricing_Plan__c =: pricePlan.Id];
            System.assertEquals(1, createdPricingTiers.size(), 'Pricing_Tier__c is created');
            System.assertNotEquals(null, createdPricingTiers[0].Tier_Number__c, 'Tier_Number__c is populated');
            System.assertNotEquals(null, createdPricingTiers[0].Discount__c, 'Discount__c is populated');
            System.assertNotEquals(null, createdPricingTiers[0].Unit_Price__c, 'Unit_Price__c is populated');
        }
        
    }
}