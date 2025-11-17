public with sharing class ContactTriggerHelper {
    /**
     * @description Helper class for Contact trigger operations. 
     * @param newList List of newly inserted Contact records
     */
    public static void processContactAfterInsert(List<Contact> newList){
        try {
            // Validate input parameters
            if (newList == null || newList.isEmpty()) {
                Logger.warn('processContactAfterInsert called with null or empty newList')
                    .addTag('ContactTriggerHelper');
                Logger.saveLog();
                return;
            }

            List<Contact> stripeCustomersForProcess = new List<Contact>();
            //Filter out records that already have Customer ID
            for (Contact customer : newList) {
                if (String.isBlank(customer.Stripe_Customer_ID__c)) {
                    stripeCustomersForProcess.add(customer);
                }
            }
            // Loop through each Customer
            for (Contact filteredCustomer : stripeCustomersForProcess) {
                // Enqueue the callout
                try {
                    StripeCalloutQueueable callout = new StripeCalloutQueueable(
                        filteredCustomer.Id,
                        filteredCustomer.FirstName + ' ' + filteredCustomer.LastName,
                        filteredCustomer.Email,
                        filteredCustomer.Phone
                    );
                    if (!Test.isRunningTest()) {
                        System.enqueueJob(callout);
                    }
                } catch (Exception ex) {
                    Logger.error('Failed to make callout: ', ex);
                    Logger.saveLog();
                }
            }

            // Note: Stripe customer data is now stored directly on Contact
            // and populated by middleware webhooks/API sync
            Logger.info('Processed ' + newList.size() + ' new Contact records. Stripe data will be populated.')
                .addTag('ContactTriggerHelper')
                .addTag('Success');
            Logger.saveLog();
        } catch (Exception ex) {
            // Handle any other unexpected errors
            Logger.error('Unexpected error in processContactAfterInsert: ' + ex.getMessage(), ex)
                .setMessage('Unexpected error occurred. Stack trace: ' + ex.getStackTraceString())
                .addTag('ContactTriggerHelper')
                .addTag('Unexpected-Error');
            Logger.saveLog();
            throw ex;
        }
    }

    /**
     * @description Processes Contact records after update to sync changes to Stripe.
     *              Detects changes in relevant fields (Email, FirstName, LastName, Phone) and queues
     *              updates to Stripe Customer API via async queueable execution to avoid mixed DML
     *              and callout limitations. Only processes Contacts with a Stripe_Customer_ID__c.
     * @param newList List of updated Contact records
     * @param oldMap Map of old Contact records keyed by Id
     */
    public static void processContactAfterUpdate(List<Contact> newList, Map<Id, Contact> oldMap){
        try {
            // Validate input parameters
            if (newList == null || newList.isEmpty() || oldMap == null) {
                Logger.warn('processContactAfterUpdate called with null or empty parameters')
                    .addTag('ContactTriggerHelper');
                Logger.saveLog();
                return;
            }

            List<Contact> contactsToSync = new List<Contact>();

            for (Contact newContact : newList) {
                Contact oldContact = oldMap.get(newContact.Id);

                // Skip if no Stripe Customer ID is set
                if (String.isBlank(newContact.Stripe_Customer_ID__c)) {
                    continue;
                }

                // Check if any relevant fields changed
                Boolean hasChanges = false;
                if (newContact.Email != oldContact.Email ||
                    newContact.FirstName != oldContact.FirstName ||
                    newContact.LastName != oldContact.LastName ||
                    newContact.Phone != oldContact.Phone) {
                    hasChanges = true;
                }

                if (hasChanges) {
                    contactsToSync.add(newContact);
                }
            }

            // Queue the Stripe update if there are contacts to sync
            if (!contactsToSync.isEmpty()) {
                Logger.info('Queueing ' + contactsToSync.size() + ' Contact(s) for Stripe sync')
                    .addTag('ContactTriggerHelper')
                    .addTag('Stripe-Sync');
                Logger.saveLog();

                // Use Queueable to handle callouts asynchronously
                System.enqueueJob(new StripeCustomerUpdateQueueable(contactsToSync));
            }
        } catch (Exception ex) {
            // Log error but don't throw to prevent blocking the DML operation
            Logger.error('Error in processContactAfterUpdate: ' + ex.getMessage(), ex)
                .setMessage('Failed to queue Stripe Customer updates. Stack trace: ' + ex.getStackTraceString())
                .addTag('ContactTriggerHelper')
                .addTag('Stripe-Sync-Error');
            Logger.saveLog();
        }
    }

    /**
     * @description Queueable class for async Stripe Customer updates.
     *              Processes Contact updates and syncs them to Stripe API using callouts.
     *              Includes comprehensive error handling, logging, and retry logic with exponential backoff.
     */
    public class StripeCustomerUpdateQueueable implements Queueable, Database.AllowsCallouts {
        private List<Contact> contactsToUpdate;
        private Map<Id, Integer> contactRetryCount;

        public StripeCustomerUpdateQueueable(List<Contact> contacts) {
            this(contacts, new Map<Id, Integer>());
        }

        public StripeCustomerUpdateQueueable(List<Contact> contacts, Map<Id, Integer> retryCountMap) {
            this.contactsToUpdate = contacts;
            this.contactRetryCount = retryCountMap;
        }

        public void execute(QueueableContext context) {
            Integer successCount = 0;
            Integer failureCount = 0;
            List<Contact> contactsToUpdateSalesforce = new List<Contact>();
            List<Contact> contactsToRetry = new List<Contact>();
            Map<Id, Integer> newRetryCountMap = new Map<Id, Integer>();

            for (Contact cont : contactsToUpdate) {
                try {
                    // Build customer name from FirstName and LastName
                    String customerName = '';
                    if (String.isNotBlank(cont.FirstName) && String.isNotBlank(cont.LastName)) {
                        customerName = cont.FirstName + ' ' + cont.LastName;
                    } else if (String.isNotBlank(cont.LastName)) {
                        customerName = cont.LastName;
                    } else if (String.isNotBlank(cont.FirstName)) {
                        customerName = cont.FirstName;
                    }

                    // Create customer wrapper
                    StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(customerName, cont.Email, cont.Phone);

                    // Call Stripe API to update customer
                    String updatedCustomerId = StripeAPIService.updateCustomer(customerWrapper, cont.Stripe_Customer_ID__c);

                    // Update Contact record with Stripe Customer ID
                    Contact contactToUpdate = new Contact(
                        Id = cont.Id,
                        Stripe_Customer_ID__c = updatedCustomerId
                    );
                    contactsToUpdateSalesforce.add(contactToUpdate);

                    Logger.info('Successfully updated Stripe Customer: ' + updatedCustomerId)
                        .setMessage('Contact Id: ' + cont.Id)
                        .addTag('ContactTriggerHelper')
                        .addTag('Stripe-Update-Success');
                    Logger.saveLog();

                    successCount++;
                } catch (StripeException ex) {
                    // Get current retry count for this contact
                    Integer currentRetryCount = contactRetryCount.get(cont.Id) != null ? contactRetryCount.get(cont.Id) : 0;

                    // Check if this error is retryable and we haven't exceeded max retries
                    if (ex.isRetryable() && currentRetryCount < StripeAPIService.MAX_RETRY_COUNT) {
                        contactsToRetry.add(cont);
                        newRetryCountMap.put(cont.Id, currentRetryCount + 1);

                        Logger.warn('Retryable error for Contact: ' + cont.Id + '. Will retry (attempt ' +
                                  (currentRetryCount + 1) + ' of ' + StripeAPIService.MAX_RETRY_COUNT + ')')
                            .setMessage('Stripe Customer ID: ' + cont.Stripe_Customer_ID__c + ', Error: ' + ex.getDetailedMessage())
                            .addTag('ContactTriggerHelper')
                            .addTag('Stripe-Update-Retry');
                        Logger.saveLog();
                    } else {
                        failureCount++;
                        Logger.error('Failed to update Stripe Customer for Contact: ' + cont.Id + ' (max retries exceeded or not retryable)', ex)
                            .setMessage('Stripe Customer ID: ' + cont.Stripe_Customer_ID__c + ', Error: ' + ex.getDetailedMessage())
                            .addTag('ContactTriggerHelper')
                            .addTag('Stripe-Update-Error');
                        Logger.saveLog();
                    }
                } catch (Exception ex) {
                    failureCount++;
                    Logger.error('Failed to update Stripe Customer for Contact: ' + cont.Id, ex)
                        .setMessage('Stripe Customer ID: ' + cont.Stripe_Customer_ID__c + ', Error: ' + ex.getMessage())
                        .addTag('ContactTriggerHelper')
                        .addTag('Stripe-Update-Error');
                    Logger.saveLog();
                }
            }

            // Update Contact records in Salesforce
            if (!contactsToUpdateSalesforce.isEmpty()) {
                try {
                    if (Schema.SObjectType.Contact.isUpdateable()) {
                        SObjectAccessDecision decision = Security.stripInaccessible(
                            AccessType.UPDATABLE,
                            contactsToUpdateSalesforce
                        );
                        update decision.getRecords();
                        Logger.info('Successfully updated ' + decision.getRecords().size() + ' Contact records in Salesforce')
                            .addTag('ContactTriggerHelper')
                            .addTag('Contact-Update-Success');
                        Logger.saveLog();
                    }
                } catch (Exception ex) {
                    Logger.error('Failed to update Contact records in Salesforce', ex)
                        .setMessage('Error: ' + ex.getMessage())
                        .addTag('ContactTriggerHelper')
                        .addTag('Contact-Update-Error');
                    Logger.saveLog();
                }
            }

            // Re-enqueue contacts that need retry with exponential backoff
            if (!contactsToRetry.isEmpty()) {
                // Calculate delay based on the maximum retry count in the batch
                Integer maxRetryCount = 0;
                for (Integer retryCount : newRetryCountMap.values()) {
                    if (retryCount > maxRetryCount) {
                        maxRetryCount = retryCount;
                    }
                }

                // Calculate exponential backoff delay in minutes
                Integer delayMinutes = (Integer)(Math.pow(2, maxRetryCount - 1) * StripeAPIService.BASE_DELAY_MINUTES);

                Logger.info('Re-enqueueing ' + contactsToRetry.size() + ' contacts for retry with ' + delayMinutes + ' minute delay')
                    .addTag('ContactTriggerHelper')
                    .addTag('Stripe-Retry-Enqueue');
                Logger.saveLog();

                // Re-enqueue with delay
                StripeCustomerUpdateQueueable retryJob = new StripeCustomerUpdateQueueable(contactsToRetry, newRetryCountMap);
                System.enqueueJob(retryJob, delayMinutes);
            }

            Logger.info('Completed Stripe Customer updates (Contact records now store all customer data)')
                .setMessage('Success: ' + successCount + ', Failures: ' + failureCount + ', Retries: ' + contactsToRetry.size())
                .addTag('ContactTriggerHelper')
                .addTag('Stripe-Sync-Complete');
            Logger.saveLog();
        }
    }
}