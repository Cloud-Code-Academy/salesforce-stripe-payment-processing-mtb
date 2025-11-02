public with sharing class StripeCustomerTriggerHelper {
    /**
     * Populates the Stripe_Customer_ID__c field with the Stripe_Customer_ID__c on the related Contact record
     *
     * @param newList List of Stripe_Customer__c records to process
     * @param oldMap Map of old Stripe_Customer__c records (null for INSERT operations)
     * @throws SecurityException if user lacks update permissions on object or field
     */
    public static void populateStripeCustomerIdOnRelatedContact(List<Stripe_Customer__c> newList, Map<Id, Stripe_Customer__c> oldMap){
        // Validate input parameters
        if (newList == null || newList.isEmpty()) {
            return;
        }

        Map<Id, Contact> contactsForUpdate = new Map<Id, Contact>();
        //Check whether Stripe_Customer__c object is available for update
        if (Schema.SObjectType.Contact.isUpdateable()) {
            for (Stripe_Customer__c customer : newList) {
                Boolean shouldUpdateContact = false;

                // Determine if Contact should be updated
                if (customer.Contact__c != null && customer.Stripe_Customer_ID__c != null) {
                    if (oldMap == null) {
                        // INSERT context: Update Contact if Stripe_Customer_ID__c is set
                        shouldUpdateContact = true;
                    } else {
                        // UPDATE context: Update Contact only if Stripe_Customer_ID__c changed
                        Stripe_Customer__c oldCustomer = oldMap.get(customer.Id);
                        if (oldCustomer != null && oldCustomer.Stripe_Customer_ID__c != customer.Stripe_Customer_ID__c) {
                            shouldUpdateContact = true;
                        }
                    }
                }

                if (shouldUpdateContact) {

                    //Check whether Stripe_Customer_ID__c field of Contact object is available for update
                    if (Schema.SObjectType.Contact.fields.Stripe_Customer_ID__c.isUpdateable()) {
                         contactsForUpdate.put(customer.Contact__c, 
                                            new Contact(Id = customer.Contact__c, 
                                            Stripe_Customer_ID__c = customer.Stripe_Customer_ID__c));
                    } else {
                        throw new SecurityException('User does not have edit access to Stripe_Customer_ID__c field of Contact object');
                    }
                }
            }
            try{
                if (!contactsForUpdate.isEmpty()) {
                    update as user contactsForUpdate.values();
                }
            } catch(Exception e){
                Logger.error('Failed to update Stripe Customer: ', e);
                Logger.saveLog();
            }
        } else {
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
        // Validate input parameters
        if (newList == null || newList.isEmpty()) {
            return;
        }

        List<Stripe_Customer__c> stripeCustomersForProcess = new List<Stripe_Customer__c>();
        if (Schema.SObjectType.Stripe_Customer__c.isAccessible()) {
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
                    Logger.error('Failed to make callout: ', ex);
                    Logger.saveLog();
                }
            }
        } else {
            throw new SecurityException('User does not have edit access to Stripe_Customer__c object');
        }
    }
}