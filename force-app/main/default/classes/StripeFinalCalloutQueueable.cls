public class StripeFinalCalloutQueueable implements Queueable, Database.AllowsCallouts{
    public static final String ATTACH_PAYMENT = 'attach_payment';

    private String calloutType;
    private String customerId;
    private String defaultMethodId;

    public StripeFinalCalloutQueueable(
        String customerId,
        String defaultMethodId
    ){
        this.calloutType = ATTACH_PAYMENT;
        this.customerId = customerId;
        this.defaultMethodId = defaultMethodId;
    }
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