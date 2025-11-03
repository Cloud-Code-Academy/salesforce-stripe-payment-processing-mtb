trigger StripeInvoiceTrigger on Stripe_Invoice__c (after insert, after update) {
    ManageTrigger__mdt triggerSetting = ManageTrigger__mdt.getInstance('StripeInvoiceTrigger');
    if (triggerSetting.IsActive__c && triggerSetting.RunForAll__c) {
        switch on Trigger.operationType {
            when AFTER_INSERT {
                StripeInvoiceTriggerHandler.afterInsert(Trigger.new);
            }
            when AFTER_UPDATE {
                StripeInvoiceTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
            }
        }
    }
}
