/**
 * @description Chained queueable class for executing dependent Stripe API callouts. Handles the second stage of multi-step
 *              Stripe operations including price creation (after product creation) and payment method creation (after
 *              customer creation). Implements security checks and chains to subsequent operations when needed.
 */
public class StripeChainedCalloutQueueable implements Queueable, Database.AllowsCallouts{
    public static final String CREATE_PRICING_PLAN = 'create_pricing_plan';
    public static final String CREATE_DEFAULT_METHOD = 'create_default_method';

    private String calloutType;
    private Id recordId;
    private String requestBody;
    private String customerId;
    /**
     * @description Constructor for price creation callouts. Initializes the queueable job to create a Stripe price
     *              using a pre-formatted request body (typically after product creation).
     * @param recordId Salesforce record ID of the Pricing_Plan__c record to update after price creation
     * @param requestBody URL-encoded request body containing price configuration parameters
     */
    public StripeChainedCalloutQueueable(
        Id recordId,
        String requestBody

    ){
        this.calloutType = CREATE_PRICING_PLAN;
        this.recordId = recordId;
        this.requestBody = requestBody;
    }
    /**
     * @description Constructor for payment method creation callouts. Initializes the queueable job to create and attach
     *              a default payment method to a Stripe customer.
     * @param customerId Stripe customer ID to associate with the payment method
     * @param recordId Salesforce record ID of the Stripe_Customer__c record to update with payment method details
     */
    public StripeChainedCalloutQueueable(
        String customerId,
        Id recordId
    ){
        this.calloutType = CREATE_DEFAULT_METHOD;
        this.customerId = customerId;
        this.recordId = recordId;
    }
    /**
     * @description Executes the chained queueable job based on callout type. Routes to either price creation (updating
     *              Pricing Plan) or payment method creation (updating Customer and chaining to payment method attachment).
     *              Includes comprehensive error logging for all operations.
     * @param context QueueableContext provided by the platform
     */
    public void execute(QueueableContext context){
        if (calloutType == CREATE_PRICING_PLAN) {
            try {
                String stripePriceId = StripeAPIService.createPrice(requestBody);
                updatePricingPlan(recordId, stripePriceId);
            } catch (Exception ex) {
                Logger.error('Failed to get stripePriceId/update Stripe Pricing Plan record: ', ex);
                Logger.saveLog();
            }
        } else if (calloutType == CREATE_DEFAULT_METHOD) {
            try {
                String defaultMethodId = StripeAPIService.createDefaultMethod();
                if (defaultMethodId != null) {
                    updateCustomer(recordId, defaultMethodId);
                    System.enqueueJob(new StripeFinalCalloutQueueable(customerId, defaultMethodId));
                } else {
                    Logger.error('Failed to get defaultMethodId');
                    Logger.saveLog();
                }
            } catch (Exception ex) {
                 Logger.error('Failed to update Stripe Customer record: ', ex);
                Logger.saveLog();
            }
        }
    }
    /**
     * @description Updates a Pricing_Plan__c record with the Stripe price ID returned from a successful API callout.
     *              Enforces object-level and field-level security before performing the update operation.
     * @param recordId Salesforce ID of the Pricing_Plan__c record to update
     * @param priceId Stripe price ID to store in the record
     */
    private void updatePricingPlan(Id recordId, String priceId){
        Pricing_Plan__c pricingPlan = new Pricing_Plan__c(
            Id = recordId,
            Stripe_Price_ID__c = priceId
        );
        if (Schema.SObjectType.Pricing_Plan__c.isUpdateable()) {
            if (Schema.SObjectType.Pricing_Plan__c.fields.Stripe_Price_ID__c.isUpdateable()) {
                try {
                    update as user pricingPlan;
                } catch (Exception ex) {
                    Logger.error('Error occurred while updating Pricing Plan record: ', ex);
                    Logger.saveLog();
                }
            } else {
                throw new SecurityException('Stripe_Price_ID__c field of Pricing_Plan__c is not available for update');
            }
        } else {
            throw new SecurityException('Pricing_Plan__c object is not available for update');
        }
    }
    /**
     * @description Updates a Stripe_Customer__c record with the default payment method ID returned from a successful
     *              API callout. Enforces object-level and field-level security before performing the update operation.
     * @param recordId Salesforce ID of the Stripe_Customer__c record to update
     * @param defaultMethodId Stripe payment method ID to store as the default payment method
     */
    private void updateCustomer(Id recordId, String defaultMethodId){
        Stripe_Customer__c customer = new Stripe_Customer__c(
            Id = recordId,
            Default_Payment_Method__c = defaultMethodId
        );
        //Check whether Stripe_Customer__c object is available for update
        if (Schema.SObjectType.Stripe_Customer__c.isUpdateable()) {
            //Check whether Default_Payment_Method__c field of Stripe_Customer__c object is available for update
            if (Schema.SObjectType.Stripe_Customer__c.fields.Default_Payment_Method__c.isUpdateable()) {
                try {
                    update as user customer;
                } catch (Exception ex) {
                    Logger.error('Error occurred while updating Stripe Customer record: ', ex);
                    Logger.saveLog();
                }
            } else {
                throw new SecurityException('Default_Payment_Method__c field of Stripe_Customer__c is not available for update');
            }
        } else {
            throw new SecurityException('Stripe_Customer__c object is not available for update');
        }
    }
}