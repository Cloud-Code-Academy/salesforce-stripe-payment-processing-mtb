public with sharing class StripeInvoiceTriggerHandler {

    /**
     * Handles after insert events for Stripe_Invoice__c
     *
     * @param newList List of newly inserted invoice records
     */
    public static void afterInsert(List<Stripe_Invoice__c> newList) {
        // Revenue rollups
        StripeInvoiceTriggerHelper.rollupRevenueToCustomer(newList, null);
        StripeInvoiceTriggerHelper.rollupRevenueToSubscription(newList, null);

        // Finance notifications for failed payments
        StripeInvoiceTriggerHelper.sendFailureNotifications(newList, null);

        // Customer health scoring
        StripeInvoiceTriggerHelper.calculateCustomerHealthScore(newList, null);

        // Churn risk detection
        StripeInvoiceTriggerHelper.detectChurnRisk(newList, null);
    }

    /**
     * Handles after update events for Stripe_Invoice__c
     *
     * @param newList List of updated invoice records
     * @param oldMap Map of old invoice records before update
     */
    public static void afterUpdate(List<Stripe_Invoice__c> newList, Map<Id, Stripe_Invoice__c> oldMap) {
        // Revenue rollups (when status or amount changes)
        StripeInvoiceTriggerHelper.rollupRevenueToCustomer(newList, oldMap);
        StripeInvoiceTriggerHelper.rollupRevenueToSubscription(newList, oldMap);

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
