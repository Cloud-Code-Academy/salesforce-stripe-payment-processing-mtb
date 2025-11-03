/**
 * Batch job to recalculate customer health scores based on invoice history
 * Can be scheduled to run weekly for comprehensive health score updates
 *
 * Schedule example:
 * CustomerHealthScoreBatch batch = new CustomerHealthScoreBatch();
 * String sch = '0 0 3 ? * SUN'; // Run every Sunday at 3 AM
 * System.schedule('Weekly Customer Health Score Update', sch, batch);
 */
public with sharing class CustomerHealthScoreBatch implements Database.Batchable<SObject>, Schedulable {

    /**
     * Start method - query for all customers with invoices
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Customer_Name__c, Health_Score__c,
                   (SELECT Id, Status__c, Dunning_Status__c, Amount__c, CreatedDate
                    FROM Stripe_Invoices__r
                    ORDER BY CreatedDate DESC
                    LIMIT 50)
            FROM Stripe_Customer__c
            WHERE Id IN (SELECT Stripe_Customer__c FROM Stripe_Invoice__c)
        ]);
    }

    /**
     * Execute method - recalculate health scores for each batch
     */
    public void execute(Database.BatchableContext bc, List<Stripe_Customer__c> scope) {
        List<Stripe_Customer__c> customersToUpdate = new List<Stripe_Customer__c>();

        try {
            for (Stripe_Customer__c customer : scope) {
                List<Stripe_Invoice__c> invoices = customer.Stripe_Invoices__r;

                if (invoices.isEmpty()) {
                    continue;
                }

                Decimal totalInvoices = invoices.size();
                Decimal paidInvoices = 0;
                Decimal failedInvoices = 0;
                Decimal dunningExhausted = 0;

                for (Stripe_Invoice__c inv : invoices) {
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
                Decimal paymentSuccessRate = (paidInvoices / totalInvoices) * 100;
                Decimal failurePenalty = Math.min((failedInvoices / totalInvoices) * 100, 40);
                Decimal dunningPenalty = Math.min((dunningExhausted / totalInvoices) * 150, 60);
                Decimal healthScore = Math.max(0, paymentSuccessRate - failurePenalty - dunningPenalty);

                if (Schema.SObjectType.Stripe_Customer__c.isUpdateable() &&
                    Schema.SObjectType.Stripe_Customer__c.fields.Health_Score__c.isUpdateable()) {

                    Stripe_Customer__c customerToUpdate = new Stripe_Customer__c(
                        Id = customer.Id,
                        Health_Score__c = healthScore
                    );
                    customersToUpdate.add(customerToUpdate);
                }
            }

            if (!customersToUpdate.isEmpty()) {
                update as user customersToUpdate;
                Logger.info('Updated health scores for ' + customersToUpdate.size() + ' customers');
            }

            Logger.saveLog();

        } catch (Exception e) {
            Logger.error('Error in CustomerHealthScoreBatch', e);
            Logger.saveLog();
        }
    }

    /**
     * Finish method - cleanup and summary
     */
    public void finish(Database.BatchableContext bc) {
        Logger.info('CustomerHealthScoreBatch completed successfully');
        Logger.saveLog();
    }

    /**
     * Schedulable execute method
     */
    public void execute(SchedulableContext sc) {
        Database.executeBatch(this, 200);
    }
}
