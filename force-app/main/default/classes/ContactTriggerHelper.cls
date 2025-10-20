public with sharing class ContactTriggerHelper {
    public static void processContactAfterInsert(List<Contact> newList){
        List<Stripe_Customer__c> stripeCustomersForInsert = new List<Stripe_Customer__c>();
        for (Contact cont : newList) {
            Stripe_Customer__c customer = new Stripe_Customer__c();
            if (Schema.SObjectType.Stripe_Customer__c.fields.Contact__c.isCreateable()) {
                customer.Contact__c = cont.Id;
            } else {
                throw new SecurityException('User does not have Create access to Contact__c field of Stripe_Customer__c object');
            }
            if (Schema.SObjectType.Stripe_Customer__c.fields.Customer_Email__c.isCreateable()
                && cont.Email != null) {
                customer.Customer_Email__c = cont.Email;
            } else {
                throw new SecurityException('User does not have Create access to Customer_Email__c field of Stripe_Customer__c object');
            }
            if (Schema.SObjectType.Stripe_Customer__c.fields.Customer_Name__c.isCreateable()) {
                customer.Customer_Name__c = cont.Name;
            } else {
                throw new SecurityException('User does not have Create access to Customer_Name__c field of Stripe_Customer__c object');
            }
            if (Schema.SObjectType.Stripe_Customer__c.fields.Customer_Phone__c.isCreateable()
                && cont.Phone != null) {
                customer.Customer_Phone__c = cont.Phone;
            } else {
                throw new SecurityException('User does not have Create access to Customer_Phone__c field of Stripe_Customer__c object');
            }
            stripeCustomersForInsert.add(customer);
        }
        if (Schema.SObjectType.Stripe_Customer__c.isCreateable()) {
            insert stripeCustomersForInsert;
        } else {
            throw new SecurityException('User does not have create access to Stripe_Customer__c object');
        }
        
    }
}