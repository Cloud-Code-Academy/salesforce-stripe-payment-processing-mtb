trigger PricingPlanTrigger on Pricing_Plan__c (after insert, after update) {
    ManageTrigger__mdt triggerSetting = ManageTrigger__mdt.getInstance('PricingPlanTrigger');
    if (triggerSetting.IsActive__c && triggerSetting.RunForAll__c) {
        switch on Trigger.operationType {
            when AFTER_INSERT {
                PricingPlanTriggerHandler.afterInsert(Trigger.new);
            }
            when AFTER_UPDATE{
                PricingPlanTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
            }
        }
    }
}