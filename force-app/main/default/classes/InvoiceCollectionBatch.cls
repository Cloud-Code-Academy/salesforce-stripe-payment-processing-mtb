/**
 * Batch job to process overdue invoices and identify collection issues
 * Can be scheduled to run daily to monitor invoice status
 *
 * Schedule example:
 * InvoiceCollectionBatch batch = new InvoiceCollectionBatch();
 * String sch = '0 0 2 * * ?'; // Run every day at 2 AM
 * System.schedule('Daily Invoice Collection Check', sch, batch);
 */
public with sharing class InvoiceCollectionBatch implements Database.Batchable<SObject>, Schedulable {

    private Integer daysOverdue;

    /**
     * Constructor
     * @param daysOverdue Number of days past due date to consider for processing (default: 7)
     */
    public InvoiceCollectionBatch() {
        this(7);
    }

    public InvoiceCollectionBatch(Integer daysOverdue) {
        this.daysOverdue = daysOverdue;
    }

    /**
     * Start method - query for overdue invoices
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date overdueDate = Date.today().addDays(-daysOverdue);

        return Database.getQueryLocator([
            SELECT Id, Name, Stripe_Invoice_ID__c, Amount__c, Status__c,
                   Dunning_Status__c, Due_Date__c, Stripe_Customer__c,
                   Stripe_Subscription__c
            FROM Stripe_Invoice__c
            WHERE Due_Date__c < :overdueDate
                AND Status__c IN ('open', 'uncollectible')
            ORDER BY Due_Date__c ASC
        ]);
    }

    /**
     * Execute method - process each batch of overdue invoices
     */
    public void execute(Database.BatchableContext bc, List<Stripe_Invoice__c> scope) {
        try {
            // Group invoices by customer for analysis
            Map<Id, List<Stripe_Invoice__c>> invoicesByCustomer = new Map<Id, List<Stripe_Invoice__c>>();

            for (Stripe_Invoice__c invoice : scope) {
                if (invoice.Stripe_Customer__c != null) {
                    if (!invoicesByCustomer.containsKey(invoice.Stripe_Customer__c)) {
                        invoicesByCustomer.put(invoice.Stripe_Customer__c, new List<Stripe_Invoice__c>());
                    }
                    invoicesByCustomer.get(invoice.Stripe_Customer__c).add(invoice);
                }
            }

            // Log collection issues
            for (Id customerId : invoicesByCustomer.keySet()) {
                List<Stripe_Invoice__c> customerInvoices = invoicesByCustomer.get(customerId);
                Decimal totalOverdue = 0;
                Integer invoiceCount = customerInvoices.size();

                for (Stripe_Invoice__c inv : customerInvoices) {
                    if (inv.Amount__c != null) {
                        totalOverdue += inv.Amount__c;
                    }
                }

                Logger.info(
                    'Customer ' + customerId + ' has ' + invoiceCount +
                    ' overdue invoice(s) totaling ' + totalOverdue
                );
            }

            Logger.saveLog();

        } catch (Exception e) {
            Logger.error('Error in InvoiceCollectionBatch', e);
            Logger.saveLog();
        }
    }

    /**
     * Finish method - cleanup and summary
     */
    public void finish(Database.BatchableContext bc) {
        Logger.info('InvoiceCollectionBatch completed successfully');
        Logger.saveLog();
    }

    /**
     * Schedulable execute method
     */
    public void execute(SchedulableContext sc) {
        Database.executeBatch(this, 200);
    }
}
