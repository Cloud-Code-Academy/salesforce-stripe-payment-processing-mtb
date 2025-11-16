public with sharing class StripeSubscriptionTriggerHandler {
    public static void afterInsert(List<Stripe_Subscription__c> newList) {
        StripeSubscriptionTriggerHelper.processStripeSubscriptionAfterUpdate(newList, null);
        StripeSubscriptionTriggerHelper.createPricingPlansUponSelection(newList, null);
    }

    public static void afterUpdate(List<Stripe_Subscription__c> newList, Map<Id, Stripe_Subscription__c> oldMap) {
        StripeSubscriptionTriggerHelper.processStripeSubscriptionAfterUpdate(newList, oldMap);
        // Removed: processStripeSubscriptionToCreateSession - no longer needed as checkout session is created directly
        // The checkout session will create the subscription in Stripe, avoiding duplicate subscriptions
        StripeSubscriptionTriggerHelper.createPricingPlansUponSelection(newList, oldMap);
    }
}