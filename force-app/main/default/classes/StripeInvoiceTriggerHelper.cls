public without sharing class StripeInvoiceTriggerHelper {
    private static final String PAID_STATUS = 'paid';
    private static final Decimal ZERO_VALUE = 0;
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
            Set<Id> stripeCustomerIds = new Set<Id>();
            Map<Id, Contact> customerIdsToCustomers = new Map<Id, Contact>();
            try {
                //Early exit if invoiceList is null
                if (invoiceList == null || invoiceList.isEmpty()) {
                    Logger.warn('calculateTotalRevenueOfStripeCustomer called with null or empty parameters')
                    .addTag('calculateTotalRevenueOfStripeCustomer');
                    Logger.saveLog();
                    return;
                }
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
                //Set Total Revenue as zero if no Invoice is found, as all of them are deleted
                for (Id customerId : stripeCustomerIds) {
                    if (!customerIdsToCustomers.containsKey(customerId)) {
                        customerIdsToCustomers.put(customerId,
                                                    new Contact(
                                                        Id = customerId,
                                                        Total_Revenue__c = ZERO_VALUE
                                                        ));}
                }
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
}