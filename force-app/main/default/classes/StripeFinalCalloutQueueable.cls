/**
 * @description Final queueable class in the Stripe API callout chain. Handles the attachment of a payment method to
 *              a Stripe customer, completing the customer setup workflow. This is the last step after customer and
 *              payment method creation.
 */
public class StripeFinalCalloutQueueable implements Queueable, Database.AllowsCallouts{
    public static final String ATTACH_PAYMENT = 'attach_payment';

    private String calloutType;
    private String customerId;
    private String defaultMethodId;
    private Integer retryCount;
    /**
     * @description Constructor for payment method attachment callouts. Initializes the queueable job to attach an
     *              existing payment method to a Stripe customer.
     * @param customerId Stripe customer ID to which the payment method will be attached
     * @param defaultMethodId Stripe payment method ID to attach to the customer
     */
    public StripeFinalCalloutQueueable(
        String customerId,
        String defaultMethodId
    ){
        this(customerId, defaultMethodId, 0);
    }

    /**
     * @description Constructor for payment method attachment callouts with retry count. Used for retry logic with exponential backoff.
     * @param customerId Stripe customer ID to which the payment method will be attached
     * @param defaultMethodId Stripe payment method ID to attach to the customer
     * @param retryCount Current retry attempt number (0 for initial attempt)
     */
    public StripeFinalCalloutQueueable(
        String customerId,
        String defaultMethodId,
        Integer retryCount
    ){
        this.calloutType = ATTACH_PAYMENT;
        this.customerId = customerId;
        this.defaultMethodId = defaultMethodId;
        this.retryCount = retryCount;
    }
    /**
     * @description Executes the final queueable job to attach a payment method to the customer. Completes the multi-step
     *              customer onboarding process. Implements retry logic with exponential backoff for transient errors.
     * @param context QueueableContext provided by the platform
     */
    public void execute(QueueableContext context){
        if (calloutType == ATTACH_PAYMENT) {
            try {
                String attachedPaymentMethod = StripeAPIService.attachPaymentMethod(defaultMethodId,
                                                                                    customerId);
            } catch (StripeException ex) {
                handleRetryableException(ex, 'Failed to attach payment method');
            } catch (Exception ex) {
                Logger.error('Failed to attach payment method: ', ex);
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
            StripeFinalCalloutQueueable retryJob = new StripeFinalCalloutQueueable(
                customerId,
                defaultMethodId,
                retryCount + 1
            );
            System.enqueueJob(retryJob, delayMinutes);
        } else {
            // Max retries reached or not retryable - log and give up
            Logger.error(errorContext + '. Max retries reached or error not retryable: ' + ex.getDetailedMessage())
                .addTag('Stripe-Error');
            Logger.saveLog();
        }
    }
}