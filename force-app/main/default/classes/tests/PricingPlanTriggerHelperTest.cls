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

            // Query to get the ProductName__c value (formula field)
            pricePlan = [SELECT Id, Currency__c, Recurrency_Type__c, Amount__c, ProductName__c
                         FROM Pricing_Plan__c WHERE Id = :pricePlan.Id];

            String requestBody = 'currency=' + EncodingUtil.urlEncode(pricePlan.Currency__c, 'UTF-8') +
                                        '&recurring[interval]=' + EncodingUtil.urlEncode(pricePlan.Recurrency_Type__c.toLowerCase(), 'UTF-8') +
                                        '&unit_amount=' + String.valueOf(pricePlan.Amount__c.longValue()) +
                                        '&product=' + EncodingUtil.urlEncode('prod_THa4qnfsETOFa2', 'UTF-8');

            // Create queueable for CREATE_PRICING_PLAN path
            StripeChainedCalloutQueueable queueable = new StripeChainedCalloutQueueable(
                pricePlan.Id,
                requestBody
            );

            Test.startTest();
            System.enqueueJob(queueable);
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
            Assert.areNotEqual(null, createdPricingTiers[0].Tier_Number__c, 'Tier_Number__c is populated');
            Assert.areNotEqual(null, createdPricingTiers[0].Discount__c, 'Discount__c is populated');
            Assert.areNotEqual(null, createdPricingTiers[0].Unit_Price__c, 'Unit_Price__c is populated');
        }

    }

    /**
     * @description Tests that multiple pricing plans referencing the same subscription
     *              don't cause a System.ListException: Duplicate id in list error.
     *              Verifies that the Map-based approach correctly handles duplicates
     *              and updates the subscription only once.
     */
    @IsTest
    static void updateStripePriceIdOnRelatedSubscription_multiplePlansReferenceSameSubscription_noDuplicateError(){
        User testUser = getTestUser();
        System.runAs(testUser){
            // Create one subscription that will be referenced by multiple pricing plans
            Stripe_Subscription__c subscription = new Stripe_Subscription__c(
                Product_Plan_Name__c = 'Shared Subscription',
                Stripe_Price_ID__c = 'price_initial_123'
            );
            insert subscription;

            // Create three pricing plans that all reference the same subscription
            List<Pricing_Plan__c> pricingPlans = new List<Pricing_Plan__c>{
                new Pricing_Plan__c(
                    Stripe_Subscription__c = subscription.Id,
                    Stripe_Price_ID__c = 'price_plan_A_111',
                    Currency__c = 'usd',
                    Recurrency_Type__c = 'month',
                    Amount__c = 100
                ),
                new Pricing_Plan__c(
                    Stripe_Subscription__c = subscription.Id,
                    Stripe_Price_ID__c = 'price_plan_B_222',
                    Currency__c = 'usd',
                    Recurrency_Type__c = 'month',
                    Amount__c = 200
                ),
                new Pricing_Plan__c(
                    Stripe_Subscription__c = subscription.Id,
                    Stripe_Price_ID__c = 'price_plan_C_333',
                    Currency__c = 'usd',
                    Recurrency_Type__c = 'month',
                    Amount__c = 300
                )
            };
            insert pricingPlans;

            // Update all pricing plans' Stripe_Price_ID__c to trigger the helper method
            pricingPlans[0].Stripe_Price_ID__c = 'price_updated_A_999';
            pricingPlans[1].Stripe_Price_ID__c = 'price_updated_B_888';
            pricingPlans[2].Stripe_Price_ID__c = 'price_updated_C_777';

            Test.startTest();
            // This should NOT throw System.ListException: Duplicate id in list
            update pricingPlans;
            Test.stopTest();

            // Verify the subscription was updated (only once, with the last value from the map)
            Stripe_Subscription__c updatedSubscription = [
                SELECT Stripe_Price_ID__c
                FROM Stripe_Subscription__c
                WHERE Id = :subscription.Id
            ];

            // The subscription should have one of the updated price IDs (last-write-wins behavior)
            Assert.isTrue(
                updatedSubscription.Stripe_Price_ID__c == 'price_updated_A_999' ||
                updatedSubscription.Stripe_Price_ID__c == 'price_updated_B_888' ||
                updatedSubscription.Stripe_Price_ID__c == 'price_updated_C_777',
                'Subscription Stripe_Price_ID__c should be updated to one of the pricing plan values'
            );

            // Most importantly: No exception should have been thrown
            Assert.areNotEqual(
                'price_initial_123',
                updatedSubscription.Stripe_Price_ID__c,
                'Subscription Stripe_Price_ID__c should have been updated from initial value'
            );
        }
    }

    /**
     * @description Tests that multiple pricing plans referencing the same subscription
     *              don't cause a System.ListException: Duplicate id in list error when updating amounts.
     *              Verifies that the Map-based approach correctly handles duplicates
     *              and updates the subscription amount only once.
     */
    @IsTest
    static void updateAmountOnRelatedSubscription_multiplePlansReferenceSameSubscription_noDuplicateError(){
        User testUser = getTestUser();
        System.runAs(testUser){
            // Create one subscription that will be referenced by multiple pricing plans
            Stripe_Subscription__c subscription = new Stripe_Subscription__c(
                Product_Plan_Name__c = 'Shared Subscription',
                Amount__c = 50
            );
            insert subscription;

            // Create three pricing plans that all reference the same subscription
            List<Pricing_Plan__c> pricingPlans = new List<Pricing_Plan__c>{
                new Pricing_Plan__c(
                    Stripe_Subscription__c = subscription.Id,
                    Stripe_Price_ID__c = 'price_plan_A',
                    Currency__c = 'usd',
                    Recurrency_Type__c = 'month',
                    Amount__c = 100
                ),
                new Pricing_Plan__c(
                    Stripe_Subscription__c = subscription.Id,
                    Stripe_Price_ID__c = 'price_plan_B',
                    Currency__c = 'usd',
                    Recurrency_Type__c = 'month',
                    Amount__c = 200
                ),
                new Pricing_Plan__c(
                    Stripe_Subscription__c = subscription.Id,
                    Stripe_Price_ID__c = 'price_plan_C',
                    Currency__c = 'usd',
                    Recurrency_Type__c = 'month',
                    Amount__c = 300
                )
            };
            insert pricingPlans;

            // Update all pricing plans' amounts to trigger the helper method
            pricingPlans[0].Amount__c = 150;
            pricingPlans[1].Amount__c = 250;
            pricingPlans[2].Amount__c = 350;

            Test.startTest();
            // This should NOT throw System.ListException: Duplicate id in list
            update pricingPlans;
            Test.stopTest();

            // Verify the subscription amount was updated (only once, with the last value from the map)
            Stripe_Subscription__c updatedSubscription = [
                SELECT Amount__c
                FROM Stripe_Subscription__c
                WHERE Id = :subscription.Id
            ];

            // The subscription should have one of the updated amounts (last-write-wins behavior)
            Assert.isTrue(
                updatedSubscription.Amount__c == 150 ||
                updatedSubscription.Amount__c == 250 ||
                updatedSubscription.Amount__c == 350,
                'Subscription Amount__c should be updated to one of the pricing plan amounts'
            );

            // Most importantly: No exception should have been thrown
            Assert.areNotEqual(
                50,
                updatedSubscription.Amount__c,
                'Subscription Amount__c should have been updated from initial value'
            );
        }
    }

    /**
     * @description Tests edge case where a single pricing plan is updated normally
     *              to ensure the Map-based approach doesn't break single-record updates.
     */
    @IsTest
    static void updateStripePriceIdOnRelatedSubscription_singlePlanUpdate_success(){
        User testUser = getTestUser();
        System.runAs(testUser){
            // Create subscription and single pricing plan
            Stripe_Subscription__c subscription = new Stripe_Subscription__c(
                Product_Plan_Name__c = 'Single Plan Subscription',
                Stripe_Price_ID__c = 'price_initial'
            );
            insert subscription;

            Pricing_Plan__c pricePlan = new Pricing_Plan__c(
                Stripe_Subscription__c = subscription.Id,
                Stripe_Price_ID__c = 'price_original',
                Currency__c = 'usd',
                Recurrency_Type__c = 'month',
                Amount__c = 100
            );
            insert pricePlan;

            // Update the pricing plan's price ID
            pricePlan.Stripe_Price_ID__c = 'price_updated_single';

            Test.startTest();
            update pricePlan;
            Test.stopTest();

            // Verify the subscription was updated correctly
            Stripe_Subscription__c updatedSubscription = [
                SELECT Stripe_Price_ID__c
                FROM Stripe_Subscription__c
                WHERE Id = :subscription.Id
            ];

            Assert.areEqual(
                'price_updated_single',
                updatedSubscription.Stripe_Price_ID__c,
                'Single pricing plan update should work correctly with Map approach'
            );
        }
    }

    // ========== High Priority Error Handling Tests ==========

    /**
     * @description Tests that updateStripePriceIdOnRelatedSubscription handles null parameters gracefully
     */
    @IsTest
    static void updateStripePriceIdOnRelatedSubscription_nullParameters_noError(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Test.startTest();
            // Should not throw exception with null parameters
            PricingPlanTriggerHelper.updateStripePriceIdOnRelatedSubscription(null, null);
            PricingPlanTriggerHelper.updateStripePriceIdOnRelatedSubscription(new List<Pricing_Plan__c>(), new Map<Id, Pricing_Plan__c>());
            Test.stopTest();

            // Verify no subscriptions were updated
            List<Stripe_Subscription__c> subscriptions = [SELECT Id FROM Stripe_Subscription__c];
            Assert.areEqual(0, subscriptions.size(), 'No subscriptions should exist after null parameter calls');
        }
    }

    /**
     * @description Tests that updateAmountOnRelatedSubscription handles null parameters gracefully
     */
    @IsTest
    static void updateAmountOnRelatedSubscription_nullParameters_noError(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Test.startTest();
            // Should not throw exception with null parameters
            PricingPlanTriggerHelper.updateAmountOnRelatedSubscription(null, null);
            PricingPlanTriggerHelper.updateAmountOnRelatedSubscription(new List<Pricing_Plan__c>(), null); // oldMap can be null on insert
            Test.stopTest();

            // Verify no subscriptions were updated
            List<Stripe_Subscription__c> subscriptions = [SELECT Id FROM Stripe_Subscription__c];
            Assert.areEqual(0, subscriptions.size(), 'No subscriptions should exist after null parameter calls');
        }
    }

    /**
     * @description Tests that pricing plan with blank Stripe_Price_ID__c is skipped
     */
    @IsTest
    static void updateStripePriceIdOnRelatedSubscription_blankPriceId_skipped(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Stripe_Subscription__c subscription = new Stripe_Subscription__c(
                Product_Plan_Name__c = 'Test',
                Stripe_Price_ID__c = 'original_price'
            );
            insert subscription;

            Pricing_Plan__c pricePlan = new Pricing_Plan__c(
                Stripe_Subscription__c = subscription.Id,
                Stripe_Price_ID__c = 'price_123',
                Currency__c = 'usd',
                Recurrency_Type__c = 'month',
                Amount__c = 100
            );
            insert pricePlan;

            // Update with blank price ID
            pricePlan.Stripe_Price_ID__c = '';

            Test.startTest();
            update pricePlan;
            Test.stopTest();

            // Verify subscription was NOT updated (blank price ID should be skipped)
            Stripe_Subscription__c updatedSubscription = [SELECT Stripe_Price_ID__c FROM Stripe_Subscription__c WHERE Id = :subscription.Id];
            Assert.areEqual('original_price', updatedSubscription.Stripe_Price_ID__c, 'Subscription should retain original price when plan has blank price ID');
        }
    }

    /**
     * @description Tests that pricing plan without Stripe_Subscription__c reference is skipped
     */
    @IsTest
    static void updateStripePriceIdOnRelatedSubscription_noSubscription_skipped(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Pricing_Plan__c pricePlan = new Pricing_Plan__c(
                Stripe_Price_ID__c = 'price_orphan',
                Currency__c = 'usd',
                Recurrency_Type__c = 'month',
                Amount__c = 100
                // No Stripe_Subscription__c reference
            );
            insert pricePlan;

            // Update price ID
            pricePlan.Stripe_Price_ID__c = 'price_orphan_updated';

            Test.startTest();
            update pricePlan;
            Test.stopTest();

            // Should complete without error (orphan plans are skipped)
            Pricing_Plan__c updatedPlan = [SELECT Stripe_Price_ID__c FROM Pricing_Plan__c WHERE Id = :pricePlan.Id];
            Assert.areEqual('price_orphan_updated', updatedPlan.Stripe_Price_ID__c, 'Plan should be updated even without subscription reference');
        }
    }

    /**
     * @description Tests that unchanged price ID is skipped (oldMap shows same value)
     */
    @IsTest
    static void updateStripePriceIdOnRelatedSubscription_unchangedPriceId_skipped(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Stripe_Subscription__c subscription = new Stripe_Subscription__c(
                Product_Plan_Name__c = 'Test',
                Stripe_Price_ID__c = 'original_price'
            );
            insert subscription;

            Pricing_Plan__c pricePlan = new Pricing_Plan__c(
                Stripe_Subscription__c = subscription.Id,
                Stripe_Price_ID__c = 'price_123',
                Currency__c = 'usd',
                Recurrency_Type__c = 'month',
                Amount__c = 100
            );
            insert pricePlan;

            // Update amount but keep price ID the same
            pricePlan.Amount__c = 200;

            Test.startTest();
            update pricePlan;
            Test.stopTest();

            // Subscription price should remain unchanged
            Stripe_Subscription__c updatedSubscription = [SELECT Stripe_Price_ID__c, Amount__c FROM Stripe_Subscription__c WHERE Id = :subscription.Id];
            Assert.areEqual('original_price', updatedSubscription.Stripe_Price_ID__c, 'Subscription price ID should not change when plan price ID is unchanged');
            Assert.areEqual(200, updatedSubscription.Amount__c, 'Amount should be updated');
        }
    }

    /**
     * @description Tests processPricingPlanAfterInsert with null parameters
     */
    @IsTest
    static void processPricingPlanAfterInsert_nullParameters_noError(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Test.startTest();
            // Should not throw exception with null parameters
            PricingPlanTriggerHelper.processPricingPlanAfterInsert(null);
            PricingPlanTriggerHelper.processPricingPlanAfterInsert(new List<Pricing_Plan__c>());
            Test.stopTest();

            // Should complete without errors
            Assert.isTrue(true, 'Method should handle null/empty parameters gracefully');
        }
    }

    /**
     * @description Tests that pricing plan with existing Stripe_Price_ID__c is skipped
     */
    @IsTest
    static void processPricingPlanAfterInsert_existingPriceId_skipped(){
        User testUser = getTestUser();
        System.runAs(testUser){
            // Create pricing plan that already has a Stripe_Price_ID__c
            Pricing_Plan__c pricePlan = new Pricing_Plan__c(
                Stripe_Price_ID__c = 'existing_price_123',
                Currency__c = 'usd',
                Recurrency_Type__c = 'month',
                Amount__c = 100
            );

            Test.startTest();
            insert pricePlan;
            Test.stopTest();

            // Since price ID already exists, no queueable should be enqueued
            // Verify the plan still has the original price ID
            Pricing_Plan__c inserted = [SELECT Stripe_Price_ID__c FROM Pricing_Plan__c WHERE Id = :pricePlan.Id];
            Assert.areEqual('existing_price_123', inserted.Stripe_Price_ID__c, 'Existing price ID should be preserved');
        }
    }

    /**
     * @description Tests that pricing plan without ProductName__c is skipped
     */
    @IsTest
    static void processPricingPlanAfterInsert_missingProductName_skipped(){
        User testUser = getTestUser();
        System.runAs(testUser){
            // Create pricing plan without ProductName__c
            Pricing_Plan__c pricePlan = new Pricing_Plan__c(
                Currency__c = 'usd',
                Recurrency_Type__c = 'month',
                Amount__c = 100
                // No ProductName__c
            );

            Test.startTest();
            insert pricePlan;
            Test.stopTest();

            // Should complete without error (plan without product name is skipped)
            Pricing_Plan__c inserted = [SELECT Stripe_Price_ID__c FROM Pricing_Plan__c WHERE Id = :pricePlan.Id];
            Assert.areEqual(null, inserted.Stripe_Price_ID__c, 'Price ID should remain null when ProductName is missing');
        }
    }

    /**
     * @description Tests createPricingTier with null parameters
     */
    @IsTest
    static void createPricingTier_nullParameters_noError(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Test.startTest();
            // Should not throw exception with null parameters
            PricingPlanTriggerHelper.createPricingTier(null);
            PricingPlanTriggerHelper.createPricingTier(new List<Pricing_Plan__c>());
            Test.stopTest();

            // Verify no pricing tiers were created
            List<Pricing_Tier__c> tiers = [SELECT Id FROM Pricing_Tier__c];
            Assert.areEqual(0, tiers.size(), 'No pricing tiers should be created for null/empty parameters');
        }
    }

    /**
     * @description Tests createPricingTier with pricing plan that has no matching metadata
     *              Should log warning but not throw exception
     */
    @IsTest
    static void createPricingTier_missingMetadata_continuesGracefully(){
        User testUser = getTestUser();
        System.runAs(testUser){
            // Create pricing plan with name that doesn't match any Stripe_Price__mdt record
            Pricing_Plan__c pricePlan = new Pricing_Plan__c(
                Stripe_Price_ID__c = 'price_no_metadata',
                Currency__c = 'usd',
                Recurrency_Type__c = 'month',
                Amount__c = 100,
                Name = 'NonExistent_Plan_Name_12345'
            );

            Test.startTest();
            insert pricePlan;
            Test.stopTest();

            // Should complete without throwing exception
            // Verify no pricing tier was created for this plan
            List<Pricing_Tier__c> tiers = [SELECT Id FROM Pricing_Tier__c WHERE Pricing_Plan__c = :pricePlan.Id];
            Assert.areEqual(0, tiers.size(), 'No pricing tier should be created when metadata is missing');
        }
    }

    /**
     * @description Tests createPricingTier with multiple pricing plans in bulk
     *              including some with and without matching metadata
     */
    @IsTest
    static void createPricingTier_bulkProcessing_partialSuccess(){
        User testUser = getTestUser();
        System.runAs(testUser){
            List<Pricing_Plan__c> pricingPlans = new List<Pricing_Plan__c>();

            // Plan with valid metadata match
            pricingPlans.add(new Pricing_Plan__c(
                Stripe_Price_ID__c = 'price_valid',
                Currency__c = 'usd',
                Recurrency_Type__c = 'month',
                Amount__c = 100,
                Name = 'Basic_Month'  // This should match metadata
            ));

            // Plan with non-matching metadata
            pricingPlans.add(new Pricing_Plan__c(
                Stripe_Price_ID__c = 'price_invalid',
                Currency__c = 'usd',
                Recurrency_Type__c = 'month',
                Amount__c = 200,
                Name = 'NonExistent_Plan'
            ));

            Test.startTest();
            insert pricingPlans;
            Test.stopTest();

            // Verify at least the valid plan created a tier
            List<Pricing_Tier__c> tiers = [SELECT Id, Pricing_Plan__c FROM Pricing_Tier__c];
            Assert.isTrue(tiers.size() >= 1, 'At least one pricing tier should be created for the valid plan');
        }
    }

    /**
     * @description Tests updateAmountOnRelatedSubscription where amount is unchanged
     *              Should skip processing
     */
    @IsTest
    static void updateAmountOnRelatedSubscription_unchangedAmount_skipped(){
        User testUser = getTestUser();
        System.runAs(testUser){
            Stripe_Subscription__c subscription = new Stripe_Subscription__c(
                Product_Plan_Name__c = 'Test',
                Amount__c = 100
            );
            insert subscription;

            Pricing_Plan__c pricePlan = new Pricing_Plan__c(
                Stripe_Subscription__c = subscription.Id,
                Stripe_Price_ID__c = 'price_123',
                Currency__c = 'usd',
                Recurrency_Type__c = 'month',
                Amount__c = 100
            );
            insert pricePlan;

            // Update something other than amount
            pricePlan.Currency__c = 'eur';

            Test.startTest();
            update pricePlan;
            Test.stopTest();

            // Subscription amount should remain unchanged
            Stripe_Subscription__c updatedSubscription = [SELECT Amount__c FROM Stripe_Subscription__c WHERE Id = :subscription.Id];
            Assert.areEqual(100, updatedSubscription.Amount__c, 'Subscription amount should not change when plan amount is unchanged');
        }
    }
}