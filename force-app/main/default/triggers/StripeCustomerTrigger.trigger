trigger StripeCustomerTrigger on Stripe_Customer__c (before insert, after insert) {
    ManageTrigger__mdt triggerSetting = ManageTrigger__mdt.getInstance('StripeCustomerTrigger');
    if (triggerSetting.IsActive__c && triggerSetting.RunForAll__c) {
        switch on Trigger.operationType {
            when BEFORE_INSERT{
                StripeCustomerTriggerHandler.beforeInsert(Trigger.new);
            }
            when AFTER_INSERT {
                StripeCustomerTriggerHandler.afterInsert(Trigger.new);
            }
        }
    }
}