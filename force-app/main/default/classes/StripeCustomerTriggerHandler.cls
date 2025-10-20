public with sharing class StripeCustomerTriggerHandler {

    public static void afterInsert(List<Stripe_Customer__c> newList){
        StripeCustomerTriggerHelper.processCustomerAfterInsert(newList);
    }
    public static void afterUpdate(List<Stripe_Customer__c> newList, Map<Id, Stripe_Customer__c> oldMap){
        StripeCustomerTriggerHelper.populateStripeCustomerIdOnRelatedContact(newList, oldMap);
    }
}