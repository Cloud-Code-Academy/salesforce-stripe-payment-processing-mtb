trigger WebhookEventTrigger on WebhookEvent__e (after insert) {
    ManageTrigger__mdt triggerSetting = ManageTrigger__mdt.getInstance('WebhookEventTrigger');
    if (triggerSetting.IsActive__c
        && triggerSetting.RunForAll__c) {
        switch on Trigger.operationType {
            when  AFTER_INSERT{
                WebhookEventTriggerHandler.afterInsert(Trigger.new);
            }
        }
    }
}