/**
 * @description Handler class for PaymentTransactionTrigger
 * Routes trigger events to appropriate helper methods for processing
 *
 * @author Cloud Code
 * @date 2025
 */
public with sharing class PaymentTransactionTriggerHandler {

    /**
     * @description Handles after insert trigger logic for Payment Transaction records
     *
     * @param newList List of newly inserted Payment Transaction records
     */
    public static void afterInsert(List<Payment_Transaction__c> newList) {
        // Update invoice status when payment succeeds
        PaymentTransactionTriggerHelper.updateInvoiceStatusOnPaymentSuccess(newList, null);
    }

    /**
     * @description Handles after update trigger logic for Payment Transaction records
     *
     * @param newList List of updated Payment Transaction records with new values
     * @param oldMap Map of Payment Transaction records before update, keyed by record Id
     */
    public static void afterUpdate(List<Payment_Transaction__c> newList, Map<Id, Payment_Transaction__c> oldMap) {
        // Update invoice status when payment status changes to succeeded
        PaymentTransactionTriggerHelper.updateInvoiceStatusOnPaymentSuccess(newList, oldMap);
    }
}