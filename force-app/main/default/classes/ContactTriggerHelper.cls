public with sharing class ContactTriggerHelper {
    /**
     * @description Helper class for Contact trigger operations. Automatically creates Stripe Customer records
     *              when new Contacts are inserted, mapping relevant Contact data (email, name, phone) to the
     *              Stripe Customer object while enforcing object-level security and user-mode permissions.
     *              Includes comprehensive error handling and logging for all failure scenarios.
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

            List<Stripe_Customer__c> stripeCustomersForInsert = new List<Stripe_Customer__c>();
            Integer successCount = 0;
            Integer failureCount = 0;

            for (Contact cont : newList) {
                try {
                    // Validate Contact data
                    if (cont.Id == null) {
                        Logger.warn('Skipping Contact with null Id')
                            .addTag('ContactTriggerHelper')
                            .addTag('Validation-Error');
                        Logger.saveLog();
                        failureCount++;
                        continue;
                    }

                    // Skip contacts without email (Customer_Email__c is required on Stripe_Customer__c)
                    if (String.isBlank(cont.Email)) {
                        Logger.warn('Skipping Contact without email: ' + cont.Id)
                            .addTag('ContactTriggerHelper')
                            .addTag('Missing-Required-Field');
                        Logger.saveLog();
                        failureCount++;
                        continue;
                    }

                    Stripe_Customer__c customer = new Stripe_Customer__c();
                    customer.Contact__c = cont.Id;

                    // Map Contact email
                    customer.Customer_Email__c = cont.Email;

                    // Map Contact name
                    if (String.isNotBlank(cont.FirstName)) {
                        customer.Customer_Name__c = cont.LastName + ' ' + cont.FirstName;
                    } else if (String.isNotBlank(cont.LastName)) {
                        customer.Customer_Name__c = cont.LastName;
                    } else {
                        // Log warning if Contact has no name
                        Logger.warn('Contact has no name: ' + cont.Id)
                            .addTag('ContactTriggerHelper')
                            .addTag('Missing-Data');
                        Logger.saveLog();
                    }

                    // Map Contact phone
                    if (cont.Phone != null) {
                        customer.Customer_Phone__c = cont.Phone;
                    }

                    stripeCustomersForInsert.add(customer);
                    successCount++;
                } catch (Exception ex) {
                    // Log individual record processing error but continue with other records
                    failureCount++;
                    Logger.error('Error processing Contact: ' + cont.Id, ex)
                        .setMessage('Failed to create Stripe Customer record. Error: ' + ex.getMessage())
                        .addTag('ContactTriggerHelper')
                        .addTag('Record-Processing-Error');
                    Logger.saveLog();
                }
            }

            // Perform DML operation
            if (!stripeCustomersForInsert.isEmpty()) {
                // Check whether Stripe_Customer__c object is available for Create for User
                if (Schema.SObjectType.Stripe_Customer__c.isCreateable()) {
                    // Strip inaccessible fields to respect field-level security
                    SObjectAccessDecision decision = Security.stripInaccessible(
                        AccessType.CREATABLE,
                        stripeCustomersForInsert
                    );
                    insert decision.getRecords();
                    Logger.info('Successfully created ' + decision.getRecords().size() + ' Stripe Customer records from ' + newList.size() + ' Contacts')
                        .addTag('ContactTriggerHelper')
                        .addTag('Success');
                    Logger.saveLog();
                } else {
                    throw new SecurityException('User does not have create access to Stripe_Customer__c object');
                }
            } else {
                // Log if no customers were created
                Logger.warn('No Stripe Customer records were created. Processed: ' + newList.size() + ' Contacts, Failures: ' + failureCount)
                    .addTag('ContactTriggerHelper')
                    .addTag('No-Records-Created');
                Logger.saveLog();
            }
        } catch (DmlException dmlEx) {
            // Handle DML-specific errors with detailed information
            Logger.error('DML error creating Stripe Customer records: ' + dmlEx.getMessage(), dmlEx)
                .setMessage('Failed to insert Stripe Customers. Details: ' + dmlEx.getDmlMessage(0))
                .addTag('ContactTriggerHelper')
                .addTag('DML-Error');
            Logger.saveLog();
            throw dmlEx;
        } catch (SecurityException secEx) {
            // Handle security/permission errors
            Logger.error('Security error: User lacks permissions to create Stripe Customer records', secEx)
                .addTag('ContactTriggerHelper')
                .addTag('Security-Error');
            Logger.saveLog();
            throw secEx;
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
     *              Includes comprehensive error handling and logging for each update operation.
     */
    public class StripeCustomerUpdateQueueable implements Queueable, Database.AllowsCallouts {
        private List<Contact> contactsToUpdate;

        public StripeCustomerUpdateQueueable(List<Contact> contacts) {
            this.contactsToUpdate = contacts;
        }

        public void execute(QueueableContext context) {
            Integer successCount = 0;
            Integer failureCount = 0;

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

                    Logger.info('Successfully updated Stripe Customer: ' + updatedCustomerId)
                        .setMessage('Contact Id: ' + cont.Id)
                        .addTag('ContactTriggerHelper')
                        .addTag('Stripe-Update-Success');
                    Logger.saveLog();

                    successCount++;
                } catch (Exception ex) {
                    failureCount++;
                    Logger.error('Failed to update Stripe Customer for Contact: ' + cont.Id, ex)
                        .setMessage('Stripe Customer ID: ' + cont.Stripe_Customer_ID__c + ', Error: ' + ex.getMessage())
                        .addTag('ContactTriggerHelper')
                        .addTag('Stripe-Update-Error');
                    Logger.saveLog();
                }
            }

            Logger.info('Completed Stripe Customer updates')
                .setMessage('Success: ' + successCount + ', Failures: ' + failureCount)
                .addTag('ContactTriggerHelper')
                .addTag('Stripe-Sync-Complete');
            Logger.saveLog();
        }
    }
}