/**
 * @description Helper class for Stripe_Subscription__c trigger operations. Manages subscription lifecycle events including
 *              initiating Stripe API callouts for subscription and checkout session creation, and creating associated
 *              Pricing Plan records based on subscription selections. Enforces object-level security throughout.
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
     * @description Processes successfully synced subscriptions to create Stripe Checkout Sessions. Identifies subscriptions
     *              with 'Completed' status that have all required data and initiates asynchronous callouts to create a checkout
     *              session for payment collection. Enforces object-level read permissions.
     * @param newList List of updated Stripe_Subscription__c records
     * @param oldMap Map of Stripe_Subscription__c records before the update (Id to old record)
     */
    public static void processStripeSubscriptionToCreateSession(List<Stripe_Subscription__c> newList, Map<Id, Stripe_Subscription__c> oldMap){
        // Validate input parameters
        if (newList == null || newList.isEmpty() || oldMap == null) {
            return;
        }

        List<Stripe_Subscription__c> subscriptionsForProcess = new List<Stripe_Subscription__c>();
        List<Stripe_Subscription__c> subscriptionsForUpdate = new List<Stripe_Subscription__c>();

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
            Stripe_Subscription__c oldSubscription = oldMap.get(subscription.Id);
            Pricing_Plan__c pricingPlan = pricingPlanMap.get(subscription.Pricing_Plan__c);

            if (oldSubscription != null
                && oldSubscription.Sync_Status__c != subscription.Sync_Status__c
                && subscription.Sync_Status__c == STATUS_SYNCED
                && !String.isBlank(subscription.Stripe_Subscription_ID__c)
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
                    Logger.info('Enqueued batch job for ' + subscriptionsForProcess.size() + ' subscriptions to create checkout sessions')
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
                    Logger.error('Failed to update subscription status after checkout session callout failure', dmlEx);
                    Logger.saveLog();
                }
            }
        }
    }
}