public with sharing class PricingPlanTriggerHandler {
    public static void afterInsert(List<Pricing_Plan__c> newList){
        PricingPlanTriggerHelper.processPricingPlanAfterInsert(newList);
        PricingPlanTriggerHelper.createPricingTier(newList);
        PricingPlanTriggerHelper.updateAmountOnRelatedSubscription(newList, null);
    }
    public static void afterUpdate(List<Pricing_Plan__c> newList, Map<Id, Pricing_Plan__c> oldMap){
        PricingPlanTriggerHelper.updateStripePriceIdOnRelatedSubscription(newList, oldMap);
        PricingPlanTriggerHelper.updateAmountOnRelatedSubscription(newList, oldMap);
    }
}