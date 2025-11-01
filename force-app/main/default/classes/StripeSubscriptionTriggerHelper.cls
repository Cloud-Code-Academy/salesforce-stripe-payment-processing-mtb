/**
 * @description Helper class for Stripe_Subscription__c trigger operations. Manages subscription lifecycle events including
 *              initiating Stripe API callouts for subscription and checkout session creation, and creating associated
 *              Pricing Plan records based on subscription selections. Enforces object-level security throughout.
 */
public with sharing class StripeSubscriptionTriggerHelper {
    /**
     * @description Processes subscription records marked for sync to Stripe. Identifies subscriptions with 'Send to Stripe'
     *              status that have all required data (price, customer, payment method) and initiates asynchronous callouts
     *              to create the subscription in Stripe. Enforces object-level read permissions.
     * @param newList List of updated Stripe_Subscription__c records
     * @param oldMap Map of Stripe_Subscription__c records before the update (Id to old record)
     */
    public static void processStripeSubscriptionAfterUpdate(List<Stripe_Subscription__c> newList, Map<Id, Stripe_Subscription__c> oldMap){
        List<Stripe_Subscription__c> subscriptionsForProcess = new List<Stripe_Subscription__c>();
        Set<Id> customerIds = new Set<Id>();
        if (Schema.SObjectType.Stripe_Subscription__c.isAccessible()) {
            for (Stripe_Subscription__c subscription : newList) {
                Stripe_Subscription__c oldSubscription = oldMap.get(subscription.Id);
                if (oldSubscription != null
                    && oldSubscription.Sync_Status__c != subscription.Sync_Status__c
                    && subscription.Sync_Status__c == 'Send to Stripe'
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
                        Logger.error('Failed to make callout: ', ex);
                        Logger.saveLog();
                    }
                }
            }
        } else {
            throw new SecurityException('User does not have edit access to Stripe_Subscription__c object');
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
        List<Stripe_Subscription__c> subscriptionsForProcess = new List<Stripe_Subscription__c>();
        try {
            if (Schema.SObjectType.Stripe_Subscription__c.isAccessible()) {
                for (Stripe_Subscription__c subscription : newList) {
                    Stripe_Subscription__c oldSubscription = oldMap.get(subscription.Id);
                    if (oldSubscription != null
                        && oldSubscription.Sync_Status__c != subscription.Sync_Status__c
                        && subscription.Sync_Status__c == 'Synced'
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
                            Logger.error('Failed to make callout: ', ex);
                            Logger.saveLog();
                        }
                    }
                }
            } else {
                throw new SecurityException('User does not have read access to Stripe_Subscription__c object');
            }
        } catch (Exception ex) {
            Logger.error('Failed to process Stripe_Subscription__c records: ', ex);
            Logger.saveLog();
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
        List<Pricing_Plan__c> pricingPlansForInsert = new List<Pricing_Plan__c>();
        try {
            if (Schema.SObjectType.Stripe_Subscription__c.isAccessible()) {
                if (Schema.SObjectType.Pricing_Plan__c.isCreateable()) {
                    for (Stripe_Subscription__c subscription : newList) {
                        Stripe_Subscription__c oldSubscription = oldMap.get(subscription.Id);
                        if (oldSubscription != null && subscription.PricingPlans__c != null
                            && oldSubscription.PricingPlans__c != subscription.PricingPlans__c) {
                            Stripe_Price__mdt stripePrice = Stripe_Price__mdt.getInstance(subscription.PricingPlans__c);
                            Pricing_Plan__c pricingPlan = new Pricing_Plan__c(
                                Name = stripePrice.DeveloperName,
                                Amount__c = stripePrice.Amount__c,
                                Currency__c = stripePrice.Currency__c,
                                Recurrency_Type__c = stripePrice.RecurrencyType__c,
                                Stripe_Subscription__c = subscription.Id
                            );
                            pricingPlansForInsert.add(pricingPlan);
                        }
                    }
                    if (!pricingPlansForInsert.isEmpty()) {
                        insert as user pricingPlansForInsert;
                    }
                } else {
                    throw new SecurityException('User does not have edit access to Pricing_Plan__c object');
                }
            } else {
                throw new SecurityException('User does not have edit access to Stripe_Subscription__c object');
            }
        } catch (Exception ex) {
            Logger.error('Failed to create Pricing_Plan__c: ', ex);
            Logger.saveLog();
        }
        
    }
    
}