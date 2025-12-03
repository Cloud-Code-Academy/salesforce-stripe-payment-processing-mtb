trigger StripeInvoiceTrigger on Stripe_Invoice__c (after insert, after update) {
    ManageTrigger__mdt triggerSetting = ManageTrigger__mdt.getInstance('StripeInvoiceTrigger');
    // Always run trigger in test context or when metadata settings allow
    if (Test.isRunningTest() || (triggerSetting != null && triggerSetting.IsActive__c && triggerSetting.RunForAll__c)) {
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