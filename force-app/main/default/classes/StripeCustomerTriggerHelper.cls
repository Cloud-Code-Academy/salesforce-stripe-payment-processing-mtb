public with sharing class StripeCustomerTriggerHelper {

    public static void populateNameFromContact(List<Stripe_Customer__c> newList){
        Map<Id, Id> customerIdsToContactIds = new Map<Id, Id>();
        Map<Id, String> contactIdsToNames = new Map<Id, String>();
        for (Stripe_Customer__c customer : newList) {
            if (customer.Contact__c != null) {
                customerIdsToContactIds.put(customer.Id, customer.Contact__c);
            }
        }
        if (!customerIdsToContactIds.isEmpty()) {
            for (Contact cont : [SELECT Name FROM Contact
                                    WHERE Id IN: customerIdsToContactIds.values()]) {
                contactIdsToNames.put(cont.Id, cont.Name);
            }
        }
        if (!customerIdsToContactIds.isEmpty()) {
            for (Stripe_Customer__c customer : newList) {
                customer.Customer_Name__c = contactIdsToNames.get(customerIdsToContactIds.get(customer.Id));
            }
        }
    }
    public static void processCustomerAfterInsert(List<Stripe_Customer__c> newList){
        List<Stripe_Customer__c> stripeCustomersForProcess = new List<Stripe_Customer__c>();

        //Filter out records that already have Customer ID
        for (Stripe_Customer__c customer : newList) {
            if (String.isBlank(customer.Stripe_Customer_ID__c)) {
                stripeCustomersForProcess.add(customer);
            }
        }
        // Loop through each Customer
        for (Stripe_Customer__c filteredCustomer : stripeCustomersForProcess) {
            // Enqueue the callout
            try {
                StripeCalloutQueueable callout = new StripeCalloutQueueable(
                    filteredCustomer.Id,
                    filteredCustomer.Customer_Name__c,
                    filteredCustomer.Customer_Email__c,
                    filteredCustomer.Customer_Phone__c
                );
                if (!Test.isRunningTest()) {
                    System.enqueueJob(callout);
                }
            } catch (Exception ex) {
                System.debug('Error occured: ' + ex.getMessage());
            }
            
        }
    }
}