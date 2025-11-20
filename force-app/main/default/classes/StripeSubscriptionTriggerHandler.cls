public with sharing class StripeSubscriptionTriggerHandler {
    public static void afterInsert(List<Stripe_Subscription__c> newList) {
        StripeSubscriptionTriggerHelper.processStripeSubscriptionAfterUpdate(newList, null);
        StripeSubscriptionTriggerHelper.calculateMRR_OfStripeCustomer(newList, null);
    }

    public static void afterUpdate(List<Stripe_Subscription__c> newList, Map<Id, Stripe_Subscription__c> oldMap) {
        StripeSubscriptionTriggerHelper.processStripeSubscriptionAfterUpdate(newList, oldMap);
        // Removed: processStripeSubscriptionToCreateSession - no longer needed as checkout session is created directly
        // The checkout session will create the subscription in Stripe, avoiding duplicate subscriptions
        // Removed: createPricingPlansUponSelection - Pricing Plans are now created via middleware
        StripeSubscriptionTriggerHelper.calculateMRR_OfStripeCustomer(newList, oldMap);
    }
}