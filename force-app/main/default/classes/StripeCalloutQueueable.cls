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
        // Run Create Customer path
        if (calloutType == CREATE_CUSTOMER) {
            try {
                String customerId = StripeAPIService.createCustomer(customerWrapper);
                updateStripeCustomer(recordId, customerId);
            } catch (Exception ex) {
                System.debug('Error occured: ' + ex.getMessage());
            }

        }
    }
    //Utility method for updating Stripe Customer record with Id from successfull response
    private void updateStripeCustomer(Id recordId, String customerId){
        Stripe_Customer__c customer = new Stripe_Customer__c(
            Id = recordId,
            Stripe_Customer_ID__c = customerId
        );
        //Check whether Stripe_Customer__c object is available for update
        if (Schema.SObjectType.Stripe_Customer__c.isUpdateable()) {
            //Check whether Stripe_Customer_ID__c field of Stripe_Customer__c object is available for update
            if (Schema.SObjectType.Stripe_Customer__c.fields.Stripe_Customer_ID__c.isUpdateable()) {
                try {
                    update as user customer;
                } catch (Exception ex) {
                    System.debug('Error occured while updating Stripe Customer record: ' + ex.getMessage());
                }
            } else {
                throw new SecurityException('Stripe_Customer_ID__c field of Stripe_Customer__c is not available for update');
            }
        } else {
            throw new SecurityException('Stripe_Customer__c object is not available for update');
        }
    }
}