/**
 * @description Trigger for Payment_Transaction__c object
 * Handles invoice status updates when payment transactions succeed
 *
 * @author Cloud Code
 * @date 2025
 */
trigger PaymentTransactionTrigger on Payment_Transaction__c (
    after insert,
    after update
) {
    if (Trigger.isAfter && Trigger.isInsert) {
        PaymentTransactionTriggerHandler.afterInsert(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        PaymentTransactionTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}