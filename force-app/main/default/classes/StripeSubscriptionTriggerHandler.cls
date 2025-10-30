public with sharing class StripeSubscriptionTriggerHandler {
    public static void afterUpdate(List<Stripe_Subscription__c> newList, Map<Id, Stripe_Subscription__c> oldMap) {
        StripeSubscriptionTriggerHelper.processStripeSubscriptionAfterUpdate(newList, oldMap);
        StripeSubscriptionTriggerHelper.processStripeSubscriptionToCreateSession(newList, oldMap);
        StripeSubscriptionTriggerHelper.createPricingPlansUponSelection(newList, oldMap);
    }
}