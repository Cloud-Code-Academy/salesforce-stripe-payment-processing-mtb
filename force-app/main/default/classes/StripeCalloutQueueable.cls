/**
 * @description Queueable class for executing asynchronous Stripe API callouts. Supports creating customers, products,
 *              subscriptions, and checkout sessions with proper chaining of dependent operations. Implements security
 *              checks for object and field-level permissions before performing DML operations.
 */
public class StripeCalloutQueueable implements Queueable, Database.AllowsCallouts{
    public static final String CREATE_CUSTOMER = 'create_customer';
    public static final String CREATE_PRODUCT = 'create_product';
    public static final String CREATE_SUBSCRIPTION = 'create_subscription';
    public static final String CREATE_SESSION = 'create_session';

    private String calloutType;
    private Id recordId;
    private String currencyName;
    private String recurringInterval;
    private Decimal amount;
    private String product;
    private String priceId;
    private String customerId;
    private String defaultMethodId;
    private StripeWrapper.CustomerWrapper customerWrapper;
    private StripeWrapper.ProductWrapper productWrapper;
    /**
     * @description Constructor for customer creation callouts. Initializes the queueable job to create a Stripe customer
     *              using the provided contact information.
     * @param recordId Salesforce record ID of the Stripe_Customer__c record to update after creation
     * @param customerName Full name of the customer
     * @param customerEmail Email address of the customer
     * @param customerPhone Phone number of the customer
     */
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
    /**
     * @description Constructor for product and price creation callouts. Initializes the queueable job to create a Stripe
     *              product and its associated recurring price.
     * @param recordId Salesforce record ID of the Pricing_Plan__c record to update after creation
     * @param currencyName Currency code for the price (e.g., 'USD', 'EUR')
     * @param recurringInterval Billing interval for recurring price (e.g., 'month', 'year')
     * @param amount Price amount in the smallest currency unit (e.g., cents)
     * @param product Product name/description
     */
    public StripeCalloutQueueable(
        Id recordId,
        String currencyName,
        String recurringInterval,
        Decimal amount,
        String product

    ){
        this.calloutType = CREATE_PRODUCT;
        this.recordId = recordId;
        this.currencyName = currencyName;
        this.recurringInterval = recurringInterval;
        this.amount = amount;
        this.productWrapper = new StripeWrapper.ProductWrapper(product);
    }
    /**
     * @description Constructor for subscription creation callouts. Initializes the queueable job to create a Stripe
     *              subscription with the specified customer, price, and payment method.
     * @param customerId Stripe customer ID to associate with the subscription
     * @param recordId Salesforce record ID of the Stripe_Subscription__c record to update after creation
     * @param priceId Stripe price ID for the subscription
     * @param defaultMethodId Stripe payment method ID to use for the subscription
     */
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
    /**
     * @description Constructor for checkout session creation callouts. Initializes the queueable job to create a Stripe
     *              Checkout Session for subscription payment.
     * @param customerId Stripe customer ID for the checkout session
     * @param priceId Stripe price ID for the subscription line item
     * @param recordId Salesforce record ID of the Stripe_Subscription__c record to update with session details
     */
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
    /**
     * @description Executes the queueable job based on the callout type. Routes to the appropriate Stripe API operation
     *              (customer, product/price, subscription, or checkout session creation) and handles subsequent record
     *              updates or chained callouts. Includes comprehensive error logging for all operations.
     * @param context QueueableContext provided by the platform
     */
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
                if (productId != null || Test.isRunningTest()) {
                    String requestBody = 'currency=' + EncodingUtil.urlEncode(currencyName, 'UTF-8') +
                                            '&recurring[interval]=' + EncodingUtil.urlEncode(recurringInterval.toLowerCase(), 'UTF-8') +
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
    /**
     * @description Updates a Stripe_Customer__c record with the Stripe customer ID returned from a successful API callout.
     *              Enforces object-level and field-level security before performing the update operation.
     * @param recordId Salesforce ID of the Stripe_Customer__c record to update
     * @param customerId Stripe customer ID to store in the record
     */
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
                    Logger.error('Error occurred while updating Stripe Customer record: ', ex);
                    Logger.saveLog();
                }
            } else {
                throw new SecurityException('Stripe_Customer_ID__c field of Stripe_Customer__c is not available for update');
            }
        } else {
            throw new SecurityException('Stripe_Customer__c object is not available for update');
        }
    }
    /**
     * @description Updates a Stripe_Subscription__c record with the Stripe subscription ID and synced status after
     *              successful subscription creation. Enforces object-level and field-level security before performing
     *              the update operation.
     * @param recordId Salesforce ID of the Stripe_Subscription__c record to update
     * @param subscriptionId Stripe subscription ID to store in the record
     */
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
                    Logger.error('Error occurred while updating Stripe_Subscription__c record: ', ex);
                    Logger.saveLog();
                }
            } else {
                throw new SecurityException('Stripe_Subscription_ID__c/Sync_Status__c field of Stripe_Subscription__c is not available for update');
            }
        }else {
            throw new SecurityException('Stripe_Subscription__c object is not available for update');
        }
    }
    /**
     * @description Updates a Stripe_Subscription__c record with checkout session details (session ID, checkout URL, and
     *              status) after successful session creation. Enforces object-level and field-level security before
     *              performing the update operation.
     * @param recordId Salesforce ID of the Stripe_Subscription__c record to update
     * @param stripeResponse Wrapper object containing session data from Stripe API response
     */
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
                    Logger.error('Error occurred while updating Stripe_Subscription__c record: ', ex);
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