public with sharing class StripeCustomerTriggerHelper {
    /**
     * Populates the Customer_Name__c field with the name from the related Contact record
     * 
     * This method queries Contact records associated with Stripe Customer records
     * and updates the Customer_Name__c field with the Contact's name.
     * Enforces object and field-level security before performing updates.
     * 
     * @param newList List of Stripe_Customer__c records to process
     * @throws SecurityException if user lacks update permissions on object or field
     */
    public static void populateNameFromContact(List<Stripe_Customer__c> newList){
        Map<Id, Id> customerIdsToContactIds = new Map<Id, Id>();
        Map<Id, String> contactIdsToNames = new Map<Id, String>();
        //Check whether Stripe_Customer__c object is available for update
        if (Schema.SObjectType.Stripe_Customer__c.isUpdateable()) {
            for (Stripe_Customer__c customer : newList) {
                if (customer.Contact__c != null) {
                    customerIdsToContactIds.put(customer.Id, customer.Contact__c);
                }
            }
            if (!customerIdsToContactIds.isEmpty()) {
                for (Contact cont : [SELECT Name FROM Contact
                                        WHERE Id IN: customerIdsToContactIds.values() WITH USER_MODE]) {
                    contactIdsToNames.put(cont.Id, cont.Name);
                }
            }
            if (!customerIdsToContactIds.isEmpty()) {
                //Check whether Customer_Name__c field of Stripe_Customer__c object is available for update
                if (Schema.SObjectType.Stripe_Customer__c.fields.Customer_Name__c.isUpdateable()) {
                    for (Stripe_Customer__c customer : newList) {
                        //Update Customer_Name__c with Name of related Contact record
                        customer.Customer_Name__c = contactIdsToNames.get(customerIdsToContactIds.get(customer.Id));
                    }
                } else {
                    throw new SecurityException('Customer_Name__c field of Stripe_Customer__c is not available for update');
                }
            }
        } else {
            throw new SecurityException('Stripe_Customer__c object is not available for update');
        }
    }
    /**
     * Processes newly inserted Stripe Customer records and creates customers in Stripe via API
     * 
     * Filters records that don't have a Stripe Customer ID and enqueues asynchronous
     * callouts to create corresponding customer records in Stripe. Each customer creation
     * is processed independently via a queueable job.
     * 
     * @param newList List of newly inserted Stripe_Customer__c records from trigger context
     */
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