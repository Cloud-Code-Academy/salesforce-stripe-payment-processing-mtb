trigger StripeSubscriptionTrigger on Stripe_Subscription__c (after update) {
    ManageTrigger__mdt triggerSetting = ManageTrigger__mdt.getInstance('StripeSubscriptionTrigger');
    if (triggerSetting.IsActive__c && triggerSetting.RunForAll__c) {
        switch on Trigger.operationType {
            when  AFTER_UPDATE{
                StripeSubscriptionTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
            }
        }
    }
}