/**
 * @description Helper class for PaymentTransactionTrigger
 * Contains business logic for updating invoice status when payments succeed
 *
 * @author Cloud Code
 * @date 2025
 */
public with sharing class PaymentTransactionTriggerHelper {

    // Constants for payment and invoice statuses
    private static final String PAYMENT_STATUS_SUCCEEDED = 'succeeded';
    private static final String INVOICE_STATUS_PAID = 'paid';

    /**
     * @description Updates parent invoice status to 'paid' when payment transaction succeeds
     * @param newTransactions List of new Payment Transaction records
     * @param oldTransactionsMap Map of old Payment Transaction records (null for insert)
     */
    public static void updateInvoiceStatusOnPaymentSuccess(
        List<Payment_Transaction__c> newTransactions,
        Map<Id, Payment_Transaction__c> oldTransactionsMap
    ) {
        try {
            // Get successful payment transactions
            List<Payment_Transaction__c> successfulTransactions = getSuccessfulTransactions(
                newTransactions,
                oldTransactionsMap
            );

            if (successfulTransactions.isEmpty()) {
                return;
            }

            // Collect invoice IDs from successful transactions
            Set<Id> invoiceIds = new Set<Id>();
            for (Payment_Transaction__c paymentTrans : successfulTransactions) {
                if (paymentTrans.Stripe_Invoice__c != null) {
                    invoiceIds.add(paymentTrans.Stripe_Invoice__c);
                }
            }

            if (invoiceIds.isEmpty()) {
                return;
            }

            // Update invoices to paid status
            updateInvoices(invoiceIds);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error updating invoice status on payment success: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            throw e;
        }
    }

    /**
     * @description Filters transactions to get only those that have succeeded status
     * @param newTransactions List of new Payment Transaction records
     * @param oldTransactionsMap Map of old Payment Transaction records (null for insert)
     * @return List of Payment Transactions that have succeeded status
     */
    @TestVisible
    private static List<Payment_Transaction__c> getSuccessfulTransactions(
        List<Payment_Transaction__c> newTransactions,
        Map<Id, Payment_Transaction__c> oldTransactionsMap
    ) {
        List<Payment_Transaction__c> successfulTransactions = new List<Payment_Transaction__c>();

        for (Payment_Transaction__c paymentTrans : newTransactions) {
            // For insert: check if status is succeeded
            // For update: check if status changed to succeeded
            Boolean isSucceeded = false;

            if (oldTransactionsMap == null) {
                // Insert scenario
                isSucceeded = paymentTrans.Status__c == PAYMENT_STATUS_SUCCEEDED;
            } else {
                // Update scenario - check if status changed to succeeded
                Payment_Transaction__c oldTransaction = oldTransactionsMap.get(paymentTrans.Id);
                isSucceeded = paymentTrans.Status__c == PAYMENT_STATUS_SUCCEEDED &&
                              oldTransaction.Status__c != PAYMENT_STATUS_SUCCEEDED;
            }

            if (isSucceeded) {
                successfulTransactions.add(paymentTrans);
            }
        }

        return successfulTransactions;
    }

    /**
     * @description Updates invoice records to 'paid' status
     * @param invoiceIds Set of invoice IDs to update
     */
    @TestVisible
    private static void updateInvoices(Set<Id> invoiceIds) {
        // Query invoices that need to be updated
        List<Stripe_Invoice__c> invoicesToUpdate = [
            SELECT Id, Status__c
            FROM Stripe_Invoice__c
            WHERE Id IN :invoiceIds
            AND Status__c != :INVOICE_STATUS_PAID
        ];

        if (invoicesToUpdate.isEmpty()) {
            return;
        }

        // Update status to paid
        for (Stripe_Invoice__c invoice : invoicesToUpdate) {
            invoice.Status__c = INVOICE_STATUS_PAID;
        }

        // Perform DML update
        update invoicesToUpdate;

        System.debug('Updated ' + invoicesToUpdate.size() + ' invoice(s) to paid status');
    }
}