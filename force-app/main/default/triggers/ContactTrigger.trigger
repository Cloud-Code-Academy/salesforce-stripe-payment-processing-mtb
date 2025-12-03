trigger ContactTrigger on Contact (after insert, after update) {
    ManageTrigger__mdt triggerSetting = ManageTrigger__mdt.getInstance('ContactTrigger');
    if (triggerSetting.IsActive__c && triggerSetting.RunForAll__c) {
        switch on Trigger.operationType {
            when AFTER_INSERT {
                ContactTriggerHandler.afterInsert(Trigger.new);
            }
            when AFTER_UPDATE {
                ContactTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
            }
        }
    }
}