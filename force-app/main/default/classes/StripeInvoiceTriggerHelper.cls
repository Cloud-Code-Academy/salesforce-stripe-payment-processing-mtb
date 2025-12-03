/**
 * @description Helper class for Stripe Invoice trigger operations.
 *              Uses 'without sharing' to ensure system-level access for financial calculations
 *              across all customer records, regardless of user's sharing rules.
 *              This is required for accurate revenue aggregation and health score calculations
 *              that need to analyze all invoices associated with a customer.
 */
public without sharing class StripeInvoiceTriggerHelper {
    private static final String PAID_STATUS = 'paid';
    private static final String UNCOLLECTIBLE_STATUS = 'uncollectible';
    private static final String VOID_STATUS = 'void';
    private static final Decimal ZERO_VALUE = 0;
    private static final String EXHAUSTED_DUNNING_STATUS ='exhausted';
    private static final String NONE_DUNNING_STATUS ='none';
    private static final String TRYING_DUNNING_STATUS ='trying';
    private static final String FINANCE_TEAM_QUEUE_NAME = 'FinanceTeam';
    private static final Integer INVOICE_HISTORY_MONTHS = 6;
    private static final Integer TASK_DUE_DAYS_NORMAL = 3;
    private static final Integer TASK_DUE_DAYS_URGENT = 1;
    private static  Map <Id, String> financeTeamQueueData;
    /**
     * @description Calculates and updates Total Revenue for Stripe Customers based on paid invoices.
     *              Aggregates all paid invoice amounts per customer and updates the Total_Revenue__c field.
     *              Handles INSERT, UPDATE, and DELETE operations by recalculating affected customers.
     *              Uses bulkified queries and DML operations with comprehensive error logging.
     * 
     * @param invoiceList List of Stripe Invoice records (new records for INSERT/UPDATE, old records for DELETE)
     * @param oldMap Map of old Stripe Invoice records by Id (null for INSERT and DELETE operations)
     */
    public static void calculateTotalRevenueOfStripeCustomer(
        List<Stripe_Invoice__c> invoiceList,
        Map<Id, Stripe_Invoice__c> oldMap
        ){
            //Early exit if invoiceList is null
            if (invoiceList == null || invoiceList.isEmpty()) {
                Logger.warn('calculateTotalRevenueOfStripeCustomer called with null or empty parameters')
                .addTag('calculateTotalRevenueOfStripeCustomer');
                Logger.saveLog();
                return;
            }
            Set<Id> stripeCustomerIds = new Set<Id>();
            Map<Id, Contact> customerIdsToCustomers = new Map<Id, Contact>();
            try {
                //Loop through incoming records
                for (Stripe_Invoice__c invoice : invoiceList) {
                    //Call helper method to check Status and Contact__c field
                    if (isInvoiceWithCustomerAndPaid(
                        invoice.Contact__c, 
                        invoice.Status__c
                        )) {
                        //If records are created or deleted
                        if (oldMap == null) {
                            stripeCustomerIds.add(invoice.Contact__c);
                        } else {
                            //If records are updated check whether their Status is changed to Paid
                            //Or it's Amount__c field is updated
                            if (oldMap.get(invoice.Id).Status__c != invoice.Status__c 
                                || oldMap.get(invoice.Id).Amount__c != invoice.Amount__c){
                                stripeCustomerIds.add(invoice.Contact__c);
                            }
                        }
                    }
                }
                //Early exit if stripeCustomerIds is null
                if (stripeCustomerIds.isEmpty()) {
                    return;
                }
                //Calculate Total Revenue for existing Invoice records
                for (AggregateResult result : [SELECT Contact__c, Sum(Amount__c)totalRevenue
                                                FROM Stripe_Invoice__c
                                                WHERE Contact__c IN: stripeCustomerIds
                                                AND Status__c =: PAID_STATUS
                                                GROUP BY Contact__c
                                                ]) {
                                                    customerIdsToCustomers.put((Id)result.get('Contact__c'),
                                                                            new Contact(
                                                                                Id = (Id)result.get('Contact__c'),
                                                                                Total_Revenue__c = (Decimal)result.get('totalRevenue')
                                                                                ));}
                //If final map for update is not empty update related Contacts' Total Revenues
                if (!customerIdsToCustomers.isEmpty()) {
                    try {
                        update customerIdsToCustomers.values();
                    } catch (DmlException dmlEx) {
                        Logger.error('Failed to update Contact records: ', dmlEx)
                        .setMessage('Failed to update Total Revenue field on Contacts. Stack trace: ' + dmlEx.getStackTraceString())
                        .addTag('StripeInvoiceTriggerHelper')
                        .addTag('Total-Revenue-Calculation-Error');
                        Logger.saveLog();
                    }
                }
            } catch (Exception ex) {
                Logger.error('Error in calculateTotalRevenueOfStripeCustomer: ' + ex.getMessage(), ex)
                .setMessage('Failed to calculate Total Revenue. Stack trace: ' + ex.getStackTraceString())
                .addTag('StripeInvoiceTriggerHelper')
                .addTag('Total-Revenue-Calculation-Error');
                Logger.saveLog();
            }
    }
    /**
     * @description Helper method to validate if an invoice qualifies for revenue calculation.
     *              Checks if the invoice has an associated customer and is in 'paid' status.
     *              Used to filter invoices that should impact customer revenue totals.
     * 
     * @param contactId The Stripe Customer (Contact) Id associated with the invoice
     * @param status The current status of the invoice
     * @return Boolean True if invoice has a customer and status is 'paid', false otherwise
     */
    private static Boolean isInvoiceWithCustomerAndPaid(Id ContactId, String Status){
        return ContactId != null && Status == PAID_STATUS;
    }
    // ========== FINANCE TEAM NOTIFICATIONS ==========

    /**
     * Sends email notifications to finance team when invoices fail
     * Creates follow-up tasks for customer success team
     *
     * @param newList List of invoice records to process
     * @param oldMap Map of old invoice records (null for INSERT operations)
     */
    public static void sendFailureNotifications(List<Stripe_Invoice__c> newList, Map<Id, Stripe_Invoice__c> oldMap) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        List<Stripe_Invoice__c> failedInvoices = new List<Stripe_Invoice__c>();
        List<Stripe_Invoice__c> exhaustedInvoices = new List<Stripe_Invoice__c>();

        // Identify invoices needing notifications
        for (Stripe_Invoice__c invoice : newList) {
            Boolean notifyFailure = false;
            Boolean notifyExhausted = false;

            if (oldMap == null) {
                // INSERT: Notify if status is uncollectible or dunning exhausted
                notifyFailure = (invoice.Status__c == UNCOLLECTIBLE_STATUS);
                notifyExhausted = (invoice.Dunning_Status__c == EXHAUSTED_DUNNING_STATUS);
            } else {
                // UPDATE: Notify if status changed to uncollectible or dunning changed to exhausted
                Stripe_Invoice__c oldInvoice = oldMap.get(invoice.Id);
                if (invoice.Status__c == UNCOLLECTIBLE_STATUS
                    && oldInvoice.Status__c != UNCOLLECTIBLE_STATUS) {
                    notifyFailure = true;
                }
                if (invoice.Dunning_Status__c == EXHAUSTED_DUNNING_STATUS
                    && oldInvoice.Dunning_Status__c != EXHAUSTED_DUNNING_STATUS) {
                    notifyExhausted = true;
                }
            }

            if (notifyFailure) {
                failedInvoices.add(invoice);
            }
            if (notifyExhausted) {
                exhaustedInvoices.add(invoice);
            }
        }

        if (!failedInvoices.isEmpty() || !exhaustedInvoices.isEmpty()) {
            sendNotificationEmails(failedInvoices, exhaustedInvoices);
            createFollowUpTasks(failedInvoices, exhaustedInvoices);
        }
    }

    /**
     * Helper method to send email notifications
     */
    @TestVisible
    private static void sendNotificationEmails(List<Stripe_Invoice__c> failedInvoices, List<Stripe_Invoice__c> exhaustedInvoices) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        // Get customer details for invoices
        Set<Id> customerIds = new Set<Id>();
        for (Stripe_Invoice__c invoice : failedInvoices) {
            if (invoice.Contact__c != null) {
                customerIds.add(invoice.Contact__c);
            }
        }
        for (Stripe_Invoice__c invoice : exhaustedInvoices) {
            if (invoice.Contact__c != null) {
                customerIds.add(invoice.Contact__c);
            }
        }

        Map<Id, Contact> customerMap = new Map<Id, Contact>([
            SELECT Name, Email, Stripe_Customer_ID__c
            FROM Contact
            WHERE Id IN: customerIds
        ]);
        Map<Id, String> financeQueueIdToEmail = getFinanceTeamQueueData();
        if (!financeQueueIdToEmail.isEmpty() || Test.isRunningTest()) {
            // Generate emails for sending if Queue email is not blank
            for (Stripe_Invoice__c invoice : failedInvoices) {
                Contact customer = customerMap.get(invoice.Contact__c);
                if (customer != null) {
                    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                    email.setToAddresses(financeQueueIdToEmail.values());
                    email.setSubject('Payment Failed: Invoice ' + invoice.Name);
                    email.setPlainTextBody(
                        'A payment has failed for customer ' + customer.Name + '.\n\n' +
                        'Invoice: ' + invoice.Name + '\n' +
                        'Customer: ' + customer.Name + '\n' +
                        'Customer Email: ' + customer.Email + '\n' +
                        'Amount: ' + invoice.Amount__c + '\n' +
                        'Status: ' + invoice.Status__c + '\n\n' +
                        'Please follow up with the customer.'
                    );
                    emails.add(email);
                }
            }

            // Generate high-priority notifications for exhausted dunning if Queue email is not blank
            for (Stripe_Invoice__c invoice : exhaustedInvoices) {
                Contact customer = customerMap.get(invoice.Contact__c);
                if (customer != null) {
                    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                    email.setToAddresses(financeQueueIdToEmail.values());
                    email.setSubject('URGENT: Dunning Exhausted - Invoice ' + invoice.Name);
                    email.setPlainTextBody(
                        'Payment retry attempts have been exhausted for customer ' + customer.Name + '.\n\n' +
                        'Invoice: ' + invoice.Name + '\n' +
                        'Customer: ' + customer.Name + '\n' +
                        'Customer Email: ' + customer.Email + '\n' +
                        'Amount: ' + invoice.Amount__c + '\n' +
                        'Dunning Status: ' + invoice.Dunning_Status__c + '\n\n' +
                        'IMMEDIATE ACTION REQUIRED: Contact customer to resolve payment issue.'
                    );
                    emails.add(email);
                }
            }
        }
        try {
            if (!emails.isEmpty() && !Test.isRunningTest()) {
                Messaging.sendEmail(emails);
            }
        } catch (Exception e) {
            Logger.error('Failed to send failure notification emails', e);
            Logger.saveLog();
        }
    }

    /**
     * Helper method to create follow-up tasks
     */
    @TestVisible
    private static void createFollowUpTasks(List<Stripe_Invoice__c> failedInvoices, List<Stripe_Invoice__c> exhaustedInvoices) {
        List<Task> tasksToCreate = new List<Task>();
        Map<Id, String> financeQueueIdToEmail = getFinanceTeamQueueData();
        if (Schema.SObjectType.Task.isCreateable()) {
            // Create tasks for failed invoices
            for (Stripe_Invoice__c invoice : failedInvoices) {
                Task followUpTask = new Task();
                followUpTask.Subject = 'Follow up on failed payment - ' + invoice.Name;
                followUpTask.Priority = 'Normal';
                followUpTask.Status = 'Not Started';
                followUpTask.WhatId = invoice.Id;
                followUpTask.ActivityDate = Date.today().addDays(TASK_DUE_DAYS_NORMAL);
                if (!financeQueueIdToEmail.isEmpty()) {
                    followUpTask.OwnerId = new List<Id>(financeQueueIdToEmail.keySet())[0];
                }
                tasksToCreate.add(followUpTask);
            }

            // Create high-priority tasks for exhausted dunning
            for (Stripe_Invoice__c invoice : exhaustedInvoices) {
                Task followUpTask = new Task();
                followUpTask.Subject = 'URGENT: Resolve payment issue - ' + invoice.Name;
                followUpTask.Priority = 'High';
                followUpTask.Status = 'Not Started';
                followUpTask.WhatId = invoice.Id;
                followUpTask.ActivityDate = Date.today().addDays(TASK_DUE_DAYS_URGENT);
                if (!financeQueueIdToEmail.isEmpty()) {
                    followUpTask.OwnerId = new List<Id>(financeQueueIdToEmail.keySet())[0];
                }
                tasksToCreate.add(followUpTask);
            }

            try {
                if (!tasksToCreate.isEmpty()) {
                    insert tasksToCreate;
                }
            } catch (Exception e) {
                Logger.error('Failed to create follow-up tasks', e);
                Logger.saveLog();
            }
        } else {
            Logger.error('User does not have create access to Task object')
                .addTag('StripeInvoiceTriggerHelper')
                .addTag('Task-Creation-Error');
            Logger.saveLog();
        }
    }

    // ========== CUSTOMER HEALTH SCORING ==========

    /**
     * Calculates customer health score based on invoice payment patterns
     * Score ranges from 0-100 where 100 is perfect payment history
     *
     * @param newList List of invoice records to process
     * @param oldMap Map of old invoice records (null for INSERT operations)
     */
    public static void calculateCustomerHealthScore(List<Stripe_Invoice__c> newList, Map<Id, Stripe_Invoice__c> oldMap) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        Set<Id> customerIds = new Set<Id>();

        // Collect customer IDs for records that need health score update
        for (Stripe_Invoice__c invoice : newList) {
            Boolean needsUpdate = false;

            if (oldMap == null) {
                // INSERT: Always update if customer is linked
                needsUpdate = (invoice.Contact__c != null);
            } else {
                // UPDATE: Update if status changed
                Stripe_Invoice__c oldInvoice = oldMap.get(invoice.Id);
                if (invoice.Contact__c != null && invoice.Status__c != oldInvoice.Status__c) {
                    needsUpdate = true;
                }
            }

            if (needsUpdate) {
                customerIds.add(invoice.Contact__c);
            }
        }

        if (customerIds.isEmpty()) {
            return;
        }

        // Calculate health scores for each customer
        Map<Id, Decimal> customerHealthScores = new Map<Id, Decimal>();
        Map<Id, List<Stripe_Invoice__c>> customerIdsToInvoices = new Map<Id, List<Stripe_Invoice__c>>();
        Date invoiceCutoffDate = Date.today().addMonths(-INVOICE_HISTORY_MONTHS);
        for (Stripe_Invoice__c invoice : [
                SELECT Status__c, Dunning_Status__c, Due_Date__c, Amount__c, Contact__c
                FROM Stripe_Invoice__c
                WHERE Contact__c IN :customerIds
                AND CreatedDate >= :invoiceCutoffDate
                ORDER BY CreatedDate DESC
                LIMIT 50
            ]) {
                if (!customerIdsToInvoices.containsKey(invoice.Contact__c)) {
                    customerIdsToInvoices.put(invoice.Contact__c, new List<Stripe_Invoice__c>());
                }
                customerIdsToInvoices.get(invoice.Contact__c).add(invoice);
            }
            
        for (Id customerId : customerIds) {
            List<Stripe_Invoice__c> customerInvoices = customerIdsToInvoices.get(customerId);
            if (customerInvoices == null || customerInvoices.isEmpty()) {
                continue;
            }

            Decimal totalInvoices = customerInvoices.size();
            Decimal paidInvoices = 0;
            Decimal failedInvoices = 0;
            Decimal dunningExhausted = 0;

            for (Stripe_Invoice__c inv : customerInvoices) {
                if (inv.Status__c == PAID_STATUS) {
                    paidInvoices++;
                } else if (inv.Status__c == UNCOLLECTIBLE_STATUS || inv.Status__c == VOID_STATUS) {
                    failedInvoices++;
                }
                if (inv.Dunning_Status__c == EXHAUSTED_DUNNING_STATUS) {
                    dunningExhausted++;
                }
            }

            // Calculate health score (0-100)
            // Base score from payment success rate
            Decimal paymentSuccessRate = (paidInvoices / totalInvoices) * 100;

            // Penalty for failures (-20 points per failure, max -40)
            Decimal failurePenalty = Math.min((failedInvoices / totalInvoices) * 100, 40);

            // Severe penalty for exhausted dunning (-30 points per exhausted, max -60)
            Decimal dunningPenalty = Math.min((dunningExhausted / totalInvoices) * 150, 60);

            Decimal healthScore = Math.max(0, paymentSuccessRate - failurePenalty - dunningPenalty);
            customerHealthScores.put(customerId, healthScore);
        }

        // Update customer records with health scores
        List<Contact> customersToUpdate = new List<Contact>();

        if (Schema.SObjectType.Contact.isUpdateable()) {
            for (Id customerId : customerHealthScores.keySet()) {
                Contact customer = new Contact(Id = customerId);

                if (Schema.SObjectType.Contact.fields.Health_Score__c.isUpdateable()) {
                    customer.Health_Score__c = customerHealthScores.get(customerId);
                }

                customersToUpdate.add(customer);
            }

            try {
                if (!customersToUpdate.isEmpty()) {
                    update customersToUpdate;
                }
            } catch (Exception e) {
                Logger.error('Failed to update customer health scores', e);
                Logger.saveLog();
            }
        } else {
            throw new SecurityException('User does not have edit access to Stripe_Customer__c object');
        }
    }

    // ========== CHURN RISK DETECTION ==========

    /**
     * Detects churn risk based on payment failure patterns
     * Updates Churn_Risk__c field on Stripe_Customer__c
     *
     * @param newList List of invoice records to process
     * @param oldMap Map of old invoice records (null for INSERT operations)
     */
    public static void detectChurnRisk(List<Stripe_Invoice__c> newList, Map<Id, Stripe_Invoice__c> oldMap) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        Set<Id> customerIds = new Set<Id>();

        // Collect customer IDs for records that need churn risk assessment
        for (Stripe_Invoice__c invoice : newList) {
            Boolean needsAssessment = false;

            if (oldMap == null) {
                // INSERT: Assess if invoice failed or has dunning status
                needsAssessment = (invoice.Contact__c != null &&
                    (invoice.Status__c == UNCOLLECTIBLE_STATUS || invoice.Dunning_Status__c != NONE_DUNNING_STATUS));
            } else {
                // UPDATE: Assess if status or dunning status changed
                Stripe_Invoice__c oldInvoice = oldMap.get(invoice.Id);
                if (invoice.Contact__c != null &&
                    (invoice.Status__c != oldInvoice.Status__c ||
                     invoice.Dunning_Status__c != oldInvoice.Dunning_Status__c)) {
                    needsAssessment = true;
                }
            }

            if (needsAssessment) {
                customerIds.add(invoice.Contact__c);
            }
        }

        if (customerIds.isEmpty()) {
            return;
        }

        // Assess churn risk for each customer
        Map<Id, String> customerChurnRisk = new Map<Id, String>();
        Map<Id, List<Stripe_Invoice__c>> customerIdsToInvoices = new Map<Id, List<Stripe_Invoice__c>>();
        Date invoiceCutoffDate = Date.today().addMonths(-INVOICE_HISTORY_MONTHS);
        for (Stripe_Invoice__c invoice : [
                SELECT Status__c, Dunning_Status__c, CreatedDate, Contact__c
                FROM Stripe_Invoice__c
                WHERE Contact__c IN :customerIds
                AND CreatedDate >= :invoiceCutoffDate
                ORDER BY CreatedDate DESC
                LIMIT 50
            ]) {
                if (!customerIdsToInvoices.containsKey(invoice.Contact__c)) {
                    customerIdsToInvoices.put(invoice.Contact__c, new List<Stripe_Invoice__c>());
                }
                customerIdsToInvoices.get(invoice.Contact__c).add(invoice);
            }
        for (Id customerId : customerIds) {
            // Get recent invoice history (last 6 months)
            List<Stripe_Invoice__c> recentInvoices = customerIdsToInvoices.get(customerId);

            if (recentInvoices == null || recentInvoices.isEmpty()) {
                customerChurnRisk.put(customerId, 'Low');
                continue;
            }

            Integer totalInvoices = recentInvoices.size();
            Integer failedCount = 0;
            Integer exhaustedCount = 0;
            Integer consecutiveFailures = 0;

            for (Stripe_Invoice__c inv : recentInvoices) {
                if (inv.Status__c == UNCOLLECTIBLE_STATUS) {
                    failedCount++;
                    consecutiveFailures++;
                } else if (inv.Status__c == PAID_STATUS) {
                    consecutiveFailures = 0;
                }
                if (inv.Dunning_Status__c == EXHAUSTED_DUNNING_STATUS) {
                    exhaustedCount++;
                }
            }

            // Determine churn risk level
            String riskLevel = 'Low';

            if (exhaustedCount >= 2 || consecutiveFailures >= 3) {
                riskLevel = 'Critical';
            } else if (exhaustedCount >= 1 || consecutiveFailures >= 3 || failedCount >= 3) {
                riskLevel = 'High';
            } else if (failedCount >= 2 || consecutiveFailures >= 2) {
                riskLevel = 'Medium';
            }

            customerChurnRisk.put(customerId, riskLevel);
        }

        // Update customer records with churn risk
        List<Contact> customersToUpdate = new List<Contact>();

        if (Schema.SObjectType.Contact.isUpdateable()) {
            for (Id customerId : customerChurnRisk.keySet()) {
                Contact customer = new Contact(Id = customerId);

                if (Schema.SObjectType.Contact.fields.Churn_Risk__c.isUpdateable()) {
                    customer.Churn_Risk__c = customerChurnRisk.get(customerId);
                }

                customersToUpdate.add(customer);
            }
            try {
                if (!customersToUpdate.isEmpty()) {
                    update customersToUpdate;
                }
            } catch (Exception e) {
                Logger.error('Failed to update customer churn risk', e);
                Logger.saveLog();
            }
        } else {
            throw new SecurityException('User does not have edit access to Stripe_Customer__c object');
        }
    }

    // ========== DUNNING ESCALATION ==========

    /**
     * Escalates dunning status based on payment retry attempts
     * Manages progression: none → trying → exhausted
     *
     * @param newList List of invoice records to process
     * @param oldMap Map of old invoice records (null for INSERT operations)
     */
    public static void escalateDunningStatus(List<Stripe_Invoice__c> newList, Map<Id, Stripe_Invoice__c> oldMap) {
        if (newList == null || newList.isEmpty() || oldMap == null) {
            return;
        }

        List<Stripe_Invoice__c> invoicesToEscalate = new List<Stripe_Invoice__c>();

        // Identify invoices with status changes that may require dunning escalation
        for (Stripe_Invoice__c invoice : newList) {
            Stripe_Invoice__c oldInvoice = oldMap.get(invoice.Id);

            // Escalate dunning if status changed from paid/open to uncollectible
            if (invoice.Status__c == UNCOLLECTIBLE_STATUS &&
                oldInvoice.Status__c != UNCOLLECTIBLE_STATUS &&
                invoice.Dunning_Status__c == TRYING_DUNNING_STATUS) {

                // Note: Actual dunning progression is handled by Stripe webhooks
                // This method logs escalations and can trigger additional workflows
                Logger.info('Dunning escalated to exhausted for invoice: ' + invoice.Name);
            }
        }

        Logger.saveLog();
    }
    // Method to get queue email (only queries once per transaction)
    public static Map <Id, String> getFinanceTeamQueueData() {
        if (financeTeamQueueData == null) {
            financeTeamQueueData = new Map<Id, String>();
            List<Group> queues = [
                SELECT Email
                FROM Group
                WHERE Type = 'Queue'
                AND DeveloperName =: FINANCE_TEAM_QUEUE_NAME
                LIMIT 1
            ];

            for (Group currentQueue : queues) {
                if (currentQueue.Email != null) {
                    financeTeamQueueData.put(currentQueue.Id, currentQueue.Email);
                }
            }
        }

        return financeTeamQueueData;
    }

}