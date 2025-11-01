/**
 * Batch job to recalculate revenue rollups on Customer and Subscription records
 * Can be scheduled to run monthly for comprehensive revenue reconciliation
 *
 * Schedule example:
 * RevenueRollupBatch batch = new RevenueRollupBatch();
 * String sch = '0 0 4 1 * ?'; // Run on 1st of every month at 4 AM
 * System.schedule('Monthly Revenue Rollup Reconciliation', sch, batch);
 */
public with sharing class RevenueRollupBatch implements Database.Batchable<SObject>, Schedulable {

    private String rollupType; // 'customer' or 'subscription'

    /**
     * Constructor
     * @param rollupType Type of rollup to perform: 'customer' or 'subscription' (default: 'customer')
     */
    public RevenueRollupBatch() {
        this('customer');
    }

    public RevenueRollupBatch(String rollupType) {
        this.rollupType = rollupType;
    }

    /**
     * Start method - query based on rollup type
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (rollupType == 'subscription') {
            return Database.getQueryLocator([
                SELECT Id, Total_Invoiced__c,
                       (SELECT Id, Amount__c
                        FROM Stripe_Invoices__r
                        WHERE Amount__c != null)
                FROM Stripe_Subscription__c
            ]);
        } else {
            // Default to customer rollup
            return Database.getQueryLocator([
                SELECT Id, Total_Revenue__c, MRR__c,
                       (SELECT Id, Amount__c
                        FROM Stripe_Invoices__r
                        WHERE Status__c = 'paid' AND Amount__c != null)
                FROM Stripe_Customer__c
            ]);
        }
    }

    /**
     * Execute method - recalculate rollups for each batch
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        try {
            if (rollupType == 'subscription') {
                processSubscriptionRollups((List<Stripe_Subscription__c>)scope);
            } else {
                processCustomerRollups((List<Stripe_Customer__c>)scope);
            }
        } catch (Exception e) {
            Logger.error('Error in RevenueRollupBatch (' + rollupType + ')', e);
            Logger.saveLog();
        }
    }

    /**
     * Process customer revenue rollups
     */
    private void processCustomerRollups(List<Stripe_Customer__c> customers) {
        List<Stripe_Customer__c> customersToUpdate = new List<Stripe_Customer__c>();

        // Get active subscription amounts for MRR calculation
        Set<Id> customerIds = new Set<Id>();
        for (Stripe_Customer__c customer : customers) {
            customerIds.add(customer.Id);
        }

        Map<Id, Decimal> customerMRR = new Map<Id, Decimal>();
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

        for (Stripe_Customer__c customer : customers) {
            Decimal totalRevenue = 0;
            for (Stripe_Invoice__c invoice : customer.Stripe_Invoices__r) {
                if (invoice.Amount__c != null) {
                    totalRevenue += invoice.Amount__c;
                }
            }

            if (Schema.SObjectType.Stripe_Customer__c.isUpdateable()) {
                Stripe_Customer__c customerToUpdate = new Stripe_Customer__c(Id = customer.Id);

                if (Schema.SObjectType.Stripe_Customer__c.fields.Total_Revenue__c.isUpdateable()) {
                    customerToUpdate.Total_Revenue__c = totalRevenue;
                }

                if (Schema.SObjectType.Stripe_Customer__c.fields.MRR__c.isUpdateable()) {
                    customerToUpdate.MRR__c = customerMRR.get(customer.Id);
                }

                customersToUpdate.add(customerToUpdate);
            }
        }

        if (!customersToUpdate.isEmpty()) {
            update as user customersToUpdate;
            Logger.info('Updated revenue rollups for ' + customersToUpdate.size() + ' customers');
            Logger.saveLog();
        }
    }

    /**
     * Process subscription invoice rollups
     */
    private void processSubscriptionRollups(List<Stripe_Subscription__c> subscriptions) {
        List<Stripe_Subscription__c> subscriptionsToUpdate = new List<Stripe_Subscription__c>();

        for (Stripe_Subscription__c subscription : subscriptions) {
            Decimal totalInvoiced = 0;
            for (Stripe_Invoice__c invoice : subscription.Stripe_Invoices__r) {
                if (invoice.Amount__c != null) {
                    totalInvoiced += invoice.Amount__c;
                }
            }

            if (Schema.SObjectType.Stripe_Subscription__c.isUpdateable() &&
                Schema.SObjectType.Stripe_Subscription__c.fields.Total_Invoiced__c.isUpdateable()) {

                Stripe_Subscription__c subscriptionToUpdate = new Stripe_Subscription__c(
                    Id = subscription.Id,
                    Total_Invoiced__c = totalInvoiced
                );
                subscriptionsToUpdate.add(subscriptionToUpdate);
            }
        }

        if (!subscriptionsToUpdate.isEmpty()) {
            update as user subscriptionsToUpdate;
            Logger.info('Updated revenue rollups for ' + subscriptionsToUpdate.size() + ' subscriptions');
            Logger.saveLog();
        }
    }

    /**
     * Finish method - cleanup and summary
     */
    public void finish(Database.BatchableContext bc) {
        Logger.info('RevenueRollupBatch (' + rollupType + ') completed successfully');
        Logger.saveLog();
    }

    /**
     * Schedulable execute method
     */
    public void execute(SchedulableContext sc) {
        Database.executeBatch(this, 200);
    }
}
