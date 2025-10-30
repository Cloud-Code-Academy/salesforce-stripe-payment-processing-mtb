trigger StripeCustomerTrigger on Stripe_Customer__c (after insert, after update) {
    ManageTrigger__mdt triggerSetting = ManageTrigger__mdt.getInstance('StripeCustomerTrigger');
    if (triggerSetting.IsActive__c && triggerSetting.RunForAll__c) {
        switch on Trigger.operationType {
            when AFTER_INSERT {
                StripeCustomerTriggerHandler.afterInsert(Trigger.new);
            }
            when AFTER_UPDATE {
                StripeCustomerTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
            }
        }
    }
}