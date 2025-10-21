public with sharing class PricingPlanTriggerHelper {
    public static void updateStripePriceIdOnRelatedSubscription(List<Pricing_Plan__c> newList, Map<Id, Pricing_Plan__c> oldMap){
        if (Schema.SObjectType.Stripe_Subscription__c.isUpdateable()) {
            List<Stripe_Subscription__c> subscriptionsForUpdate = new List<Stripe_Subscription__c>();
            for (Pricing_Plan__c pricePlan : newList) {
                Pricing_Plan__c oldPricePlan = oldMap.get(pricePlan.Id);
                if (!String.isBlank(pricePlan.Stripe_Price_ID__c) && oldPricePlan != null
                    && oldPricePlan.Stripe_Price_ID__c != pricePlan.Stripe_Price_ID__c
                    && !String.isBlank(pricePlan.Stripe_Subscription__c)) {
                    Stripe_Subscription__c subsription = new Stripe_Subscription__c(
                        Id = pricePlan.Stripe_Subscription__c,
                        Stripe_Price_ID__c = pricePlan.Stripe_Price_ID__c
                    );
                    subscriptionsForUpdate.add(subsription);
                }
            }
            if (!subscriptionsForUpdate.isEmpty()) {
                update as user subscriptionsForUpdate;
            }
        } else {
            throw new SecurityException('User does not have access to Stripe_Subscription__c object');
        }
    }
    public static void updateAmountOnRelatedSubscription(List<Pricing_Plan__c> newList, Map<Id, Pricing_Plan__c> oldMap){
        if (Schema.SObjectType.Stripe_Subscription__c.isUpdateable()) {
            List<Stripe_Subscription__c> subscriptionsForUpdate = new List<Stripe_Subscription__c>();
            for (Pricing_Plan__c pricePlan : newList) {
                Pricing_Plan__c oldPricePlan = oldMap.get(pricePlan.Id);
                if (oldPricePlan.Amount__c != pricePlan.Amount__c  && oldPricePlan != null
                    && !String.isBlank(pricePlan.Stripe_Subscription__c)) {
                    Stripe_Subscription__c subsription = new Stripe_Subscription__c(
                        Id = pricePlan.Stripe_Subscription__c,
                        Amount__c = pricePlan.Amount__c
                    );
                    subscriptionsForUpdate.add(subsription);
                }
            }
            if (!subscriptionsForUpdate.isEmpty()) {
                update as user subscriptionsForUpdate;
            }
        } else {
            throw new SecurityException('User does not have access to Stripe_Subscription__c object');
        }
    }
    public static void processPricingPlanAfterInsert(List<Pricing_Plan__c> newList){
        List<Pricing_Plan__c> pricingPlansForProcess = new List<Pricing_Plan__c>();
        if (Schema.SObjectType.Pricing_Plan__c.isAccessible()) {
            for (Pricing_Plan__c pricingPlan : newList) {
                if (String.isBlank(pricingPlan.Stripe_Price_ID__c)
                    && !String.isBlank(pricingPlan.ProductName__c)) {
                    pricingPlansForProcess.add(pricingPlan);
                }
            }
            if (!pricingPlansForProcess.isEmpty()) {
                for (Pricing_Plan__c pricingPlan : pricingPlansForProcess) {
                    try {
                        StripeCalloutQueueable callout = new StripeCalloutQueueable(
                            pricingPlan.Id,
                            pricingPlan.Currency__c,
                            pricingPlan.Recurrency_Type__c.toString().replace('ily','y').replace('ly',''),
                            pricingPlan.Amount__c,
                            pricingPlan.ProductName__c
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
            throw new SecurityException('User does not have access to Pricing_Plan__c object');
        }
    }
    public static void createPricingTier(List<Pricing_Plan__c> newList){
        if (Schema.SObjectType.Pricing_Plan__c.isAccessible()) {
            List<Pricing_Tier__c> pricingTierForInsert = new List<Pricing_Tier__c>();
             for (Pricing_Plan__c pricingPlan : newList){
                Stripe_Price__mdt stripePrice = Stripe_Price__mdt.getInstance(pricingPlan.Name);
                if (stripePrice != null) {
                    Pricing_Tier__c pricingTier = new Pricing_Tier__c(
                        Tier_Number__c = stripePrice.TierNumber__c,
                        Discount__c = stripePrice.Discount__c,
                        Pricing_Plan__c = pricingPlan.Id,
                        Unit_Price__c = stripePrice.PricePerUnit__c
                    );
                pricingTierForInsert.add(pricingTier);
                }
             }
             if (!pricingTierForInsert.isEmpty()) {
                insert as user pricingTierForInsert;
             }
        } else {
            throw new SecurityException('User does not have access to Pricing_Plan__c object');
        }
    }
}