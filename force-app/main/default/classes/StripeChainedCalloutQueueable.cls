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
    private Integer retryCount;
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
        this(recordId, requestBody, 0);
    }

    /**
     * @description Constructor for price creation callouts with retry count. Used for retry logic with exponential backoff.
     * @param recordId Salesforce record ID of the Pricing_Plan__c record to update after price creation
     * @param requestBody URL-encoded request body containing price configuration parameters
     * @param retryCount Current retry attempt number (0 for initial attempt)
     */
    public StripeChainedCalloutQueueable(
        Id recordId,
        String requestBody,
        Integer retryCount
    ){
        this.calloutType = CREATE_PRICING_PLAN;
        this.recordId = recordId;
        this.requestBody = requestBody;
        this.retryCount = retryCount;
    }

    /**
     * @description Constructor for payment method creation callouts. Initializes the queueable job to create and attach
     *              a default payment method to a Stripe customer.
     * @param customerId Stripe customer ID to associate with the payment method
     * @param recordId Salesforce record ID of the Contact record to update with payment method details
     */
    public StripeChainedCalloutQueueable(
        String customerId,
        Id recordId
    ){
        this(customerId, recordId, 0);
    }

    /**
     * @description Constructor for payment method creation callouts with retry count. Used for retry logic with exponential backoff.
     * @param customerId Stripe customer ID to associate with the payment method
     * @param recordId Salesforce record ID of the Contact record to update with payment method details
     * @param retryCount Current retry attempt number (0 for initial attempt)
     */
    public StripeChainedCalloutQueueable(
        String customerId,
        Id recordId,
        Integer retryCount
    ){
        this.calloutType = CREATE_DEFAULT_METHOD;
        this.customerId = customerId;
        this.recordId = recordId;
        this.retryCount = retryCount;
    }
    /**
     * @description Executes the chained queueable job based on callout type. Routes to either price creation (updating
     *              Pricing Plan) or payment method creation (updating Customer and chaining to payment method attachment).
     *              Implements retry logic with exponential backoff for transient errors.
     * @param context QueueableContext provided by the platform
     */
    public void execute(QueueableContext context){
        if (calloutType == CREATE_PRICING_PLAN) {
            try {
                String stripePriceId = StripeAPIService.createPrice(requestBody);
                updatePricingPlan(recordId, stripePriceId);
            } catch (StripeException ex) {
                handleRetryableException(ex, 'Failed to create price');
            } catch (Exception ex) {
                Logger.error('Failed to get stripePriceId/update Stripe Pricing Plan record: ', ex);
                Logger.saveLog();
            }
        } else if (calloutType == CREATE_DEFAULT_METHOD) {
            try {
                String defaultMethodId = StripeAPIService.createDefaultMethod(customerId);
                if (defaultMethodId != null) {
                    updateCustomer(recordId, defaultMethodId);
                    System.enqueueJob(new StripeFinalCalloutQueueable(customerId, defaultMethodId));
                }
            } catch (StripeException ex) {
                handleRetryableException(ex, 'Failed to create default payment method');
            } catch (Exception ex) {
                 Logger.error('Failed to get defaultMethodId/update Stripe Customer record: ', ex);
                Logger.saveLog();
            }
        }
    }

    /**
     * @description Handles retryable exceptions by re-enqueueing the job with exponential backoff delay.
     * @param ex The StripeException that was thrown
     * @param errorContext Context string describing the operation that failed
     */
    private void handleRetryableException(StripeException ex, String errorContext) {
        if (ex.isRetryable() && retryCount < StripeAPIService.MAX_RETRY_COUNT) {
            // Calculate exponential backoff delay in minutes
            Integer delayMinutes = (Integer)(Math.pow(2, retryCount) * StripeAPIService.BASE_DELAY_MINUTES);

            Logger.warn(errorContext + '. Retryable error encountered. Retry attempt ' + (retryCount + 1) +
                       ' of ' + StripeAPIService.MAX_RETRY_COUNT + '. Retrying in ' + delayMinutes + ' minutes')
                .setMessage(ex.getDetailedMessage())
                .addTag('Stripe-Retry');
            Logger.saveLog();

            // Re-enqueue the job with delay
            StripeChainedCalloutQueueable retryJob = createRetryJob();
            System.enqueueJob(retryJob, delayMinutes);
        } else {
            // Max retries reached or not retryable - log and give up
            Logger.error(errorContext + '. Max retries reached or error not retryable: ' + ex.getDetailedMessage())
                .addTag('Stripe-Error');
            Logger.saveLog();
        }
    }

    /**
     * @description Creates a new instance of StripeChainedCalloutQueueable with incremented retry count for re-enqueueing.
     * @return StripeChainedCalloutQueueable A new instance with the same parameters but incremented retry count
     */
    private StripeChainedCalloutQueueable createRetryJob() {
        Integer nextRetryCount = retryCount + 1;

        if (calloutType == CREATE_PRICING_PLAN) {
            return new StripeChainedCalloutQueueable(
                recordId,
                requestBody,
                nextRetryCount
            );
        } else if (calloutType == CREATE_DEFAULT_METHOD) {
            return new StripeChainedCalloutQueueable(
                customerId,
                recordId,
                nextRetryCount
            );
        }

        return null; // Should never reach here
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
                    Logger.error('Error occured while updating Pricing Plan record: ', ex);
                    Logger.saveLog();
                }
            } else {
                throw new SecurityException('Stripe_Price_ID__c field of Pricing_Plan__c is not available for update');
            }
        } else {
            throw new SecurityException('Stripe_Price_ID__c object is not available for update');
        }
    }
    /**
     * @description Updates a Contact record with the default payment method ID returned from a successful
     *              API callout. Enforces object-level and field-level security before performing the update operation.
     * @param recordId Salesforce ID of the Contact record to update
     * @param defaultMethodId Stripe payment method ID to store as the default payment method
     */
    private void updateCustomer(Id recordId, String defaultMethodId){
        Contact contact = new Contact(
            Id = recordId,
            Default_Payment_Method__c = defaultMethodId
        );
        //Check whether Contact object is available for update
        if (Schema.SObjectType.Contact.isUpdateable()) {
            //Check whether Default_Payment_Method__c field of Contact object is available for update
            if (Schema.SObjectType.Contact.fields.Default_Payment_Method__c.isUpdateable()) {
                try {
                    update as user contact;
                } catch (Exception ex) {
                    Logger.error('Error occured while updating Contact record: ', ex);
                    Logger.saveLog();
                }
            } else {
                throw new SecurityException('Default_Payment_Method__c field of Contact is not available for update');
            }
        } else {
            throw new SecurityException('Contact object is not available for update');
        }
    }
}