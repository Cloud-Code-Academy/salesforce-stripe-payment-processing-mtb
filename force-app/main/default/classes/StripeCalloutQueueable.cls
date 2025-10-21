/**
 * Queueable class to make asynchronous callouts to Stripe API
 */
public class StripeCalloutQueueable implements Queueable, Database.AllowsCallouts{
    public static final String CREATE_CUSTOMER = 'create_customer';
    public static final String CREATE_PRODUCT = 'create_product';
    public static final String CREATE_SUBSCRIPTION = 'create_subscription';
    public static final String CREATE_SESSION = 'create_session';

    private String calloutType;
    private Id recordId;
    private String currencyName;
    private String reccuringInterval;
    private Decimal amount;
    private String product;
    private String priceId;
    private String customerId;
    private String defaultMethodId;
    private StripeWrapper.CustomerWrapper customerWrapper;
    private StripeWrapper.ProductWrapper productWrapper;

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
    public StripeCalloutQueueable(
        Id recordId,
        String currencyName,
        String reccuringInterval,
        Decimal amount,
        String product

    ){
        this.calloutType = CREATE_PRODUCT;
        this.recordId = recordId;
        this.currencyName = currencyName;
        this.reccuringInterval = reccuringInterval;
        this.amount = amount;
        this.productWrapper = new StripeWrapper.ProductWrapper(product);
    }
    public StripeCalloutQueueable(
        String customerId,
        Id recordId,
        String priceId,
        String defaultMethodId
    ){
        this.calloutType = CREATE_SUBSCRIPTION;
        this.customerId = customerId;
        this.recordId = recordId;
        this.priceId = priceId;
        this.defaultMethodId = defaultMethodId;
    }
    public StripeCalloutQueueable(
        String customerId,
        String priceId,
        Id recordId
    ){
        this.calloutType = CREATE_SESSION;
        this.customerId = customerId;
        this.priceId = priceId;
        this.recordId = recordId;
    }

    public void execute(QueueableContext context){
        // Run Create Customer path
        if (calloutType == CREATE_CUSTOMER) {
            try {
                String customerId = StripeAPIService.createCustomer(customerWrapper);
                updateStripeCustomer(recordId, customerId);
                if (customerId != null) {
                    System.enqueueJob(new StripeChainedCalloutQueueable(customerId, recordId));
                }
            } catch (Exception ex) {
                Logger.error('Failed to get customerId/update Stripe Customer record: ', ex);
                Logger.saveLog();
            }
        } else if (calloutType == CREATE_PRODUCT) {
            try {
                String productId = StripeAPIService.createProduct(productWrapper);
                if (productId != null) {
                    String requestBody = 'currency=' + EncodingUtil.urlEncode(currencyName, 'UTF-8') +
                                            '&recurring[interval]=' + EncodingUtil.urlEncode(reccuringInterval.toLowerCase(), 'UTF-8') +
                                            '&unit_amount=' + String.valueOf(amount.longValue()) +
                                            '&product=' + EncodingUtil.urlEncode(productId, 'UTF-8');
                    System.enqueueJob(new StripeChainedCalloutQueueable(recordId, requestBody));
                }
            } catch (Exception ex) {
                Logger.error('Failed to get productId: ', ex);
                Logger.saveLog();
            }
        } else if (calloutType == CREATE_SUBSCRIPTION) {
            try {
                String subscriptionId = StripeAPIService.createSubscription(customerId, priceId, defaultMethodId);
                updateStripeSubscription(recordId, subscriptionId);
            } catch (Exception ex) {
                Logger.error('Failed to get subscriptionId/update Stripe Subscription record: ', ex);
                Logger.saveLog();
            }
        } else if (calloutType == CREATE_SESSION) {
            try {
                StripeWrapper stripeResponse = StripeAPIService.createSession(customerId, priceId);
                updateStripeSubscriptionWithSessionData(recordId, stripeResponse);
            } catch (Exception ex) {
                Logger.error('Failed to get subscriptionId/update Stripe Subscription record: ', ex);
                Logger.saveLog();
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
                    Logger.error('Error occured while updating Stripe Customer record: ', ex);
                    Logger.saveLog();
                }
            } else {
                throw new SecurityException('Stripe_Customer_ID__c field of Stripe_Customer__c is not available for update');
            }
        } else {
            throw new SecurityException('Stripe_Customer__c object is not available for update');
        }
    }
    private void updateStripeSubscription(Id recordId, String subscriptionId){
        Stripe_Subscription__c subscription = new Stripe_Subscription__c(
            Id = recordId,
            Stripe_Subscription_ID__c = subscriptionId, 
            Sync_Status__c = 'Synced'
        );
        if (Schema.SObjectType.Stripe_Subscription__c.isUpdateable()){
            if (Schema.SObjectType.Stripe_Subscription__c.fields.Stripe_Subscription_ID__c.isUpdateable()
                && Schema.SObjectType.Stripe_Subscription__c.fields.Sync_Status__c.isUpdateable()){
                try {
                    update as user subscription;
                } catch (Exception ex) {
                    Logger.error('Error occured while updating Stripe Customer record: ', ex);
                    Logger.saveLog();
                }
            } else {
                throw new SecurityException('Stripe_Subscription_ID__c/Sync_Status__c field of Stripe_Subscription__c is not available for update');
            }
        }else {
            throw new SecurityException('Stripe_Subscription__c object is not available for update');
        }
    }
    private void updateStripeSubscriptionWithSessionData(Id recordId, StripeWrapper stripeResponse){
        Stripe_Subscription__c subscription = new Stripe_Subscription__c(
            Id = recordId,
            Checkout_URL__c = stripeResponse.url,
            Stripe_Checkout_Session_ID__c = stripeResponse.id,
            Sync_Status__c = 'Checkout Created'
        );
        if (Schema.SObjectType.Stripe_Subscription__c.isUpdateable()){
            if (Schema.SObjectType.Stripe_Subscription__c.fields.Checkout_URL__c.isUpdateable()
                && Schema.SObjectType.Stripe_Subscription__c.fields.Stripe_Checkout_Session_ID__c.isUpdateable()
                && Schema.SObjectType.Stripe_Subscription__c.fields.Sync_Status__c.isUpdateable()){
                try {
                    update as user subscription;
                } catch (Exception ex) {
                    Logger.error('Error occured while updating Stripe Customer record: ', ex);
                    Logger.saveLog();
                }
            } else {
                throw new SecurityException('Checkout_URL__c/Stripe_Checkout_Session_ID__c/Sync_Status__c field of Stripe_Subscription__c is not available for update');
            }
        }else {
            throw new SecurityException('Stripe_Subscription__c object is not available for update');
        }
    }
}