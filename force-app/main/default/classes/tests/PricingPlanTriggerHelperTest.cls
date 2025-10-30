@isTest
public class PricingPlanTriggerHelperTest {
    private static User testUser;

    @TestSetup
    static void setupTestData() {
        // Create test user with Stripe API Access permission set
        testUser = TestDataFactory.createUserWithPermissionSets(
            new List<String>{'Stripe_API_Access', 'CustomMetadataAccess','Stripe_Integration_User','PricingPlanAndPricingTier'}
        );
        ManageTrigger__mdt triggerSetting = new ManageTrigger__mdt(
        DeveloperName = 'PricingPlanTrigger',
        IsActive__c = true,
        RunForAll__c = true
    );
    }
    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'testuser%@testorg.com' LIMIT 1];
    }
    @IsTest
    static void updateStripePriceIdOnRelatedSubscription_insertAndUpdatePriceId_success(){
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
        pricePlan.Stripe_Price_ID__c = 'updatedID';
        Test.startTest();
        update pricePlan;
        Test.stopTest();
        List<Stripe_Subscription__c> updatedSubscription = [SELECT Stripe_Price_ID__c FROM Stripe_Subscription__c WHERE Id =: subscription.Id];
        // Verify the result
        System.assertEquals('updatedID', updatedSubscription[0].Stripe_Price_ID__c, 'Stripe_Price_ID__c is updated on related Stripe_Subscription__c');
        
    }
    @IsTest
    static void updateAmountOnRelatedSubscription_insertAndUpdateAmount_success(){
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
    @IsTest 
    static void processPricingPlanAfterInsert_insertAndSendToStripe_success(){
        // Set mock to handle multiple callouts
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeCalloutMock());
            Stripe_Subscription__c subscription = new Stripe_Subscription__c(
                Product_Plan_Name__c = 'Orange'
            );
            insert subscription;
            
            Pricing_Plan__c pricePlan = new Pricing_Plan__c(
                Stripe_Subscription__c = subscription.Id,
                Currency__c = 'usd',
                Recurrency_Type__c = 'week',
                Amount__c = 24
            );
            
            Test.startTest();
            insert pricePlan;
            Test.stopTest();
            
        }
        
    }
    @IsTest
    static void createPricingTier_insertPricingPlanWithProperName_success(){
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