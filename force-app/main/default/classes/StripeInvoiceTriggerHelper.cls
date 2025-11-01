public with sharing class StripeInvoiceTriggerHelper {

    // ========== REVENUE ROLLUP CALCULATIONS ==========

    /**
     * Rolls up paid invoice amounts to parent Stripe_Customer__c records
     * Updates Total_Revenue__c and MRR__c fields
     *
     * @param newList List of invoice records to process
     * @param oldMap Map of old invoice records (null for INSERT operations)
     */
    public static void rollupRevenueToCustomer(List<Stripe_Invoice__c> newList, Map<Id, Stripe_Invoice__c> oldMap) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        Set<Id> customerIds = new Set<Id>();

        // Collect customer IDs for records that need rollup
        for (Stripe_Invoice__c invoice : newList) {
            Boolean needsRollup = false;

            if (oldMap == null) {
                // INSERT: Always rollup if customer is linked and invoice is paid
                needsRollup = (invoice.Stripe_Customer__c != null && invoice.Status__c == 'paid');
            } else {
                // UPDATE: Rollup if status or amount changed
                Stripe_Invoice__c oldInvoice = oldMap.get(invoice.Id);
                if (invoice.Stripe_Customer__c != null &&
                    (invoice.Status__c != oldInvoice.Status__c || invoice.Amount__c != oldInvoice.Amount__c)) {
                    needsRollup = true;
                }
            }

            if (needsRollup) {
                customerIds.add(invoice.Stripe_Customer__c);
            }
        }

        if (customerIds.isEmpty()) {
            return;
        }

        // Query all paid invoices for affected customers
        Map<Id, Decimal> customerTotalRevenue = new Map<Id, Decimal>();
        Map<Id, Decimal> customerMRR = new Map<Id, Decimal>();

        for (AggregateResult ar : [
            SELECT Stripe_Customer__c, SUM(Amount__c) totalAmount
            FROM Stripe_Invoice__c
            WHERE Stripe_Customer__c IN :customerIds
                AND Status__c = 'paid'
                AND Amount__c != null
            GROUP BY Stripe_Customer__c
        ]) {
            Id customerId = (Id)ar.get('Stripe_Customer__c');
            Decimal totalAmount = (Decimal)ar.get('totalAmount');
            customerTotalRevenue.put(customerId, totalAmount);
        }

        // Calculate MRR from active subscriptions
        for (AggregateResult ar : [
            SELECT Stripe_Customer__c, SUM(Amount__c) monthlyAmount
            FROM Stripe_Subscription__c
            WHERE Stripe_Customer__c IN :customerIds
                AND Status__c = 'active'
                AND Amount__c != null
            GROUP BY Stripe_Customer__c
        ]) {
            Id customerId = (Id)ar.get('Stripe_Customer__c');
            Decimal monthlyAmount = (Decimal)ar.get('monthlyAmount');
            customerMRR.put(customerId, monthlyAmount);
        }

        // Update customer records
        List<Stripe_Customer__c> customersToUpdate = new List<Stripe_Customer__c>();

        if (Schema.SObjectType.Stripe_Customer__c.isUpdateable()) {
            for (Id customerId : customerIds) {
                Stripe_Customer__c customer = new Stripe_Customer__c(Id = customerId);

                if (Schema.SObjectType.Stripe_Customer__c.fields.Total_Revenue__c.isUpdateable()) {
                    customer.Total_Revenue__c = customerTotalRevenue.get(customerId);
                }

                if (Schema.SObjectType.Stripe_Customer__c.fields.MRR__c.isUpdateable()) {
                    customer.MRR__c = customerMRR.get(customerId);
                }

                customersToUpdate.add(customer);
            }

            try {
                if (!customersToUpdate.isEmpty()) {
                    update as user customersToUpdate;
                }
            } catch (Exception e) {
                Logger.error('Failed to rollup revenue to customers', e);
                Logger.saveLog();
            }
        } else {
            throw new SecurityException('User does not have edit access to Stripe_Customer__c object');
        }
    }

    /**
     * Rolls up invoice amounts to parent Stripe_Subscription__c records
     * Updates Total_Invoiced__c field
     *
     * @param newList List of invoice records to process
     * @param oldMap Map of old invoice records (null for INSERT operations)
     */
    public static void rollupRevenueToSubscription(List<Stripe_Invoice__c> newList, Map<Id, Stripe_Invoice__c> oldMap) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        Set<Id> subscriptionIds = new Set<Id>();

        // Collect subscription IDs for records that need rollup
        for (Stripe_Invoice__c invoice : newList) {
            Boolean needsRollup = false;

            if (oldMap == null) {
                // INSERT: Always rollup if subscription is linked
                needsRollup = (invoice.Stripe_Subscription__c != null);
            } else {
                // UPDATE: Rollup if amount changed
                Stripe_Invoice__c oldInvoice = oldMap.get(invoice.Id);
                if (invoice.Stripe_Subscription__c != null && invoice.Amount__c != oldInvoice.Amount__c) {
                    needsRollup = true;
                }
            }

            if (needsRollup) {
                subscriptionIds.add(invoice.Stripe_Subscription__c);
            }
        }

        if (subscriptionIds.isEmpty()) {
            return;
        }

        // Query all invoices for affected subscriptions
        Map<Id, Decimal> subscriptionTotalInvoiced = new Map<Id, Decimal>();

        for (AggregateResult ar : [
            SELECT Stripe_Subscription__c, SUM(Amount__c) totalAmount
            FROM Stripe_Invoice__c
            WHERE Stripe_Subscription__c IN :subscriptionIds
                AND Amount__c != null
            GROUP BY Stripe_Subscription__c
        ]) {
            Id subscriptionId = (Id)ar.get('Stripe_Subscription__c');
            Decimal totalAmount = (Decimal)ar.get('totalAmount');
            subscriptionTotalInvoiced.put(subscriptionId, totalAmount);
        }

        // Update subscription records
        List<Stripe_Subscription__c> subscriptionsToUpdate = new List<Stripe_Subscription__c>();

        if (Schema.SObjectType.Stripe_Subscription__c.isUpdateable()) {
            for (Id subscriptionId : subscriptionIds) {
                Stripe_Subscription__c subscription = new Stripe_Subscription__c(Id = subscriptionId);

                if (Schema.SObjectType.Stripe_Subscription__c.fields.Total_Invoiced__c.isUpdateable()) {
                    subscription.Total_Invoiced__c = subscriptionTotalInvoiced.get(subscriptionId);
                }

                subscriptionsToUpdate.add(subscription);
            }

            try {
                if (!subscriptionsToUpdate.isEmpty()) {
                    update as user subscriptionsToUpdate;
                }
            } catch (Exception e) {
                Logger.error('Failed to rollup revenue to subscriptions', e);
                Logger.saveLog();
            }
        } else {
            throw new SecurityException('User does not have edit access to Stripe_Subscription__c object');
        }
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
                notifyFailure = (invoice.Status__c == 'uncollectible');
                notifyExhausted = (invoice.Dunning_Status__c == 'exhausted');
            } else {
                // UPDATE: Notify if status changed to uncollectible or dunning changed to exhausted
                Stripe_Invoice__c oldInvoice = oldMap.get(invoice.Id);
                if (invoice.Status__c == 'uncollectible' && oldInvoice.Status__c != 'uncollectible') {
                    notifyFailure = true;
                }
                if (invoice.Dunning_Status__c == 'exhausted' && oldInvoice.Dunning_Status__c != 'exhausted') {
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
            if (invoice.Stripe_Customer__c != null) {
                customerIds.add(invoice.Stripe_Customer__c);
            }
        }
        for (Stripe_Invoice__c invoice : exhaustedInvoices) {
            if (invoice.Stripe_Customer__c != null) {
                customerIds.add(invoice.Stripe_Customer__c);
            }
        }

        Map<Id, Stripe_Customer__c> customerMap = new Map<Id, Stripe_Customer__c>([
            SELECT Id, Customer_Name__c, Customer_Email__c, Stripe_Customer_ID__c
            FROM Stripe_Customer__c
            WHERE Id IN :customerIds
        ]);

        // Send notifications for failed invoices
        for (Stripe_Invoice__c invoice : failedInvoices) {
            Stripe_Customer__c customer = customerMap.get(invoice.Stripe_Customer__c);
            if (customer != null) {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new String[]{'finance@example.com'}); // Configure via Custom Metadata
                email.setSubject('Payment Failed: Invoice ' + invoice.Name);
                email.setPlainTextBody(
                    'A payment has failed for customer ' + customer.Customer_Name__c + '.\n\n' +
                    'Invoice: ' + invoice.Name + '\n' +
                    'Customer: ' + customer.Customer_Name__c + '\n' +
                    'Customer Email: ' + customer.Customer_Email__c + '\n' +
                    'Amount: ' + invoice.Amount__c + '\n' +
                    'Status: ' + invoice.Status__c + '\n\n' +
                    'Please follow up with the customer.'
                );
                emails.add(email);
            }
        }

        // Send high-priority notifications for exhausted dunning
        for (Stripe_Invoice__c invoice : exhaustedInvoices) {
            Stripe_Customer__c customer = customerMap.get(invoice.Stripe_Customer__c);
            if (customer != null) {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new String[]{'finance@example.com'}); // Configure via Custom Metadata
                email.setSubject('URGENT: Dunning Exhausted - Invoice ' + invoice.Name);
                email.setPlainTextBody(
                    'Payment retry attempts have been exhausted for customer ' + customer.Customer_Name__c + '.\n\n' +
                    'Invoice: ' + invoice.Name + '\n' +
                    'Customer: ' + customer.Customer_Name__c + '\n' +
                    'Customer Email: ' + customer.Customer_Email__c + '\n' +
                    'Amount: ' + invoice.Amount__c + '\n' +
                    'Dunning Status: ' + invoice.Dunning_Status__c + '\n\n' +
                    'IMMEDIATE ACTION REQUIRED: Contact customer to resolve payment issue.'
                );
                emails.add(email);
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

        if (Schema.SObjectType.Task.isCreateable()) {
            // Create tasks for failed invoices
            for (Stripe_Invoice__c invoice : failedInvoices) {
                Task followUpTask = new Task();
                followUpTask.Subject = 'Follow up on failed payment - ' + invoice.Name;
                followUpTask.Priority = 'Normal';
                followUpTask.Status = 'Not Started';
                followUpTask.WhatId = invoice.Id;
                followUpTask.ActivityDate = Date.today().addDays(3);
                tasksToCreate.add(followUpTask);
            }

            // Create high-priority tasks for exhausted dunning
            for (Stripe_Invoice__c invoice : exhaustedInvoices) {
                Task followUpTask = new Task();
                followUpTask.Subject = 'URGENT: Resolve payment issue - ' + invoice.Name;
                followUpTask.Priority = 'High';
                followUpTask.Status = 'Not Started';
                followUpTask.WhatId = invoice.Id;
                followUpTask.ActivityDate = Date.today().addDays(1);
                tasksToCreate.add(followUpTask);
            }

            try {
                if (!tasksToCreate.isEmpty()) {
                    insert as user tasksToCreate;
                }
            } catch (Exception e) {
                Logger.error('Failed to create follow-up tasks', e);
                Logger.saveLog();
            }
        } else {
            throw new SecurityException('User does not have create access to Task object');
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
                needsUpdate = (invoice.Stripe_Customer__c != null);
            } else {
                // UPDATE: Update if status changed
                Stripe_Invoice__c oldInvoice = oldMap.get(invoice.Id);
                if (invoice.Stripe_Customer__c != null && invoice.Status__c != oldInvoice.Status__c) {
                    needsUpdate = true;
                }
            }

            if (needsUpdate) {
                customerIds.add(invoice.Stripe_Customer__c);
            }
        }

        if (customerIds.isEmpty()) {
            return;
        }

        // Calculate health scores for each customer
        Map<Id, Decimal> customerHealthScores = new Map<Id, Decimal>();

        for (Id customerId : customerIds) {
            List<Stripe_Invoice__c> customerInvoices = [
                SELECT Id, Status__c, Dunning_Status__c, Due_Date__c, Amount__c
                FROM Stripe_Invoice__c
                WHERE Stripe_Customer__c = :customerId
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];

            if (customerInvoices.isEmpty()) {
                continue;
            }

            Decimal totalInvoices = customerInvoices.size();
            Decimal paidInvoices = 0;
            Decimal failedInvoices = 0;
            Decimal dunningExhausted = 0;

            for (Stripe_Invoice__c inv : customerInvoices) {
                if (inv.Status__c == 'paid') {
                    paidInvoices++;
                } else if (inv.Status__c == 'uncollectible' || inv.Status__c == 'void') {
                    failedInvoices++;
                }
                if (inv.Dunning_Status__c == 'exhausted') {
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
        List<Stripe_Customer__c> customersToUpdate = new List<Stripe_Customer__c>();

        if (Schema.SObjectType.Stripe_Customer__c.isUpdateable()) {
            for (Id customerId : customerHealthScores.keySet()) {
                Stripe_Customer__c customer = new Stripe_Customer__c(Id = customerId);

                if (Schema.SObjectType.Stripe_Customer__c.fields.Health_Score__c.isUpdateable()) {
                    customer.Health_Score__c = customerHealthScores.get(customerId);
                }

                customersToUpdate.add(customer);
            }

            try {
                if (!customersToUpdate.isEmpty()) {
                    update as user customersToUpdate;
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
                needsAssessment = (invoice.Stripe_Customer__c != null &&
                    (invoice.Status__c == 'uncollectible' || invoice.Dunning_Status__c != 'none'));
            } else {
                // UPDATE: Assess if status or dunning status changed
                Stripe_Invoice__c oldInvoice = oldMap.get(invoice.Id);
                if (invoice.Stripe_Customer__c != null &&
                    (invoice.Status__c != oldInvoice.Status__c ||
                     invoice.Dunning_Status__c != oldInvoice.Dunning_Status__c)) {
                    needsAssessment = true;
                }
            }

            if (needsAssessment) {
                customerIds.add(invoice.Stripe_Customer__c);
            }
        }

        if (customerIds.isEmpty()) {
            return;
        }

        // Assess churn risk for each customer
        Map<Id, String> customerChurnRisk = new Map<Id, String>();

        for (Id customerId : customerIds) {
            // Get recent invoice history (last 6 months)
            List<Stripe_Invoice__c> recentInvoices = [
                SELECT Id, Status__c, Dunning_Status__c, CreatedDate
                FROM Stripe_Invoice__c
                WHERE Stripe_Customer__c = :customerId
                    AND CreatedDate = LAST_N_MONTHS:6
                ORDER BY CreatedDate DESC
            ];

            if (recentInvoices.isEmpty()) {
                customerChurnRisk.put(customerId, 'Low');
                continue;
            }

            Integer totalInvoices = recentInvoices.size();
            Integer failedCount = 0;
            Integer exhaustedCount = 0;
            Integer consecutiveFailures = 0;

            for (Stripe_Invoice__c inv : recentInvoices) {
                if (inv.Status__c == 'uncollectible') {
                    failedCount++;
                    consecutiveFailures++;
                } else if (inv.Status__c == 'paid') {
                    consecutiveFailures = 0;
                }
                if (inv.Dunning_Status__c == 'exhausted') {
                    exhaustedCount++;
                }
            }

            // Determine churn risk level
            String riskLevel = 'Low';

            if (exhaustedCount >= 2 || consecutiveFailures >= 3) {
                riskLevel = 'Critical';
            } else if (exhaustedCount >= 1 || consecutiveFailures >= 2 || failedCount >= 3) {
                riskLevel = 'High';
            } else if (failedCount >= 2) {
                riskLevel = 'Medium';
            }

            customerChurnRisk.put(customerId, riskLevel);
        }

        // Update customer records with churn risk
        List<Stripe_Customer__c> customersToUpdate = new List<Stripe_Customer__c>();

        if (Schema.SObjectType.Stripe_Customer__c.isUpdateable()) {
            for (Id customerId : customerChurnRisk.keySet()) {
                Stripe_Customer__c customer = new Stripe_Customer__c(Id = customerId);

                if (Schema.SObjectType.Stripe_Customer__c.fields.Churn_Risk__c.isUpdateable()) {
                    customer.Churn_Risk__c = customerChurnRisk.get(customerId);
                }

                customersToUpdate.add(customer);
            }

            try {
                if (!customersToUpdate.isEmpty()) {
                    update as user customersToUpdate;
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
            if (invoice.Status__c == 'uncollectible' &&
                oldInvoice.Status__c != 'uncollectible' &&
                invoice.Dunning_Status__c == 'trying') {

                // Note: Actual dunning progression is handled by Stripe webhooks
                // This method logs escalations and can trigger additional workflows
                Logger.info('Dunning escalated to exhausted for invoice: ' + invoice.Name);
            }
        }

        Logger.saveLog();
    }
}
