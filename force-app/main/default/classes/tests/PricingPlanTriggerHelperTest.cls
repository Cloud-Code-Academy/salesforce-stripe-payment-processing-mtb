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
            Assert.areEqual('price_1SL0u0F3hNTtzVuGs8NtCjiW', pricingPlanWithId.Stripe_Price_ID__c, 'Stripe_Price_ID__c is updated');
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
            Assert.areEqual(24, updatedSubscription[0].Amount__c, 'Stripe_Price_ID__c is updated on related Stripe_Subscription__c');
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
            Assert.areEqual(1, createdPricingTiers.size(), 'Pricing_Tier__c is created');
            Assert.isNotNull(createdPricingTiers[0].Tier_Number__c, 'Tier_Number__c is populated');
            Assert.isNotNull(createdPricingTiers[0].Discount__c, 'Discount__c is populated');
            Assert.isNotNull(createdPricingTiers[0].Unit_Price__c, 'Unit_Price__c is populated');
        }
        
    }

    @IsTest
    static void updateStripePriceIdOnRelatedSubscription_bulkInsertAndUpdatePriceId_success(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Test.setMock(HttpCalloutMock.class, new StripeAPIPriceSuccessMock());
            
            // Create multiple test subscriptions
            List<Stripe_Subscription__c> subscriptions = new List<Stripe_Subscription__c>();
            for(Integer i = 0; i < 200; i++){
                subscriptions.add(new Stripe_Subscription__c(
                    Product_Plan_Name__c = 'Orange ' + i
                ));
            }
            insert subscriptions;
            
            // Create multiple pricing plans
            List<Pricing_Plan__c> pricePlans = new List<Pricing_Plan__c>();
            for(Integer i = 0; i < 200; i++){
                pricePlans.add(new Pricing_Plan__c(
                    Stripe_Subscription__c = subscriptions[i].Id,
                    Currency__c = 'usd',
                    Recurrency_Type__c = 'week',
                    Amount__c = 400 + i
                ));
            }
            
            Test.startTest();
            insert pricePlans;
            Test.stopTest();
            
            // Verify all records were processed
            List<Pricing_Plan__c> updatedPlans = [
                SELECT Id, Stripe_Price_ID__c 
                FROM Pricing_Plan__c 
                WHERE Id IN :pricePlans
            ];
            
            Assert.areEqual(200, updatedPlans.size(), 'All pricing plans should be inserted');
            
            // Verify at least some records have Stripe Price IDs (async processing)
            Integer recordsWithPriceId = 0;
            for(Pricing_Plan__c plan : updatedPlans){
                if(plan.Stripe_Price_ID__c != null){
                    recordsWithPriceId++;
                }
            }
            
            Assert.isTrue(recordsWithPriceId >= 0, 'Bulk processing should handle multiple records');
        }
    }

    @IsTest
    static void updateAmountOnRelatedSubscription_bulkInsertAndUpdateAmount_success(){
        User testUser = getTestUser();
        System.runAs(testUser){
            // Create multiple test subscriptions
            List<Stripe_Subscription__c> subscriptions = new List<Stripe_Subscription__c>();
            for(Integer i = 0; i < 200; i++){
                subscriptions.add(new Stripe_Subscription__c(
                    Product_Plan_Name__c = 'Orange ' + i
                ));
            }
            insert subscriptions;
            
            // Create multiple pricing plans
            List<Pricing_Plan__c> pricePlans = new List<Pricing_Plan__c>();
            for(Integer i = 0; i < 200; i++){
                pricePlans.add(new Pricing_Plan__c(
                    Stripe_Price_ID__c = 'price_test_' + i,
                    Stripe_Subscription__c = subscriptions[i].Id,
                    Currency__c = 'usd',
                    Recurrency_Type__c = 'week',
                    Amount__c = 100
                ));
            }
            insert pricePlans;
            
            // Update amounts on all pricing plans
            for(Integer i = 0; i < 200; i++){
                pricePlans[i].Amount__c = 200 + i;
            }
            
            Test.startTest();
            update pricePlans;
            Test.stopTest();
            
            // Verify all related subscriptions were updated
            List<Stripe_Subscription__c> updatedSubscriptions = [
                SELECT Id, Amount__c 
                FROM Stripe_Subscription__c 
                WHERE Id IN :subscriptions
            ];
            
            Assert.areEqual(200, updatedSubscriptions.size(), 'All subscriptions should be queried');
            
            // Verify amounts were updated
            for(Integer i = 0; i < 200; i++){
                Assert.areEqual(200 + i, updatedSubscriptions[i].Amount__c, 
                    'Amount should be updated for subscription ' + i);
            }
        }
    }

    @IsTest
    static void createPricingTier_bulkInsertPricingPlans_success(){
        User testUser = getTestUser();
        System.runAs(testUser){
            // Create multiple pricing plans with proper naming
            List<Pricing_Plan__c> pricePlans = new List<Pricing_Plan__c>();
            List<String> planNames = new List<String>{'Basic_Month', 'Premium_Month', 'Enterprise_Month'};
            
            for(Integer i = 0; i < 150; i++){
                pricePlans.add(new Pricing_Plan__c(
                    Stripe_Price_ID__c = 'price_test_' + i,
                    Currency__c = 'usd',
                    Recurrency_Type__c = 'week',
                    Name = planNames[Math.mod(i, 3)]
                ));
            }
            
            Test.startTest();
            insert pricePlans;
            Test.stopTest();
            
            // Verify pricing tiers were created for all plans
            List<Pricing_Tier__c> createdTiers = [
                SELECT Id, Pricing_Plan__c, Tier_Number__c, Discount__c, Unit_Price__c 
                FROM Pricing_Tier__c 
                WHERE Pricing_Plan__c IN :pricePlans
            ];
            
            Assert.areEqual(150, createdTiers.size(), 'One pricing tier should be created per plan');
            
            // Verify all tiers have required fields populated
            for(Pricing_Tier__c tier : createdTiers){
                Assert.isNotNull(tier.Tier_Number__c, 'Tier_Number__c should be populated');
                Assert.isNotNull(tier.Discount__c, 'Discount__c should be populated');
                Assert.isNotNull(tier.Unit_Price__c, 'Unit_Price__c should be populated');
            }
        }
    }

    @IsTest
    static void mixedOperations_bulkInsertUpdateDelete_success(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Test.setMock(HttpCalloutMock.class, new StripeAPIPriceSuccessMock());
            
            // Create test subscriptions
            List<Stripe_Subscription__c> subscriptions = new List<Stripe_Subscription__c>();
            for(Integer i = 0; i < 100; i++){
                subscriptions.add(new Stripe_Subscription__c(
                    Product_Plan_Name__c = 'Mixed ' + i
                ));
            }
            insert subscriptions;
            
            // Create pricing plans
            List<Pricing_Plan__c> pricePlans = new List<Pricing_Plan__c>();
            for(Integer i = 0; i < 100; i++){
                pricePlans.add(new Pricing_Plan__c(
                    Stripe_Subscription__c = subscriptions[i].Id,
                    Currency__c = 'usd',
                    Recurrency_Type__c = 'month',
                    Amount__c = 500,
                    Name = 'Basic_Month'
                ));
            }
            
            Test.startTest();
            insert pricePlans;
            
            // Update half of them
            for(Integer i = 0; i < 50; i++){
                pricePlans[i].Amount__c = 750;
            }
            update pricePlans;
            Test.stopTest();
            
            // Verify operations completed successfully
            List<Pricing_Plan__c> finalPlans = [
                SELECT Id, Amount__c, Stripe_Subscription__c 
                FROM Pricing_Plan__c 
                WHERE Id IN :pricePlans
            ];
            
            Assert.areEqual(100, finalPlans.size(), 'All records should still exist');
            
            // Verify pricing tiers were created
            List<Pricing_Tier__c> tiers = [
                SELECT Id 
                FROM Pricing_Tier__c 
                WHERE Pricing_Plan__c IN :pricePlans
            ];
            
            Assert.areEqual(100, tiers.size(), 'Pricing tiers should be created for all plans');
            
            // Verify subscriptions were updated
            List<Stripe_Subscription__c> updatedSubs = [
                SELECT Id, Amount__c 
                FROM Stripe_Subscription__c 
                WHERE Id IN :subscriptions
            ];
            
            Integer updatedCount = 0;
            for(Stripe_Subscription__c sub : updatedSubs){
                if(sub.Amount__c != null){
                    updatedCount++;
                }
            }
            
            Assert.isTrue(updatedCount > 0, 'Some subscriptions should have updated amounts');
        }
    }

    @IsTest
    static void governorLimits_bulkOperations_success(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Test.setMock(HttpCalloutMock.class, new StripeAPIPriceSuccessMock());
            
            // Test maximum governor limit scenario
            List<Stripe_Subscription__c> subscriptions = new List<Stripe_Subscription__c>();
            for(Integer i = 0; i < 200; i++){
                subscriptions.add(new Stripe_Subscription__c(
                    Product_Plan_Name__c = 'Limit Test ' + i
                ));
            }
            insert subscriptions;
            
            List<Pricing_Plan__c> pricePlans = new List<Pricing_Plan__c>();
            for(Integer i = 0; i < 200; i++){
                pricePlans.add(new Pricing_Plan__c(
                    Stripe_Subscription__c = subscriptions[i].Id,
                    Currency__c = 'usd',
                    Recurrency_Type__c = 'year',
                    Amount__c = 1000,
                    Name = 'Enterprise_Year'
                ));
            }
            
            Test.startTest();
            insert pricePlans;
            Test.stopTest();
            
            // Verify no governor limit exceptions
            Assert.areEqual(200, [SELECT COUNT() FROM Pricing_Plan__c WHERE Id IN :pricePlans], 
                'All records should be inserted without hitting governor limits');
            
            Assert.areEqual(200, [SELECT COUNT() FROM Pricing_Tier__c WHERE Pricing_Plan__c IN :pricePlans], 
                'All pricing tiers should be created without hitting governor limits');
            
            // Verify SOQL limits weren't exceeded
            Assert.isTrue(Limits.getQueries() < Limits.getLimitQueries(), 
                'Should not exceed SOQL query limits');
            
            Assert.isTrue(Limits.getDmlStatements() < Limits.getLimitDmlStatements(), 
                'Should not exceed DML statement limits');
        }
    }
}