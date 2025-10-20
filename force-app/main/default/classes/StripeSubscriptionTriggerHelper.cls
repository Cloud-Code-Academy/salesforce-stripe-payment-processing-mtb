public with sharing class StripeSubscriptionTriggerHelper {
    public static void processStripeSubscriptionAfterUpdate(List<Stripe_Subscription__c> newList, Map<Id, Stripe_Subscription__c> oldMap){
        List<Stripe_Subscription__c> subscriptionsForProcess = new List<Stripe_Subscription__c>();
        List<Stripe_Subscription__c> subscriptionsForUpdate = new List<Stripe_Subscription__c>();
        Set<Id> customerIds = new Set<Id>();
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
    }
    public static void processStripeSubscriptionToCreateSession(List<Stripe_Subscription__c> newList, Map<Id, Stripe_Subscription__c> oldMap){
        List<Stripe_Subscription__c> subscriptionsForProcess = new List<Stripe_Subscription__c>();
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
    }
    public static void createPricingPlansUponSelection(List<Stripe_Subscription__c> newList, Map<Id, Stripe_Subscription__c> oldMap){
        List<Pricing_Plan__c> pricingPlansForInsert = new List<Pricing_Plan__c>();
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
            insert pricingPlansForInsert;
        }
    }
}