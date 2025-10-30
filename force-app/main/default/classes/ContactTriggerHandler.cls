public with sharing class ContactTriggerHandler {
    public static void afterInsert(List<Contact> newList){
        ContactTriggerHelper.processContactAfterInsert(newList);
    }
}