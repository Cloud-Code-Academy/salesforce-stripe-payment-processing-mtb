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
        this.calloutType = ATTACH_PAYMENT;
        this.customerId = customerId;
        this.defaultMethodId = defaultMethodId;
    }
    /**
     * @description Executes the final queueable job to attach a payment method to the customer. Completes the multi-step
     *              customer onboarding process. Includes error logging for attachment failures.
     * @param context QueueableContext provided by the platform
     */
    public void execute(QueueableContext context){
        if (calloutType == ATTACH_PAYMENT) {
            try {
                String attachedPaymentMethod = StripeAPIService.attachPaymentMethod(defaultMethodId, customerId);
            } catch (Exception ex) {
                Logger.error('Failed to get subscriptionId/update Stripe Subscription record: ', ex);
                Logger.saveLog();
            }
        }
    }
}