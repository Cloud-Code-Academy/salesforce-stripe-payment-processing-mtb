public with sharing class StripeCustomerTriggerHandler {

    public static void beforeInsert(List<Stripe_Customer__c> newList){
        StripeCustomerTriggerHelper.populateNameFromContact(newList);
    }
    public static void afterInsert(List<Stripe_Customer__c> newList){
        StripeCustomerTriggerHelper.processCustomerAfterInsert(newList);
    }
}