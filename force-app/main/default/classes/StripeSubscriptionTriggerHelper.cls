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
            // Changed logic: Instead of creating subscription directly, create checkout session which will create the subscription
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
                    // Create checkout session directly - this will create the subscription in Stripe
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
                    Logger.error('Failed to update subscription status after callout failure', dmlEx);
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
        if (newList == null || newList.isEmpty() || oldMap == null) {
            return;
        }
        try {
            for (Stripe_Subscription__c subscription : newList) {
                //Check whether Subscription related to Customer
                if (subscription.Contact__c != null) {
                    //Check whether Status field was updated to or from Active value
                    if ((oldMap.get(subscription.Id).Status__c != subscription.Status__c 
                        && subscription.Amount__c != null
                        && (oldMap.get(subscription.Id).Status__c == STATUS_ACTIVE
                            || subscription.Status__c == STATUS_ACTIVE))
                        //Check whether Amount__c field was updated on Active Subscription
                        || (oldMap.get(subscription.Id).Amount__c != subscription.Amount__c 
                            && subscription.Status__c == STATUS_ACTIVE)) {
                        customerIds.add(subscription.Contact__c);
                    }
                }
            }
            //Exit early if no records meet criteria
            if (customerIds.isEmpty()) {
                return;
            }
            //Loop through all subscriptions and calculate MRR
            for (Stripe_Subscription__c subscription : [SELECT Amount__c, Current_Period_Start__c, Current_Period_End__c, Contact__c
                                                        FROM Stripe_Subscription__c
                                                        WHERE Status__c =: STATUS_ACTIVE
                                                        AND Contact__c IN: customerIds
                                                        AND Amount__c != null
                                                        AND Current_Period_Start__c != null
                                                        AND Current_Period_End__c != null]) {
                //Calculate days for current Subscription
                Integer subscriptionDays = Date.valueOf(subscription.Current_Period_Start__c).daysBetween(Date.valueOf(subscription.Current_Period_End__c));
                if (subscriptionDays <= 0) {
                    subscriptionDays = 1;
                }
                //Calculate average Revenue per day
                Decimal amountPerDay = subscription.Amount__c / subscriptionDays;
                //Calculate monthly Revenue
                Decimal monthlyRevenue = amountPerDay * AVERAGE_DAYS_IN_MONTH;
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