public with sharing class PricingPlanTriggerHelper {
    /**
     * @description Synchronizes Stripe Price ID changes from Pricing Plans to their related Stripe Subscriptions.
     *              Triggers when a Pricing Plan's Stripe_Price_ID__c is updated and propagates the change to any
     *              linked Stripe_Subscription__c record. Enforces object-level update permissions before performing DML.
     *              Logs errors if the update operation fails.
     * @param newList List of updated Pricing_Plan__c records
     * @param oldMap Map of Pricing_Plan__c records before the update (Id to old record)
     */
    public static void updateStripePriceIdOnRelatedSubscription(List<Pricing_Plan__c> newList, Map<Id, Pricing_Plan__c> oldMap){
        try {
            // Validate input parameters
            if (newList == null || newList.isEmpty() || oldMap == null) {
                Logger.warn('updateStripePriceIdOnRelatedSubscription called with null or empty parameters')
                    .addTag('PricingPlanTriggerHelper');
                Logger.saveLog();
                return;
            }

            if(!Schema.SObjectType.Pricing_Plan__c.isAccessible()){
                Logger.warn('updateStripePriceIdOnRelatedSubscription called with no pricing plan access')
                    .addTag('PricingPlanTriggerHelper');
                Logger.saveLog();
                return;
            }

            // Use Map to prevent duplicate Id errors if multiple pricing plans reference the same subscription
            Map<Id, Stripe_Subscription__c> subscriptionsForUpdateMap = new Map<Id, Stripe_Subscription__c>();

            for (Pricing_Plan__c pricePlan : newList) {
                try {
                    Pricing_Plan__c oldPricePlan = oldMap.get(pricePlan.Id);
                    if (!String.isBlank(pricePlan.Stripe_Price_ID__c) && oldPricePlan != null
                        && oldPricePlan.Stripe_Price_ID__c != pricePlan.Stripe_Price_ID__c
                        && !String.isBlank(pricePlan.Stripe_Subscription__c)) {

                        // Check if this subscription is already in the map (multiple pricing plans referencing same subscription)
                        if (subscriptionsForUpdateMap.containsKey(pricePlan.Stripe_Subscription__c)) {
                            Logger.warn('Multiple Pricing Plans reference the same Subscription: ' + pricePlan.Stripe_Subscription__c)
                                .setMessage('Pricing Plan ' + pricePlan.Id + ' references subscription already updated by another plan')
                                .addTag('PricingPlanTriggerHelper')
                                .addTag('Duplicate-Subscription-Reference');
                            Logger.saveLog();
                        }

                        Stripe_Subscription__c subsription = new Stripe_Subscription__c(
                            Id = pricePlan.Stripe_Subscription__c,
                            Stripe_Price_ID__c = pricePlan.Stripe_Price_ID__c
                        );
                        subscriptionsForUpdateMap.put(pricePlan.Stripe_Subscription__c, subsription);
                    }
                } catch (Exception ex) {
                    // Log individual record processing error but continue with other records
                    Logger.error('Error processing Pricing Plan: ' + pricePlan.Id, ex)
                        .addTag('PricingPlanTriggerHelper')
                        .addTag('StripePriceID-Update');
                    Logger.saveLog();
                }
            }

            // Perform DML operation
            if (!subscriptionsForUpdateMap.isEmpty()) {
                if (Schema.SObjectType.Stripe_Subscription__c.isUpdateable()) {
                    update as user subscriptionsForUpdateMap.values();
                    Logger.info('Successfully updated ' + subscriptionsForUpdateMap.size() + ' Stripe Subscriptions with new Price IDs')
                        .addTag('PricingPlanTriggerHelper');
                    Logger.saveLog();
                } else {
                    throw new SecurityException('User does not have access to update Stripe_Subscription__c object');
                }
            }
        } catch (DmlException dmlEx) {
            // Handle DML-specific errors
            Logger.error('DML error updating Stripe Subscriptions: ' + dmlEx.getMessage(), dmlEx)
                .setMessage('Failed to update subscriptions. Details: ' + dmlEx.getDmlMessage(0))
                .addTag('PricingPlanTriggerHelper')
                .addTag('DML-Error');
            Logger.saveLog();
            throw dmlEx;
        } catch (SecurityException secEx) {
            // Handle security/permission errors
            Logger.error('Security error: User lacks permissions to update Stripe Subscriptions', secEx)
                .addTag('PricingPlanTriggerHelper')
                .addTag('Security-Error');
            Logger.saveLog();
            throw secEx;
        } catch (Exception ex) {
            // Handle any other unexpected errors
            Logger.error('Unexpected error in updateStripePriceIdOnRelatedSubscription: ' + ex.getMessage(), ex)
                .addTag('PricingPlanTriggerHelper')
                .addTag('Unexpected-Error');
            Logger.saveLog();
            throw ex;
        }
    }
    /**
     * @description Synchronizes Amount changes from Pricing Plans to their related Stripe Subscriptions.
     *              Triggers when a Pricing Plan's Amount__c is updated and propagates the change to any
     *              linked Stripe_Subscription__c record. Enforces object-level update permissions before performing DML.
     *              Logs errors if the update operation fails.
     * @param newList List of updated Pricing_Plan__c records
     * @param oldMap Map of Pricing_Plan__c records before the update (Id to old record)
     */
    public static void updateAmountOnRelatedSubscription(List<Pricing_Plan__c> newList, Map<Id, Pricing_Plan__c> oldMap){
        try {
            // Validate input parameters
            if (newList == null || newList.isEmpty()) {
                Logger.warn('updateAmountOnRelatedSubscription called with null or empty newList')
                    .addTag('PricingPlanTriggerHelper');
                Logger.saveLog();
                return;
            }

            // Use Map to prevent duplicate Id errors if multiple pricing plans reference the same subscription
            Map<Id, Stripe_Subscription__c> subscriptionsForUpdateMap = new Map<Id, Stripe_Subscription__c>();

            for (Pricing_Plan__c pricePlan : newList) {
                try {
                    Pricing_Plan__c oldPricePlan;
                    if (oldMap != null) {
                        oldPricePlan = oldMap.get(pricePlan.Id);
                    }
                    if ((oldPricePlan == null || oldPricePlan.Amount__c != pricePlan.Amount__c)
                         && pricePlan.Stripe_Subscription__c != null) {

                        // Check if this subscription is already in the map (multiple pricing plans referencing same subscription)
                        if (subscriptionsForUpdateMap.containsKey(pricePlan.Stripe_Subscription__c)) {
                            Logger.warn('Multiple Pricing Plans reference the same Subscription: ' + pricePlan.Stripe_Subscription__c)
                                .setMessage('Pricing Plan ' + pricePlan.Id + ' references subscription already updated by another plan')
                                .addTag('PricingPlanTriggerHelper')
                                .addTag('Duplicate-Subscription-Reference');
                            Logger.saveLog();
                        }

                        Stripe_Subscription__c subsription = new Stripe_Subscription__c(
                            Id = pricePlan.Stripe_Subscription__c,
                            Amount__c = pricePlan.Amount__c
                        );
                        subscriptionsForUpdateMap.put(pricePlan.Stripe_Subscription__c, subsription);
                    }
                } catch (Exception ex) {
                    // Log individual record processing error but continue with other records
                    Logger.error('Error processing Pricing Plan: ' + pricePlan.Id, ex)
                        .addTag('PricingPlanTriggerHelper')
                        .addTag('Amount-Update');
                    Logger.saveLog();
                }
            }

            // Perform DML operation
            if (!subscriptionsForUpdateMap.isEmpty()) {
                if (Schema.SObjectType.Stripe_Subscription__c.isUpdateable()) {
                    update as user subscriptionsForUpdateMap.values();
                    Logger.info('Successfully updated ' + subscriptionsForUpdateMap.size() + ' Stripe Subscriptions with new Amounts')
                        .addTag('PricingPlanTriggerHelper');
                    Logger.saveLog();
                } else {
                    throw new SecurityException('User does not have access to update Stripe_Subscription__c object');
                }
            }
        } catch (DmlException dmlEx) {
            // Handle DML-specific errors
            Logger.error('DML error updating Stripe Subscriptions: ' + dmlEx.getMessage(), dmlEx)
                .setMessage('Failed to update subscription amounts. Details: ' + dmlEx.getDmlMessage(0))
                .addTag('PricingPlanTriggerHelper')
                .addTag('DML-Error');
            Logger.saveLog();
            throw dmlEx;
        } catch (SecurityException secEx) {
            // Handle security/permission errors
            Logger.error('Security error: User lacks permissions to update Stripe Subscriptions', secEx)
                .addTag('PricingPlanTriggerHelper')
                .addTag('Security-Error');
            Logger.saveLog();
            throw secEx;
        } catch (Exception ex) {
            // Handle any other unexpected errors
            Logger.error('Unexpected error in updateAmountOnRelatedSubscription: ' + ex.getMessage(), ex)
                .addTag('PricingPlanTriggerHelper')
                .addTag('Unexpected-Error');
            Logger.saveLog();
            throw ex;
        }
    }
    /**
     * @description Processes newly inserted Pricing Plans and initiates Stripe Price creation via asynchronous callout.
     *              Identifies Pricing Plans without a Stripe_Price_ID__c but with a ProductName__c, then queues a
     *              StripeCalloutQueueable job for each to create the corresponding Stripe Price. Enforces object-level
     *              read permissions and includes comprehensive error logging for failed callout initiations.
     * @param newList List of newly inserted Pricing_Plan__c records
     */
    public static void processPricingPlanAfterInsert(List<Pricing_Plan__c> newList){
        try {
            // Validate input parameters
            if (newList == null || newList.isEmpty()) {
                Logger.warn('processPricingPlanAfterInsert called with null or empty newList')
                    .addTag('PricingPlanTriggerHelper');
                Logger.saveLog();
                return;
            }

            // Check permissions first
            if (!Schema.SObjectType.Pricing_Plan__c.isAccessible()) {
                throw new SecurityException('User does not have access to read Pricing_Plan__c object');
            }

            List<Pricing_Plan__c> pricingPlansForProcess = new List<Pricing_Plan__c>();

            // Identify pricing plans that need Stripe price creation
            Set<Id> pricingPlanIds = new Set<Id>();
            for (Pricing_Plan__c pricingPlan : newList) {
                try {
                    if (String.isBlank(pricingPlan.Stripe_Price_ID__c)) {
                        pricingPlanIds.add(pricingPlan.Id);
                    }
                } catch (Exception ex) {
                    // Log individual record processing error but continue with other records
                    Logger.error('Error validating Pricing Plan: ' + pricingPlan.Id, ex)
                        .addTag('PricingPlanTriggerHelper')
                        .addTag('Validation-Error');
                    Logger.saveLog();
                }
            }

            // Query the pricing plans with required fields
            if (!pricingPlanIds.isEmpty()) {
                pricingPlansForProcess = [SELECT Id, Currency__c, Recurrency_Type__c, Amount__c, Stripe_Price_ID__c,
                                                 Stripe_Subscription__r.Product_Plan_Name__c
                                         FROM Pricing_Plan__c
                                         WHERE Id IN :pricingPlanIds];
            }

            // Enqueue a single batch job for all pricing plans instead of one per record
            if (!pricingPlansForProcess.isEmpty()) {
                // Pre-validate all records before enqueueing
                List<Pricing_Plan__c> validPlansForProcessing = new List<Pricing_Plan__c>();
                Integer failureCount = 0;

                for (Pricing_Plan__c pricingPlan : pricingPlansForProcess) {
                    try {
                        // Validate required fields before adding to batch
                        if (pricingPlan.Currency__c == null || pricingPlan.Recurrency_Type__c == null
                            || pricingPlan.Amount__c == null) {
                            throw new IllegalArgumentException('Missing required fields for Stripe Price creation');
                        }
                        // Only process if we have a product name (from related subscription)
                        if (pricingPlan.Stripe_Subscription__r != null &&
                            !String.isBlank(pricingPlan.Stripe_Subscription__r.Product_Plan_Name__c)) {
                            validPlansForProcessing.add(pricingPlan);
                        }
                    } catch (Exception ex) {
                        // Log validation errors but continue with valid records
                        failureCount++;
                        Logger.error('Failed to process Pricing Plan: ' + pricingPlan.Id, ex)
                            .setMessage('Error details: ' + ex.getMessage())
                            .addTag('PricingPlanTriggerHelper')
                            .addTag('Validation-Error');
                        Logger.saveLog();
                    }
                }

                // Enqueue batch job if we have valid plans
                if (!validPlansForProcessing.isEmpty()) {
                    try {
                        StripeCalloutQueueable callout = new StripeCalloutQueueable(validPlansForProcessing);
                        if (!Test.isRunningTest()) {
                            System.enqueueJob(callout);
                            Logger.info('Enqueued batch job for ' + validPlansForProcessing.size() + ' pricing plans')
                                .addTag('PricingPlanTriggerHelper')
                                .addTag('Batch-Processing');
                            Logger.saveLog();
                        }
                    } catch (AsyncException asyncEx) {
                        // Handle queueable-specific errors (e.g., too many jobs)
                        Logger.error('Failed to enqueue Stripe batch callout', asyncEx)
                            .setMessage('AsyncException: ' + asyncEx.getMessage())
                            .addTag('PricingPlanTriggerHelper')
                            .addTag('Queueable-Error');
                        Logger.saveLog();
                    }
                }

                // Log summary
                Logger.info('Processed ' + pricingPlansForProcess.size() + ' Pricing Plans. Valid for processing: ' + validPlansForProcessing.size() + ', Validation failures: ' + failureCount)
                    .addTag('PricingPlanTriggerHelper')
                    .addTag('Processing-Summary');
                Logger.saveLog();
            } else {
                Logger.info('No Pricing Plans require Stripe Price creation')
                    .addTag('PricingPlanTriggerHelper');
                Logger.saveLog();
            }
        } catch (SecurityException secEx) {
            // Handle security/permission errors
            Logger.error('Security error: User lacks permissions to process Pricing Plans', secEx)
                .addTag('PricingPlanTriggerHelper')
                .addTag('Security-Error');
            Logger.saveLog();
            throw secEx;
        } catch (Exception ex) {
            // Handle any other unexpected errors
            Logger.error('Unexpected error in processPricingPlanAfterInsert: ' + ex.getMessage(), ex)
                .addTag('PricingPlanTriggerHelper')
                .addTag('Unexpected-Error');
            Logger.saveLog();
            throw ex;
        }
    }
    /**
     * @description Creates Pricing Tier records for newly inserted Pricing Plans based on custom metadata configuration.
     *              Retrieves tier configuration (tier number, discount, unit price) from Stripe_Price__mdt custom metadata
     *              using the Pricing Plan's name as the lookup key. Enforces object-level create permissions before DML.
     *              Logs errors if the insert operation fails.
     * @param newList List of newly inserted Pricing_Plan__c records
     */
    public static void createPricingTier(List<Pricing_Plan__c> newList){
        try {
            // Validate input parameters
            if (newList == null || newList.isEmpty()) {
                Logger.warn('createPricingTier called with null or empty newList')
                    .addTag('PricingPlanTriggerHelper');
                Logger.saveLog();
                return;
            }

            List<Pricing_Tier__c> pricingTierForInsert = new List<Pricing_Tier__c>();

            for (Pricing_Plan__c pricingPlan : newList){
                try {
                    // Query custom metadata for pricing tier configuration
                    Stripe_Price__mdt stripePrice = Stripe_Price__mdt.getInstance(pricingPlan.Name);

                    if (stripePrice != null) {
                        Pricing_Tier__c pricingTier = new Pricing_Tier__c(
                            Tier_Number__c = stripePrice.TierNumber__c,
                            Discount__c = stripePrice.Discount__c,
                            Pricing_Plan__c = pricingPlan.Id,
                            Unit_Price__c = stripePrice.PricePerUnit__c
                        );
                        pricingTierForInsert.add(pricingTier);
                    } else {
                        // Log warning if no custom metadata found for this pricing plan
                        Logger.warn('No Stripe_Price__mdt metadata found for Pricing Plan: ' + pricingPlan.Name)
                            .addTag('PricingPlanTriggerHelper')
                            .addTag('Metadata-Missing');
                        Logger.saveLog();
                    }
                } catch (Exception ex) {
                    // Log individual record processing error but continue with other records
                    Logger.error('Error creating Pricing Tier for Pricing Plan: ' + pricingPlan.Id, ex)
                        .addTag('PricingPlanTriggerHelper')
                        .addTag('Tier-Creation-Error');
                    Logger.saveLog();
                }
            }

            // Perform DML operation
            if (!pricingTierForInsert.isEmpty()) {
                // Fixed: Check Pricing_Tier__c permissions instead of Stripe_Subscription__c
                if (Schema.SObjectType.Pricing_Tier__c.isCreateable()) {
                    insert as user pricingTierForInsert;
                    Logger.info('Successfully created ' + pricingTierForInsert.size() + ' Pricing Tiers')
                        .addTag('PricingPlanTriggerHelper');
                    Logger.saveLog();
                } else {
                    throw new SecurityException('User does not have access to create Pricing_Tier__c records');
                }
            } else {
                Logger.info('No Pricing Tiers to create')
                    .addTag('PricingPlanTriggerHelper');
                Logger.saveLog();
            }
        } catch (DmlException dmlEx) {
            // Handle DML-specific errors
            Logger.error('DML error creating Pricing Tiers: ' + dmlEx.getMessage(), dmlEx)
                .setMessage('Failed to create pricing tiers. Details: ' + dmlEx.getDmlMessage(0))
                .addTag('PricingPlanTriggerHelper')
                .addTag('DML-Error');
            Logger.saveLog();
            throw dmlEx;
        } catch (SecurityException secEx) {
            // Handle security/permission errors
            Logger.error('Security error: User lacks permissions to create Pricing Tiers', secEx)
                .addTag('PricingPlanTriggerHelper')
                .addTag('Security-Error');
            Logger.saveLog();
            throw secEx;
        } catch (Exception ex) {
            // Handle any other unexpected errors
            Logger.error('Unexpected error in createPricingTier: ' + ex.getMessage(), ex)
                .addTag('PricingPlanTriggerHelper')
                .addTag('Unexpected-Error');
            Logger.saveLog();
            throw ex;
        }
    }
}