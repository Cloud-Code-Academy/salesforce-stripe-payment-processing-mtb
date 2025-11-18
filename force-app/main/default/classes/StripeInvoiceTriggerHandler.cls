public with sharing class StripeInvoiceTriggerHandler {
    /**
     * @description Handles after insert trigger logic for Stripe Invoice records.
     * 
     * @param newList List of newly inserted Stripe Invoice records
     */
    public static void afterInsert(List<Stripe_Invoice__c> newList){
        //Triggers revenue calculation for customers with newly created paid invoices.
        StripeInvoiceTriggerHelper.calculateTotalRevenueOfStripeCustomer(newList, null);
         // Finance notifications for failed payments
        StripeInvoiceTriggerHelper.sendFailureNotifications(newList, null);

        // Customer health scoring
        StripeInvoiceTriggerHelper.calculateCustomerHealthScore(newList, null);

        // Churn risk detection
        StripeInvoiceTriggerHelper.detectChurnRisk(newList, null);
    }
    /**
     * @description Handles after update trigger logic for Stripe Invoice records.
     *              Triggers revenue recalculation when invoice status changes to paid or amount is updated.
     * 
     * @param newList List of updated Stripe Invoice records with new values
     * @param oldMap Map of Stripe Invoice records before update, keyed by record Id
     */
    public static void afterUpdate(List<Stripe_Invoice__c> newList, Map<Id, Stripe_Invoice__c> oldMap){
        //Triggers revenue calculation for customers with newly created paid invoices.
        StripeInvoiceTriggerHelper.calculateTotalRevenueOfStripeCustomer(newList, oldMap);
        // Finance notifications (when status or dunning status changes)
        StripeInvoiceTriggerHelper.sendFailureNotifications(newList, oldMap);

        // Customer health scoring (when payment patterns change)
        StripeInvoiceTriggerHelper.calculateCustomerHealthScore(newList, oldMap);

        // Churn risk detection (when dunning status changes)
        StripeInvoiceTriggerHelper.detectChurnRisk(newList, oldMap);

        // Dunning escalation (when status changes)
        StripeInvoiceTriggerHelper.escalateDunningStatus(newList, oldMap);
    }
}