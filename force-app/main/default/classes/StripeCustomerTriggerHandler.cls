public with sharing class StripeCustomerTriggerHandler {

    public static void afterInsert(List<Stripe_Customer__c> newList){
        // Process customers without Stripe_Customer_ID__c (enqueue API callouts)
        StripeCustomerTriggerHelper.processCustomerAfterInsert(newList);
        // Update related Contacts for customers that already have Stripe_Customer_ID__c
        StripeCustomerTriggerHelper.populateStripeCustomerIdOnRelatedContact(newList, null);
    }
    public static void afterUpdate(List<Stripe_Customer__c> newList, Map<Id, Stripe_Customer__c> oldMap){
        StripeCustomerTriggerHelper.populateStripeCustomerIdOnRelatedContact(newList, oldMap);
    }
}