/**
 * @description Helper class for Stripe_Subscription__c trigger operations. Manages subscription lifecycle events including
 *              initiating Stripe API callouts for subscription and checkout session creation, and creating associated
 *              Pricing Plan records based on subscription selections. Enforces object-level security throughout.
 */
public with sharing class StripeSubscriptionTriggerHelper {
    // Status constants for subscription sync
    private static final String STATUS_SEND_TO_STRIPE = 'Send to Stripe';
    private static final String STATUS_SYNCED = 'Synced';
    private static final String STATUS_FAILED = 'Failed';
    /**
     * @description Processes subscription records marked for sync to Stripe. Identifies subscriptions with 'Send to Stripe'
     *              status that have all required data (price, customer, payment method) and initiates asynchronous callouts
     *              to create the subscription in Stripe. Enforces object-level read permissions.
     * @param newList List of updated Stripe_Subscription__c records
     * @param oldMap Map of Stripe_Subscription__c records before the update (Id to old record)
     */
    public static void processStripeSubscriptionAfterUpdate(List<Stripe_Subscription__c> newList, Map<Id, Stripe_Subscription__c> oldMap){
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

        for (Stripe_Subscription__c subscription : newList) {
            Stripe_Subscription__c oldSubscription = oldMap.get(subscription.Id);
            if (oldSubscription != null
                && oldSubscription.Sync_Status__c != subscription.Sync_Status__c
                && subscription.Sync_Status__c == STATUS_SEND_TO_STRIPE
                && String.isBlank(subscription.Stripe_Subscription_ID__c)
                && !String.isBlank(subscription.Stripe_Price_ID__c)
                && !String.isBlank(subscription.StripeCustomerId__c)
                && !String.isBlank(subscription.CustomerDefaultPayment__c)) {
                subscriptionsForProcess.add(subscription);
            }
        }

        if (!subscriptionsForProcess.isEmpty()) {
            for (Stripe_Subscription__c subscriptionRec : subscriptionsForProcess) {
                try {
                    StripeCalloutQueueable callout = new StripeCalloutQueueable(
                        subscriptionRec.StripeCustomerId__c,
                        subscriptionRec.Id,
                        subscriptionRec.Stripe_Price_ID__c,
                        subscriptionRec.CustomerDefaultPayment__c
                    );
                    if (!Test.isRunningTest()) {
                        System.enqueueJob(callout);
                    }
                } catch (Exception ex) {
                    Logger.error('Failed to enqueue subscription callout for subscription: ' + subscriptionRec.Id, ex);
                    Logger.saveLog();
                    // Track failed subscriptions for status update
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
     *              with 'Synced' status that have all required data and initiates asynchronous callouts to create a checkout
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

        for (Stripe_Subscription__c subscription : newList) {
            Stripe_Subscription__c oldSubscription = oldMap.get(subscription.Id);
            if (oldSubscription != null
                && oldSubscription.Sync_Status__c != subscription.Sync_Status__c
                && subscription.Sync_Status__c == STATUS_SYNCED
                && !String.isBlank(subscription.Stripe_Subscription_ID__c)
                && !String.isBlank(subscription.Stripe_Price_ID__c)
                && !String.isBlank(subscription.StripeCustomerId__c)
                && !String.isBlank(subscription.CustomerDefaultPayment__c)) {
                subscriptionsForProcess.add(subscription);
            }
        }

        if (!subscriptionsForProcess.isEmpty()) {
            for (Stripe_Subscription__c subscriptionRec : subscriptionsForProcess) {
                try {
                    StripeCalloutQueueable callout = new StripeCalloutQueueable(
                        subscriptionRec.StripeCustomerId__c,
                        subscriptionRec.Stripe_Price_ID__c,
                        subscriptionRec.Id
                    );
                    if (!Test.isRunningTest()) {
                        System.enqueueJob(callout);
                    }
                } catch (Exception ex) {
                    Logger.error('Failed to enqueue checkout session callout for subscription: ' + subscriptionRec.Id, ex);
                    Logger.saveLog();
                    // Track failed subscriptions for status update
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
    /**
     * @description Creates Pricing Plan records when a pricing plan is selected on a subscription. Retrieves plan details
     *              from Stripe_Price__mdt custom metadata and creates corresponding Pricing_Plan__c records linked to the
     *              subscription. Enforces object-level permissions for both read and create operations.
     * @param newList List of updated Stripe_Subscription__c records
     * @param oldMap Map of Stripe_Subscription__c records before the update (Id to old record)
     */
    public static void createPricingPlansUponSelection(List<Stripe_Subscription__c> newList, Map<Id, Stripe_Subscription__c> oldMap){
        // Validate input parameters
        if (newList == null || newList.isEmpty() || oldMap == null) {
            return;
        }

        List<Pricing_Plan__c> pricingPlansForInsert = new List<Pricing_Plan__c>();

        if (!Schema.SObjectType.Stripe_Subscription__c.isAccessible()) {
            throw new SecurityException('User does not have read access to Stripe_Subscription__c object');
        }

        if (!Schema.SObjectType.Pricing_Plan__c.isCreateable()) {
            throw new SecurityException('User does not have create access to Pricing_Plan__c object');
        }

        for (Stripe_Subscription__c subscription : newList) {
            Stripe_Subscription__c oldSubscription = oldMap.get(subscription.Id);
            if (oldSubscription != null && subscription.PricingPlans__c != null
                && oldSubscription.PricingPlans__c != subscription.PricingPlans__c) {

                // Retrieve metadata and validate it exists
                Stripe_Price__mdt stripePrice = Stripe_Price__mdt.getInstance(subscription.PricingPlans__c);

                if (stripePrice == null) {
                    Logger.error('Stripe Price metadata not found for: ' + subscription.PricingPlans__c +
                                ' on subscription: ' + subscription.Id);
                    Logger.saveLog();
                    continue; // Skip this subscription and continue processing others
                }

                Pricing_Plan__c pricingPlan = new Pricing_Plan__c();

                // Check field-level security before setting each field
                if (Schema.SObjectType.Pricing_Plan__c.fields.Name.isCreateable()) {
                    pricingPlan.Name = stripePrice.DeveloperName;
                }
                if (Schema.SObjectType.Pricing_Plan__c.fields.Amount__c.isCreateable()) {
                    pricingPlan.Amount__c = stripePrice.Amount__c;
                }
                if (Schema.SObjectType.Pricing_Plan__c.fields.Currency__c.isCreateable()) {
                    pricingPlan.Currency__c = stripePrice.Currency__c;
                }
                if (Schema.SObjectType.Pricing_Plan__c.fields.Recurrency_Type__c.isCreateable()) {
                    pricingPlan.Recurrency_Type__c = stripePrice.RecurrencyType__c;
                }
                if (Schema.SObjectType.Pricing_Plan__c.fields.Stripe_Subscription__c.isCreateable()) {
                    pricingPlan.Stripe_Subscription__c = subscription.Id;
                }

                pricingPlansForInsert.add(pricingPlan);
            }
        }

        if (!pricingPlansForInsert.isEmpty()) {
            try {
                insert as user pricingPlansForInsert;
            } catch (DmlException dmlEx) {
                Logger.error('Failed to insert pricing plans', dmlEx);
                Logger.saveLog();
                // Re-throw to ensure trigger fails if pricing plans can't be created
                throw dmlEx;
            }
        }
    }
    
}