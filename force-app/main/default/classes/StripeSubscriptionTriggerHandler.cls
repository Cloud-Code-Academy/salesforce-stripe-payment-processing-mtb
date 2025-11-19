public with sharing class StripeSubscriptionTriggerHandler {
    public static void afterInsert(List<Stripe_Subscription__c> newList) {
        StripeSubscriptionTriggerHelper.processStripeSubscriptionAfterUpdate(newList, null);
    }

    public static void afterUpdate(List<Stripe_Subscription__c> newList, Map<Id, Stripe_Subscription__c> oldMap) {
        StripeSubscriptionTriggerHelper.processStripeSubscriptionAfterUpdate(newList, oldMap);
    }
}