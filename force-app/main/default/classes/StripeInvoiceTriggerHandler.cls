public with sharing class StripeInvoiceTriggerHandler {
    /**
     * @description Handles after insert trigger logic for Stripe Invoice records.
     *              Triggers revenue calculation for customers with newly created paid invoices.
     * 
     * @param newList List of newly inserted Stripe Invoice records
     */
    public static void afterInsert(List<Stripe_Invoice__c> newList){
        StripeInvoiceTriggerHelper.calculateTotalRevenueOfStripeCustomer(newList, null);
    }
    /**
     * @description Handles after update trigger logic for Stripe Invoice records.
     *              Triggers revenue recalculation when invoice status changes to paid or amount is updated.
     * 
     * @param newList List of updated Stripe Invoice records with new values
     * @param oldMap Map of Stripe Invoice records before update, keyed by record Id
     */
    public static void afterUpdate(List<Stripe_Invoice__c> newList, Map<Id, Stripe_Invoice__c> oldMap){
        StripeInvoiceTriggerHelper.calculateTotalRevenueOfStripeCustomer(newList, oldMap);
    }
    /**
     * @description Handles after delete trigger logic for Stripe Invoice records.
     *              Triggers revenue recalculation for customers whose paid invoices were deleted.
     * 
     * @param oldList List of deleted Stripe Invoice records
     */
    public static void afterDelete(List<Stripe_Invoice__c> oldList){
        StripeInvoiceTriggerHelper.calculateTotalRevenueOfStripeCustomer(oldList, null);
    }
}