public class StripeChainedCalloutQueueable implements Queueable, Database.AllowsCallouts{
    public static final String CREATE_PRICING_PLAN = 'create_pricing_plan';
    public static final String CREATE_DEFAULT_METHOD = 'create_default_method';

    private String calloutType;
    private Id recordId;
    private String requestBody;
    private String customerId;
    public StripeChainedCalloutQueueable(
        Id recordId,
        String requestBody

    ){
        this.calloutType = CREATE_PRICING_PLAN;
        this.recordId = recordId;
        this.requestBody = requestBody;
    }
    public StripeChainedCalloutQueueable(
        String customerId,
        Id recordId
    ){
        this.calloutType = CREATE_DEFAULT_METHOD;
        this.customerId = customerId;
        this.recordId = recordId;
    }
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
                String defaultMethodId = StripeAPIService.createDefaultMethod(customerId);
                if (defaultMethodId != null) {
                    updateCustomer(recordId, defaultMethodId);
                    System.enqueueJob(new StripeFinalCalloutQueueable(customerId, defaultMethodId));
                }
            } catch (Exception ex) {
                 Logger.error('Failed to get defaultMethodId/update Stripe Customer record: ', ex);
                Logger.saveLog();
            }
        }
    }
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
    private void updateCustomer(Id recordId, String defaultMethodId){
        Stripe_Customer__c customer = new Stripe_Customer__c(
            Id = recordId,
            Default_Payment_Method__c = defaultMethodId
        );
        //Check whether Stripe_Customer__c object is available for update
        if (Schema.SObjectType.Stripe_Customer__c.isUpdateable()) {
            //Check whether Stripe_Customer_ID__c field of Stripe_Customer__c object is available for update
            if (Schema.SObjectType.Stripe_Customer__c.fields.Default_Payment_Method__c.isUpdateable()) {
                try {
                    update as user customer;
                } catch (Exception ex) {
                    Logger.error('Error occured while updating Stripe Customer record: ', ex);
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