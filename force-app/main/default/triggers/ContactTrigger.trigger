trigger ContactTrigger on Contact (after insert) {
    ManageTrigger__mdt triggerSetting = ManageTrigger__mdt.getInstance('ContactTrigger');
    if (triggerSetting.IsActive__c && triggerSetting.RunForAll__c) {
        switch on Trigger.operationType {
            when AFTER_INSERT {
                ContactTriggerHandler.afterInsert(Trigger.new);
            }
        }
    }
}