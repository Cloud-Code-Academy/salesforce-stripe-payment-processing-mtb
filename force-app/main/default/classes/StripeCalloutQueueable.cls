/**
 * Queueable class to make asynchronous callouts to Stripe API
 */
public class StripeCalloutQueueable implements Queueable, Database.AllowsCallouts{
    public static final String CREATE_CUSTOMER = 'Create Customer';

    private String calloutType;
    private Id recordId;
    private StripeWrapper.CustomerWrapper customerWrapper;

    public StripeCalloutQueueable(
        Id recordId,
        String customerName,
        String customerEmail,
        String customerPhone
    ){
        this.calloutType = CREATE_CUSTOMER;
        this.recordId = recordId;
        this.customerWrapper = new StripeWrapper.CustomerWrapper(customerName, customerEmail, customerPhone);
    }

    public void execute(QueueableContext context){
        System.debug('Queueable started here:');
        if (calloutType == CREATE_CUSTOMER) {
            try {
                String customerId = StripeAPIService.createCustomer(customerWrapper);
                System.debug('customerId is here:' + customerId);
                updateStripeCustomer(recordId, customerId);
            } catch (Exception ex) {
                System.debug('Error occured: ' + ex.getMessage());
            }

        }
    }

    private void updateStripeCustomer(Id recordId, String customerId){
        Stripe_Customer__c customer = new Stripe_Customer__c(
            Id = recordId,
            Stripe_Customer_ID__c = customerId
        );
        update customer;
    }
}