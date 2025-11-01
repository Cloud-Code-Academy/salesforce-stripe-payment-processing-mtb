public with sharing class PricingPlanTriggerHelper {
    /**
     * @description Synchronizes Stripe Price ID changes from Pricing Plans to their related Stripe Subscriptions.
     *              Triggers when a Pricing Plan's Stripe_Price_ID__c is updated and propagates the change to any
     *              linked Stripe_Subscription__c record. Enforces object-level update permissions before performing DML.
     * @param newList List of updated Pricing_Plan__c records
     * @param oldMap Map of Pricing_Plan__c records before the update (Id to old record)
     */
    public static void updateStripePriceIdOnRelatedSubscription(List<Pricing_Plan__c> newList, Map<Id, Pricing_Plan__c> oldMap){
        Map<Id, Stripe_Subscription__c> subscriptionsForUpdate = new Map<Id, Stripe_Subscription__c>();
        try {
            for (Pricing_Plan__c pricePlan : newList) {
                Pricing_Plan__c oldPricePlan = oldMap.get(pricePlan.Id);
                if (!String.isBlank(pricePlan.Stripe_Price_ID__c) && oldPricePlan != null
                    && oldPricePlan.Stripe_Price_ID__c != pricePlan.Stripe_Price_ID__c
                    && !String.isBlank(pricePlan.Stripe_Subscription__c)) {
                    subscriptionsForUpdate.put(pricePlan.Stripe_Subscription__c,
                                                new  Stripe_Subscription__c(
                                                    Id = pricePlan.Stripe_Subscription__c,
                                                    Stripe_Price_ID__c = pricePlan.Stripe_Price_ID__c
                                                ));
                }
            }
            if (Schema.SObjectType.Stripe_Subscription__c.isUpdateable()) {
                if (!subscriptionsForUpdate.isEmpty()) {
                    update as user subscriptionsForUpdate.values();
                }
            } else {
                throw new SecurityException('User does not have access to Stripe_Subscription__c object');
            }
        } catch (Exception ex) {
            Logger.error('Error occurred while updating Pricing_Plan__c', ex);
            Logger.saveLog();
        }

    }
    /**
     * @description Synchronizes Amount changes from Pricing Plans to their related Stripe Subscriptions.
     *              Triggers when a Pricing Plan's Amount__c is updated and propagates the change to any
     *              linked Stripe_Subscription__c record. Enforces object-level update permissions before performing DML.
     * @param newList List of updated Pricing_Plan__c records
     * @param oldMap Map of Pricing_Plan__c records before the update (Id to old record)
     */
    public static void updateAmountOnRelatedSubscription(List<Pricing_Plan__c> newList, Map<Id, Pricing_Plan__c> oldMap){
        Map<Id, Stripe_Subscription__c> subscriptionsForUpdate = new Map<Id, Stripe_Subscription__c>();
        try {
            if (Schema.SObjectType.Pricing_Plan__c.isAccessible()) {
                for (Pricing_Plan__c pricePlan : newList) {
                    Pricing_Plan__c oldPricePlan;
                    if ((oldMap == null || oldMap.get(pricePlan.Id).Amount__c != pricePlan.Amount__c)
                        && pricePlan.Stripe_Subscription__c != null) {
                        subscriptionsForUpdate.put(pricePlan.Stripe_Subscription__c,
                                                new  Stripe_Subscription__c(
                                                    Id = pricePlan.Stripe_Subscription__c,
                                                    Amount__c = pricePlan.Amount__c
                                                ));
                    }
                }
                if (Schema.SObjectType.Stripe_Subscription__c.isUpdateable()) {
                    if (!subscriptionsForUpdate.isEmpty()) {
                        update as user subscriptionsForUpdate.values();
                    }
                } else {
                    throw new SecurityException('User does not have access to Stripe_Subscription__c object');
                }
            } else {
                throw new SecurityException('User does not have access to Pricing_Plan__c object');
            }
        } catch (Exception ex) {
            Logger.error('Error occurred while updating Amount on related Subscription ', ex);
            Logger.saveLog();
        }
    }
    /**
     * @description Processes newly inserted Pricing Plans and initiates Stripe Price creation via asynchronous callout.
     *              Identifies Pricing Plans without a Stripe_Price_ID__c but with a ProductName__c, then queues a
     *              StripeCalloutQueueable job for each to create the corresponding Stripe Price. Enforces object-level
     *              read permissions and includes error logging for failed callout initiations.
     * @param newList List of newly inserted Pricing_Plan__c records
     */
    public static void processPricingPlanAfterInsert(List<Pricing_Plan__c> newList){
        List<Pricing_Plan__c> pricingPlansForProcess = new List<Pricing_Plan__c>();
        try {
            if (Schema.SObjectType.Pricing_Plan__c.isAccessible()) {
                for (Pricing_Plan__c pricingPlan : newList) {
                    if (String.isBlank(pricingPlan.Stripe_Price_ID__c)
                        && !String.isBlank(pricingPlan.ProductName__c)
                        && !String.isBlank(pricingPlan.Recurrency_Type__c)) {
                        pricingPlansForProcess.add(pricingPlan);
                    }
                }
                //Make callout for each Pricing_Plan__c to create Price object in Stripe
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
        } catch (Exception ex) {
            Logger.error('Error while making callouts for Pricing_Plan__c', ex);
            Logger.saveLog();
        }
        
    }
    /**
     * @description Creates Pricing Tier records for newly inserted Pricing Plans based on custom metadata configuration.
     *              Retrieves tier configuration (tier number, discount, unit price) from Stripe_Price__mdt custom metadata
     *              using the Pricing Plan's name as the lookup key. Enforces object-level create permissions before DML.
     * @param newList List of newly inserted Pricing_Plan__c records
     */
    public static void createPricingTier(List<Pricing_Plan__c> newList){
        List<Pricing_Tier__c> pricingTierForInsert = new List<Pricing_Tier__c>();
        try {
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
            if (Schema.SObjectType.Pricing_Tier__c.isCreateable()) {
                if (!pricingTierForInsert.isEmpty()) {
                    insert as user pricingTierForInsert;
                }
            } else {
                throw new SecurityException('User does not have access to Pricing_Tier__c object');
            }
        } catch (Exception ex) {
            Logger.error('Error while creating Pricing_Tier__c', ex);
            Logger.saveLog();
        }
    }
}