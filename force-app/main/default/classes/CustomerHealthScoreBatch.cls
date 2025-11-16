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
     * Start method - query for all contacts with Stripe customer data
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Health_Score__c, Stripe_Customer_ID__c
            FROM Contact
            WHERE Stripe_Customer_ID__c != null
        ]);
    }

    /**
     * Execute method - recalculate health scores for each batch
     */
    public void execute(Database.BatchableContext bc, List<Contact> scope) {
        // Get Stripe Customer IDs from contacts in this batch
        Set<String> stripeCustomerIds = new Set<String>();
        for (Contact c : scope) {
            if (String.isNotBlank(c.Stripe_Customer_ID__c)) {
                stripeCustomerIds.add(c.Stripe_Customer_ID__c);
            }
        }

        // Query invoices for these customers
        Map<String, List<Stripe_Invoice__c>> invoicesByStripeId = new Map<String, List<Stripe_Invoice__c>>();
        for (Stripe_Invoice__c inv : [
            SELECT Id, Status__c, Dunning_Status__c, Amount__c, CreatedDate, Contact__r.Stripe_Customer_ID__c
            FROM Stripe_Invoice__c
            WHERE Contact__r.Stripe_Customer_ID__c IN :stripeCustomerIds
            ORDER BY CreatedDate DESC
        ]) {
            String stripeId = inv.Contact__r.Stripe_Customer_ID__c;
            if (!invoicesByStripeId.containsKey(stripeId)) {
                invoicesByStripeId.put(stripeId, new List<Stripe_Invoice__c>());
            }
            invoicesByStripeId.get(stripeId).add(inv);
        }

        List<Contact> contactsToUpdate = new List<Contact>();

        try {
            for (Contact contact : scope) {
                List<Stripe_Invoice__c> invoices = invoicesByStripeId.get(contact.Stripe_Customer_ID__c);

                if (invoices == null || invoices.isEmpty()) {
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

                if (Schema.SObjectType.Contact.isUpdateable() &&
                    Schema.SObjectType.Contact.fields.Health_Score__c.isUpdateable()) {

                    Contact contactToUpdate = new Contact(
                        Id = contact.Id,
                        Health_Score__c = healthScore
                    );
                    contactsToUpdate.add(contactToUpdate);
                }
            }

            if (!contactsToUpdate.isEmpty()) {
                update as user contactsToUpdate;
                Logger.info('Updated health scores for ' + contactsToUpdate.size() + ' contacts');
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
