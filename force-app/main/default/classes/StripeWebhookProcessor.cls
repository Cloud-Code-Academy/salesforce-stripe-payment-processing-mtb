public class StripeWebhookProcessor implements IWebhookProcessor{
    // Constants for webhook event types
    private static final String EVENT_CUSTOMER_UPDATED = 'customer.updated';
    private static final String EVENT_CHECKOUT_SESSION_COMPLETED = 'checkout.session.completed';
    private static final String EVENT_PAYMENT_INTENT_SUCCEEDED = 'payment_intent.succeeded';
    private static final String EVENT_PAYMENT_INTENT_PAYMENT_FAILED = 'payment_intent.payment_failed';
    private static final String EVENT_CUSTOMER_SUBSCRIPTION_UPDATED = 'customer.subscription.updated';
    private static final String EVENT_CUSTOMER_SUBSCRIPTION_DELETED = 'customer.subscription.deleted';

    public Boolean validate(RestRequest request){
        Boolean valid;
        try {
            String requestBody = request.requestBody.toString();
            Map<String, Object> payload = (Map<String,Object>)JSON.deserializeUntyped(requestBody);
            if (payload.containsKey('webhookEvent')) {
                valid = true;
            }
        } catch (Exception ex) {
            Logger.error('Failed to deserialize JSON: ', ex);
            Logger.saveLog();
        }
        return valid;
    }
    public void process(RestRequest request){
        try {
            String requestBody = request.requestBody.toString();
            Map<String,Object> payload = (Map<String, Object>)JSON.deserializeUntyped(requestBody);
            String webhookEvent = (String)payload.get('webhookEvent');
            if (webhookEvent == EVENT_CUSTOMER_UPDATED) {
                processCustomerUpdated(payload);
            } else if (webhookEvent == EVENT_CHECKOUT_SESSION_COMPLETED) {
                processCheckoutSessionCompleted(payload);
            } else if (webhookEvent == EVENT_PAYMENT_INTENT_SUCCEEDED) {
                processPaymentIntentSucceeded(payload);
            } else if (webhookEvent == EVENT_PAYMENT_INTENT_PAYMENT_FAILED) {
                processPaymentIntentPaymentFailed(payload);
            } else if (webhookEvent == EVENT_CUSTOMER_SUBSCRIPTION_UPDATED) {
                processCustomerSubscriptionUpdated(payload);
            } else if (webhookEvent == EVENT_CUSTOMER_SUBSCRIPTION_DELETED) {
                processCustomerSubscriptionDeleted(payload);
            }
        } catch (Exception ex) {
            Logger.error('Error while processing webhook: ', ex);
        }
    }
    private void processCustomerUpdated(Map<String, Object> payload){
        try {
            Map<String, Object> customerData = (Map<String, Object>)payload.get('object');
            String customerId = (String)customerData.get('id');
            List<Stripe_Customer__c> customersList = [
                                                        SELECT Id 
                                                        FROM Stripe_Customer__c 
                                                        WHERE Stripe_Customer_ID__c =: customerId
                                                        ];
            Stripe_Customer__c customerForUpsert = upsertCustomerRecord(customersList[0], customerData);
            upsert customerForUpsert;
        } catch (Exception ex) {
            Logger.error('Error while upserting Stripe_Customer__c: ', ex);
            Logger.saveLog();
        }
    }
    private void processCheckoutSessionCompleted(Map<String, Object> payload){
        try {
            Map<String, Object> sessionData = (Map<String, Object>)payload.get('object');
            String sessionId = (String)sessionData.get('id');
            List<Stripe_Subscription__c> subscriptionsList = [
                                                                SELECT Status__c
                                                                FROM Stripe_Subscription__c
                                                                WHERE Stripe_Checkout_Session_ID__c =: sessionId
                                                                ];
            subscriptionsList[0].Status__c = 'active';
            update subscriptionsList[0];
        } catch (Exception ex) {
            Logger.error('Error while upserting Stripe_Subscription__c: ', ex);
            Logger.saveLog();
        }
    }
    private void processPaymentIntentSucceeded(Map<String, Object> payload){
        try {
            Map<String, Object> paymentData = (Map<String, Object>)payload.get('object');
            Payment_Transaction__c paymentForInsert = createPaymentTransaction(paymentData);
            insert paymentForInsert;
        } catch (Exception ex) {
            Logger.error('Error while inserting Payment_Transaction__c: ', ex);
            Logger.saveLog();
        } 
    }
    private void processPaymentIntentPaymentFailed(Map<String, Object> payload){
        try {
            Map<String, Object> paymentData = (Map<String, Object>)payload.get('object');
             Logger.warn('Payment Intent Failed: ', JSON.serializePretty(paymentData));
            Logger.saveLog();
        } catch (Exception ex) {
            Logger.error('Error while logging failed Payment_Transaction__c: ', ex);
            Logger.saveLog();
        }
        Map<String, Object> paymentData = (Map<String, Object>)payload.get('object');
    }
    private void processCustomerSubscriptionUpdated(Map<String, Object> payload){
        try {
            Map<String, Object> subscriptionData = (Map<String, Object>)payload.get('object');
            String subscriptionId = (String)subscriptionData.get('id');
            Stripe_Subscription__c existingSubscripton = [SELECT Id 
                                                            FROM Stripe_Subscription__c 
                                                            WHERE Stripe_Subscription_ID__c =: subscriptionId LIMIT 1
                                                            ];
            Stripe_Subscription__c subscriptionForUpdate = updateSubscription(existingSubscripton.Id, subscriptionData);
            update subscriptionForUpdate;
        } catch (Exception ex) {
            Logger.error('Error while updating Stripe_Subscription__c: ', ex);
            Logger.saveLog();
        }
        
    }
    private void processCustomerSubscriptionDeleted(Map<String, Object> payload){
        Map<String, Object> subscriptionData = (Map<String, Object>)payload.get('object');
        String subscriptionId = (String)subscriptionData.get('id');
        Stripe_Subscription__c existingSubscripton = [SELECT Id 
                                                        FROM Stripe_Subscription__c 
                                                        WHERE Stripe_Subscription_ID__c =: subscriptionId LIMIT 1
                                                        ];
        existingSubscripton.Status__c = 'canceled';
        update existingSubscripton;
    }

    private Stripe_Customer__c upsertCustomerRecord(
        Stripe_Customer__c existingCustomer, 
        Map<String, Object> customerData
        ){
        String customerId = (String)customerData.get('id');
        String email = (String)customerData.get('email');
        String phone = (String)customerData.get('phone');
        Stripe_Customer__c updatedCustomer = new Stripe_Customer__c(
            Id = existingCustomer.Id,
            Customer_Email__c = email,
            Customer_Phone__c = phone
        );
        return updatedCustomer;
    }
    private Payment_Transaction__c createPaymentTransaction(Map<String, Object> paymentData){
        String paymentId = (String)paymentData.get('id');
        Integer amount = (Integer)paymentData.get('amount');
        String currencyName = (String)paymentData.get('currency');
        String paymentMethodTypeName = (String)paymentData.get('payment_method_types[0]');
        String statusName = (String)paymentData.get('status');
        Long created = (Integer)paymentData.get('created');
        String customerId = (String)paymentData.get('customer');
        DateTime createdDateTime = DateTime.newInstance(created * 1000);


        Stripe_Customer__c customer = [SELECT Id 
                                        FROM Stripe_Customer__c 
                                        WHERE Stripe_Customer_ID__c =: customerId LIMIT 1
                                        ];
        Stripe_Subscription__c subscription = [SELECT Id 
                                                FROM Stripe_Subscription__c 
                                                WHERE Stripe_Customer__c =: customer.Id LIMIT 1
                                                ];
        Payment_Transaction__c payment = new Payment_Transaction__c(
            Amount__c = amount,
            Currency__c = currencyName,
            Payment_Method_Type__c = paymentMethodTypeName,
            Status__c = statusName,
            Stripe_Payment_Intent_ID__c = paymentId,
            Transaction_Date__c = createdDateTime,
            Stripe_Customer__c = customer.Id,
            Stripe_Subscription__c = subscription.Id
        );
        return payment;
    }
    private Stripe_Subscription__c updateSubscription(Id recordId, Map<String, Object> subscriptionData){
        String subscriptionId = (String)subscriptionData.get('id');
        String currencyName = (String)subscriptionData.get('currency');
        Map<String, Object> planData = (Map<String, Object>)subscriptionData.get('plan');
        String priceId = (String)planData.get('id');
        Integer amount = (Integer)planData.get('amount');
        Stripe_Subscription__c subscriptionForUpdate = new Stripe_Subscription__c(
            Id = recordId,
            Amount__c = amount,
            Currency__c = currencyName,
            Stripe_Price_ID__c = priceId
        );
        return subscriptionForUpdate;
    }
}