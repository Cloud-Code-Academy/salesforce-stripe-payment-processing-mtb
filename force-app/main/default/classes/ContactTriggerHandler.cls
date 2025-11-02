public with sharing class ContactTriggerHandler {
    public static void afterInsert(List<Contact> newList){
        ContactTriggerHelper.processContactAfterInsert(newList);
    }

    public static void afterUpdate(List<Contact> newList, Map<Id, Contact> oldMap){
        ContactTriggerHelper.processContactAfterUpdate(newList, oldMap);
    }
}