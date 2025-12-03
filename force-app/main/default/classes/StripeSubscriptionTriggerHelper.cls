/**
 * @description Helper class for Stripe_Subscription__c trigger operations. Manages subscription lifecycle events including
 *              initiating Stripe API callouts for subscription and checkout session creation. Enforces object-level
 *              security throughout.
 */
public with sharing class StripeSubscriptionTriggerHelper {
    // Status constants for subscription sync
    private static final String STATUS_SEND_TO_STRIPE = 'Send to Stripe';
    private static final String STATUS_SYNCED = 'Completed';
    private static final String STATUS_FAILED = 'Failed';
    private static final String STATUS_ACTIVE = 'active';
    private static final Decimal ZERO_VALUE = 0;
    private static final Integer AVERAGE_DAYS_IN_MONTH = 30;
    /**
     * @description Processes subscription records marked for sync to Stripe. Identifies subscriptions with 'Send to Stripe'
     *              status that have all required data (price, customer, payment method) and initiates asynchronous callouts
     *              to create the subscription in Stripe. Enforces object-level read permissions.
     * @param newList List of updated Stripe_Subscription__c records
     * @param oldMap Map of Stripe_Subscription__c records before the update (Id to old record)
     */
    public static void processStripeSubscriptionAfterUpdate(List<Stripe_Subscription__c> newList, Map<Id, Stripe_Subscription__c> oldMap){
        // Validate input parameters
        if (newList == null || newList.isEmpty()) {
            return;
        }

        List<Stripe_Subscription__c> subscriptionsForProcess = new List<Stripe_Subscription__c>();
        List<Stripe_Subscription__c> subscriptionsForUpdate = new List<Stripe_Subscription__c>();
        Boolean isInsert = (oldMap == null || oldMap.isEmpty());

        if (!Schema.SObjectType.Stripe_Subscription__c.isAccessible()) {
            throw new SecurityException('User does not have read access to Stripe_Subscription__c object');
        }

        if (!Schema.SObjectType.Stripe_Subscription__c.isUpdateable()) {
            throw new SecurityException('User does not have update access to Stripe_Subscription__c object');
        }

        Set<Id> pricingPlanIds = new Set<Id>();
        for (Stripe_Subscription__c subscription : newList) {
            if (subscription.Pricing_Plan__c != null) {
                pricingPlanIds.add(subscription.Pricing_Plan__c);
            }
        }

        // Query Pricing Plans to get their Stripe Price IDs
        Map<Id, Pricing_Plan__c> pricingPlanMap = new Map<Id, Pricing_Plan__c>();
        if (!pricingPlanIds.isEmpty()) {
            if (!Schema.SObjectType.Pricing_Plan__c.isAccessible()) {
                throw new SecurityException('User does not have read access to Pricing_Plan__c object');
            }
            pricingPlanMap = new Map<Id, Pricing_Plan__c>(
                [SELECT Id, Stripe_Price_ID__c
                 FROM Pricing_Plan__c
                 WHERE Id IN :pricingPlanIds]
            );
        }

        for (Stripe_Subscription__c subscription : newList) {
            Stripe_Subscription__c oldSubscription = isInsert ? null : oldMap.get(subscription.Id);
            Pricing_Plan__c pricingPlan = pricingPlanMap.get(subscription.Pricing_Plan__c);

            // Changed logic: Instead of creating subscription directly, create checkout session which will create the subscription
            Boolean statusChanged = isInsert ? true : (oldSubscription != null && oldSubscription.Sync_Status__c != subscription.Sync_Status__c);
            if (statusChanged
                && subscription.Sync_Status__c == STATUS_SEND_TO_STRIPE
                && String.isBlank(subscription.Stripe_Subscription_ID__c)
                && pricingPlan != null
                && !String.isBlank(subscription.StripeCustomerId__c)) {
                // Note: Stripe_Price_ID__c and CustomerDefaultPayment__c are not required here
                // - Stripe_Price_ID__c is validated in StripeCalloutQueueable
                // - CustomerDefaultPayment__c is collected during the checkout session
                subscriptionsForProcess.add(subscription);
            }
        }

        if (!subscriptionsForProcess.isEmpty()) {
            try {
                // Enqueue a single batch job for all subscriptions instead of one per record
                StripeCalloutQueueable callout = new StripeCalloutQueueable(subscriptionsForProcess, pricingPlanMap);
                if (!Test.isRunningTest()) {
                    System.enqueueJob(callout);
                    Logger.info('Enqueued batch job for ' + subscriptionsForProcess.size() + ' subscription checkout sessions')
                        .addTag('StripeSubscriptionTriggerHelper')
                        .addTag('Batch-Processing');
                    Logger.saveLog();
                }
            } catch (Exception ex) {
                Logger.error('Failed to enqueue batch checkout session callout', ex);
                Logger.saveLog();
                // Mark all subscriptions as failed
                for (Stripe_Subscription__c subscriptionRec : subscriptionsForProcess) {
                    subscriptionRec.Sync_Status__c = STATUS_FAILED;
                    subscriptionsForUpdate.add(subscriptionRec);
                }
            }

            // Update subscriptions that failed to enqueue
            if (!subscriptionsForUpdate.isEmpty()) {
                try {
                    update as user subscriptionsForUpdate;
                } catch (DmlException dmlEx) {
                    Logger.error('Failed to update subscription status after callout failure', dmlEx);
                    Logger.saveLog();
                }
            }
        }
    }
    /**
     * @description Calculates and updates the Monthly Recurring Revenue (MRR) for Contacts
     *              based on their active Stripe subscriptions. This method is triggered when
     *              subscription status changes to/from Active or when subscription amount changes
     *              on an Active subscription.
     *
     * @param newList List of Stripe_Subscription__c records with new values (after update)
     * @param oldMap Map of Stripe_Subscription__c records with old values (before update), keyed by Id
     *
     * */
    public static void calculateMRR_OfStripeCustomer(List<Stripe_Subscription__c> newList, Map<Id, Stripe_Subscription__c> oldMap){
        Set<Id> customerIds = new Set<Id>();
        Map<Id, Decimal> customerIdsToMRR = new Map<Id, Decimal>();
        Map<Id, Contact> customerIdsToCustomers = new Map<Id, Contact>();
        // Validate input parameters
        if (newList == null || newList.isEmpty()) {
            return;
        }
        Boolean isInsert = (oldMap == null || oldMap.isEmpty());
        try {
            for (Stripe_Subscription__c subscription : newList) {
                //Check whether Subscription related to Customer
                if (subscription.Contact__c != null) {
                    // For inserts, check if subscription is active
                    if (isInsert) {
                        if (subscription.Status__c == STATUS_ACTIVE && subscription.Amount__c != null) {
                            customerIds.add(subscription.Contact__c);
                        }
                    } else {
                        Stripe_Subscription__c oldSubscription = oldMap.get(subscription.Id);
                        //Check whether Status field was updated to or from Active value
                        if ((oldSubscription.Status__c != subscription.Status__c
                            && subscription.Amount__c != null
                            && (oldSubscription.Status__c == STATUS_ACTIVE
                                || subscription.Status__c == STATUS_ACTIVE))
                            //Check whether Amount__c field was updated on Active Subscription
                            || (oldSubscription.Amount__c != subscription.Amount__c
                                && subscription.Status__c == STATUS_ACTIVE)) {
                            customerIds.add(subscription.Contact__c);
                        }
                    }
                }
            }
            //Exit early if no records meet criteria
            if (customerIds.isEmpty()) {
                return;
            }
            //Loop through all subscriptions and calculate MRR
            for (Stripe_Subscription__c subscription : [SELECT Amount__c, Current_Period_Start__c, Current_Period_End__c, Contact__c,
                                                                Pricing_Plan__r.Recurrency_Type__c
                                                        FROM Stripe_Subscription__c
                                                        WHERE Status__c =: STATUS_ACTIVE
                                                        AND Contact__c IN: customerIds
                                                        AND Amount__c != null]) {
                Decimal monthlyRevenue = 0;

                // Get the recurrency type from the related Pricing Plan
                String recurrencyType = subscription.Pricing_Plan__r != null ?
                                        subscription.Pricing_Plan__r.Recurrency_Type__c : null;

                // Calculate MRR based on the billing interval
                if (String.isNotBlank(recurrencyType)) {
                    // Convert subscription amount to monthly based on billing interval
                    if (recurrencyType.toLowerCase() == 'month') {
                        // Already monthly, use amount as-is
                        monthlyRevenue = subscription.Amount__c;
                    } else if (recurrencyType.toLowerCase() == 'year') {
                        // Annual subscription, divide by 12
                        monthlyRevenue = subscription.Amount__c / 12;
                    } else if (recurrencyType.toLowerCase() == 'week') {
                        // Weekly subscription, multiply by 4.33 (average weeks per month)
                        monthlyRevenue = subscription.Amount__c * 4.33;
                    } else if (recurrencyType.toLowerCase() == 'day') {
                        // Daily subscription, multiply by 30
                        monthlyRevenue = subscription.Amount__c * AVERAGE_DAYS_IN_MONTH;
                    } else {
                        // Unknown interval, fall back to period-based calculation if dates are valid
                        if (subscription.Current_Period_Start__c != null &&
                            subscription.Current_Period_End__c != null) {
                            Integer subscriptionDays = Date.valueOf(subscription.Current_Period_Start__c)
                                .daysBetween(Date.valueOf(subscription.Current_Period_End__c));
                            if (subscriptionDays > 0) {
                                Decimal amountPerDay = subscription.Amount__c / subscriptionDays;
                                monthlyRevenue = amountPerDay * AVERAGE_DAYS_IN_MONTH;
                            } else {
                                // If period dates are same/invalid, assume it's monthly
                                monthlyRevenue = subscription.Amount__c;
                            }
                        } else {
                            // No valid dates, assume monthly
                            monthlyRevenue = subscription.Amount__c;
                        }
                    }
                } else if (subscription.Current_Period_Start__c != null &&
                          subscription.Current_Period_End__c != null) {
                    // No recurrency type, try to calculate from period dates
                    Integer subscriptionDays = Date.valueOf(subscription.Current_Period_Start__c)
                        .daysBetween(Date.valueOf(subscription.Current_Period_End__c));
                    if (subscriptionDays > 0) {
                        Decimal amountPerDay = subscription.Amount__c / subscriptionDays;
                        monthlyRevenue = amountPerDay * AVERAGE_DAYS_IN_MONTH;
                    } else {
                        // Period dates are same or invalid, assume monthly amount
                        monthlyRevenue = subscription.Amount__c;
                    }
                } else {
                    // No recurrency type and no valid dates, assume monthly
                    monthlyRevenue = subscription.Amount__c;
                }

                if (!customerIdsToMRR.containsKey(subscription.Contact__c)) {
                    customerIdsToMRR.put(subscription.Contact__c, 0);
                }
                //Aggregate monthly revenues across all Subscriptions
                customerIdsToMRR.put(subscription.Contact__c,
                                    customerIdsToMRR.get(subscription.Contact__c) + monthlyRevenue);
            }
            //Collect records for update in Map to avoid duplicates
            for (Id customerId : customerIds) {
                if (customerIdsToMRR.containsKey(customerId)) {
                    customerIdsToCustomers.put(customerId, new Contact(Id = customerId,
                                                                        MRR__c = customerIdsToMRR.get(customerId)));
                } else {
                    //Assign zero value if no active Subscription is found
                    customerIdsToCustomers.put(customerId, new Contact(Id = customerId,
                                                                        MRR__c = ZERO_VALUE));
                }
            }
            if (!customerIdsToCustomers.isEmpty()) {
                try {
                    update customerIdsToCustomers.values();
                } catch (DmlException dmlEx) {
                    Logger.error('Failed to update Contact records: ', dmlEx)
                    .setMessage('Failed to update MRR field on Contacts. Stack trace: ' + dmlEx.getStackTraceString())
                    .addTag('StripeSubscriptionTriggerHelper')
                    .addTag('MRR-Calculation-Error');
                    Logger.saveLog();
                }
            }
        } catch (Exception ex) {
            Logger.error('Error in calculateMRR_OfStripeCustomer: ' + ex.getMessage(), ex)
            .setMessage('Failed to calculate MRR. Stack trace: ' + ex.getStackTraceString())
            .addTag('StripeSubscriptionTriggerHelper')
            .addTag('MRR-Calculation-Error');
            Logger.saveLog();
        }
    }
}