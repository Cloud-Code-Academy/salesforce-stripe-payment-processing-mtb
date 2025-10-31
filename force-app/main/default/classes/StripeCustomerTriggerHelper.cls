public with sharing class StripeCustomerTriggerHelper {
    /**
     * Populates the Stripe_Customer_ID__c field with the Stripe_Customer_ID__c on the related Contact record
     * 
     * @param newList List of Stripe_Customer__c records to process
     * @throws SecurityException if user lacks update permissions on object or field
     */
    public static void populateStripeCustomerIdOnRelatedContact(List<Stripe_Customer__c> newList, Map<Id, Stripe_Customer__c> oldMap){
        List<Contact> contactsForUpdate = new List<Contact>();
        //Check whether Stripe_Customer__c object is available for update
        try {
            if (!Schema.SObjectType.Contact.fields.Stripe_Customer_ID__c.isUpdateable()) {
                throw new SecurityException('User does not have edit access to Stripe_Customer_ID__c field of Contact object');
            }
            for (Stripe_Customer__c customer : newList) {
                Stripe_Customer__c oldCustomer = oldMap.get(customer.Id);
                if (oldCustomer != null && customer.Contact__c != null
                    && customer.Stripe_Customer_ID__c != null
                    && oldCustomer.Stripe_Customer_ID__c != customer.Stripe_Customer_ID__c) {
                    Contact cont = new Contact();
                    cont.Id = customer.Contact__c;
                    cont.Stripe_Customer_ID__c = customer.Stripe_Customer_ID__c;
                    contactsForUpdate.add(cont);
                }
            }
            if (!contactsForUpdate.isEmpty()) {
                update as user contactsForUpdate;
            }
        } catch(Exception e) {
            Logger.error('Failed to update Stripe Customer: ', e);
            Logger.saveLog();
            throw new SecurityException('User does not have edit access to Contact object');
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
        try {
            //Filter out records that already have Customer ID
            for (Stripe_Customer__c customer : newList) {
                if (String.isBlank(customer.Stripe_Customer_ID__c)) {
                    stripeCustomersForProcess.add(customer);
                }
            }
            // Loop through each Customer
            for (Stripe_Customer__c filteredCustomer : stripeCustomersForProcess) {
                // Enqueue the callout
                StripeCalloutQueueable callout = new StripeCalloutQueueable(
                    filteredCustomer.Id,
                    filteredCustomer.Customer_Name__c,
                    filteredCustomer.Customer_Email__c,
                    filteredCustomer.Customer_Phone__c
                );
                if (!Test.isRunningTest()) {
                    System.enqueueJob(callout);
                }
            }
        } catch (Exception e) {
            Logger.error('Failed to process customer after insert: ', e);
            Logger.saveLog();
            throw new SecurityException('User does not have edit access to Stripe_Customer__c object');
        }
    }
}