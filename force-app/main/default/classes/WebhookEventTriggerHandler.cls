/**
 * @description Handler class for processing Stripe webhook events received via Platform Events.
 *              Processes various Stripe events including customer updates, checkout sessions,
 *              payment intents, and subscription changes.
 */
public class WebhookEventTriggerHandler {

    // Constants for webhook event types
    private static final String EVENT_CUSTOMER_UPDATED = 'customer.updated';
    private static final String EVENT_CHECKOUT_SESSION_COMPLETED = 'checkout.session.completed';
    private static final String EVENT_PAYMENT_INTENT_SUCCEEDED = 'payment_intent.succeeded';
    private static final String EVENT_PAYMENT_INTENT_PAYMENT_FAILED = 'payment_intent.payment_failed';
    private static final String EVENT_CUSTOMER_SUBSCRIPTION_UPDATED = 'customer.subscription.updated';
    private static final String EVENT_CUSTOMER_SUBSCRIPTION_DELETED = 'customer.subscription.deleted';
    /**
     * @description Trigger handler for after insert context on WebhookEvent__e platform events
     * @param newList List of newly inserted webhook event records
     */
    public static void afterInsert(List<WebhookEvent__e> newList){
        processWebhookRecords(newList);
    }
    /**
     * @description Main processing method that routes webhook events to appropriate handlers
     *              based on event type. Deserializes JSON payload and delegates to specific methods.
     * @param newList List of webhook event platform event records to process
     */
    public static void processWebhookRecords(List<WebhookEvent__e> newList){
        try {
            for (WebhookEvent__e event : newList) {
                // Deserialize the JSON payload, replacing reserved keywords to avoid conflicts
                StripeWebhookWrapper payload = (
                                                StripeWebhookWrapper)JSON.deserialize(
                                                event.Payload__c.toString().replace('object', 'object_x')
                                                .replace('currency', 'currency_x'), 
                                                StripeWebhookWrapper.class
                                                );
                // Route to appropriate handler based on event type
                if (event.EventType__c == EVENT_CUSTOMER_UPDATED) {
                    processCustomerUpsert(payload);
                } else if (event.EventType__c == EVENT_CHECKOUT_SESSION_COMPLETED) {
                    processCheckoutSessionCompleted(payload);
                } else if (event.EventType__c == EVENT_PAYMENT_INTENT_SUCCEEDED
                            || event.EventType__c == EVENT_PAYMENT_INTENT_PAYMENT_FAILED) {
                    upsertPaymentTransaction(payload);
                } else if (event.EventType__c == EVENT_CUSTOMER_SUBSCRIPTION_UPDATED
                            || event.EventType__c == EVENT_CUSTOMER_SUBSCRIPTION_DELETED) {
                    updateSubscription(payload);
                }
            }
        } catch (Exception ex) {
            Logger.error('Error while processing customer: ', ex);
            Logger.saveLog();
        }
    }
    /**
     * @description Processes customer.updated webhook events from Stripe.
     *              Creates or updates Stripe_Customer__c records with customer information.
     * @param payload Deserialized Stripe webhook payload containing customer data
     */
    private static void processCustomerUpsert(StripeWebhookWrapper payload){
        try {
            // Extract customer data from webhook payload
            String webhookCustomerId = payload.data.object_x.id;
            String webhookCustomerEmail = payload.data.object_x.email;
            String webhookCustomerPhone = payload.data.object_x.phone;
            String webhookCustomerName = payload.data.object_x.name;

            // Check FLS for Stripe_Customer__c fields
            if (!Schema.sObjectType.Stripe_Customer__c.isCreateable() || 
                !Schema.sObjectType.Stripe_Customer__c.isUpdateable()) {
                throw new SecurityException('Insufficient permissions to create/update Stripe_Customer__c');
            }
            // Build customer record for upsert
            Stripe_Customer__c customer = new Stripe_Customer__c();
            customer.Stripe_Customer_ID__c = webhookCustomerId;
            if (String.isNotBlank(webhookCustomerEmail)) {
                customer.Customer_Email__c = webhookCustomerEmail;
            } 
            if (String.isNotBlank(webhookCustomerPhone)) {
                customer.Customer_Phone__c = webhookCustomerPhone;
            }
            if (String.isNotBlank(webhookCustomerName)) {
                customer.Customer_Name__c = webhookCustomerName;
            }
            // Upsert using external ID field
            upsert customer Stripe_Customer_ID__c;
            
        } catch (Exception ex) {
            Logger.error('Error while populating Stripe_Customer__c: ', ex);
            Logger.saveLog();
        }
    }
    /**
     * @description Processes checkout.session.completed webhook events from Stripe.
     *              Updates existing subscription records with checkout session data.
     * @param payload Deserialized Stripe webhook payload containing checkout session data
     */
    private static void processCheckoutSessionCompleted(StripeWebhookWrapper payload){
        try {
            // Extract checkout session data
            String sessionId = payload.data.object_x.id;
            String invoiceId = payload.data.object_x.invoice;
            String subscriptionId = payload.data.object_x.subscription;
            // Check FLS for Stripe_Subscription__c
            if (!Schema.sObjectType.Stripe_Subscription__c.isUpdateable()) {
                throw new SecurityException('Insufficient permissions to update Stripe_Subscription__c');
            }
            // Query for existing subscription record by checkout session ID
            List<Stripe_Subscription__c> existingSubscriptionRecords = [
                                                                    SELECT Stripe_Subscription_ID__c 
                                                                    FROM Stripe_Subscription__c 
                                                                    WHERE Stripe_Checkout_Session_ID__c =: sessionId
                                                                    ];
            Stripe_Subscription__c subscription = new Stripe_Subscription__c();
            // Update existing record if found
            if (!existingSubscriptionRecords.isEmpty()) {
                subscription.Id = existingSubscriptionRecords[0].Id;   
            }
            if (subscriptionId != null) {
                subscription.Stripe_Subscription_ID__c = subscriptionId;    
            }
            // Mark subscription as active after successful checkout
            subscription.Status__c = 'active';
            if(invoiceId != null){
                subscription.StripeInvoiceId__c = invoiceId;
            }
            update subscription;
        } catch (Exception ex) {
            Logger.error('Error while upserting Stripe_Subscription__c: ', ex);
            Logger.saveLog();
        }
    }
    /**
     * @description Processes payment_intent.succeeded and payment_intent.payment_failed webhook events.
     *              Creates or updates Payment_Transaction__c records with payment details.
     * @param paymentData Deserialized Stripe webhook payload containing payment intent data
     */
    private static void upsertPaymentTransaction(StripeWebhookWrapper paymentData){
        try {
            // Extract payment intent data
            String paymentId = paymentData.data.object_x.id;
            Integer amount = paymentData.data.object_x.amount;
            String currencyName = paymentData.data.object_x.currency_x;
            String paymentMethodTypeName = paymentData.data.object_x.payment_method_types[0];
            String statusName = paymentData.data.object_x.status;
            Long created = paymentData.data.object_x.created;
            DateTime createdDateTime = DateTime.newInstance(created * 1000);
            String customerId = paymentData.data.object_x.customer;
            String orderReference = paymentData.data.object_x.payment_details.order_reference + '%';
            // Check FLS for Payment_Transaction__c
            if (!Schema.sObjectType.Payment_Transaction__c.isCreateable() || 
                !Schema.sObjectType.Payment_Transaction__c.isUpdateable()) {
                throw new SecurityException('Insufficient permissions to create/update Payment_Transaction__c');
            }
            List<Stripe_Customer__c> customers;
            List<Stripe_Subscription__c> subscriptions;
            // Query for related customer record
            if (customerId != null) {
                customers = [
                            SELECT Id 
                            FROM Stripe_Customer__c 
                            WHERE Stripe_Customer_ID__c =: customerId
                            ];
            }
            // Query for related subscription using order reference
            if (orderReference != null) {
                subscriptions = [
                                SELECT Id 
                                FROM Stripe_Subscription__c 
                                WHERE Stripe_Checkout_Session_ID__c 
                                LIKE: orderReference
                                ];
            }
            // Build payment transaction record
            Payment_Transaction__c payment = new Payment_Transaction__c();
            // Convert from cents to dollars
            payment.Amount__c = amount != null ? (amount/100) : 0;
            payment.Currency__c = currencyName != null ? currencyName : 'usd';
            if (paymentMethodTypeName != null) {
                payment.Payment_Method_Type__c = paymentMethodTypeName;    
            }
            payment.Status__c = statusName;
            payment.Stripe_Payment_Intent_ID__c = paymentId;
            payment.Transaction_Date__c = createdDateTime;
            // Link to customer if found
            if (!customers.isEmpty()) {
                payment.Stripe_Customer__c = customers[0].Id;    
            }
            // Link to subscription if found
            if (!subscriptions.isEmpty()) {
                payment.Stripe_Subscription__c = subscriptions[0].Id;    
            }
            // Upsert using external ID field
            upsert payment Stripe_Payment_Intent_ID__c;
        } catch (Exception ex) {
            Logger.error('Error while upserting Payment_Transaction__c: ', ex);
            Logger.saveLog();
        }
    }
    /**
     * @description Processes customer.subscription.updated and customer.subscription.deleted webhook events.
     *              Creates or updates Stripe_Subscription__c records with subscription details.
     * @param subsriptionData Deserialized Stripe webhook payload containing subscription data
     */
    private static void updateSubscription(StripeWebhookWrapper subsriptionData){
        try {
            // Extract subscription data
            String subscriptionId = subsriptionData.data.object_x.id;
            Integer amount = subsriptionData.data.object_x.items.data[0].plan.amount; //in cents
            String currencyName = subsriptionData.data.object_x.currency_x;
            Long currentPeriodEnd = subsriptionData.data.object_x.items.data[0].current_period_end;
            DateTime currentPeriodEndDateTime = DateTime.newInstance(currentPeriodEnd * 1000);
            Long currentPeriodStart = subsriptionData.data.object_x.items.data[0].current_period_start;
            DateTime currentPeriodStartDateTime = DateTime.newInstance(currentPeriodStart * 1000);
            String statusName = subsriptionData.data.object_x.status;
            // Check FLS for Stripe_Subscription__c
            if (!Schema.sObjectType.Stripe_Subscription__c.isCreateable() || 
                !Schema.sObjectType.Stripe_Subscription__c.isUpdateable()) {
                throw new SecurityException('Insufficient permissions to create/update Stripe_Subscription__c');
            }
            // Build subscription record
            Stripe_Subscription__c subscription = new Stripe_Subscription__c();
            subscription.Stripe_Subscription_ID__c = subscriptionId;
            // Convert from cents to dollars
            subscription.Amount__c = amount != null ? (amount/100) : 0;
            subscription.Currency__c = currencyName != null ? currencyName : 'usd';
            if (statusName != null) {
                subscription.Status__c = statusName;    
            }
            if (currentPeriodEndDateTime != null) {
                subscription.Current_Period_End__c = currentPeriodEndDateTime;
            }
            if (currentPeriodStartDateTime != null) {
                subscription.Current_Period_Start__c = currentPeriodStartDateTime;
            }
            // Upsert using external ID field
            upsert subscription Stripe_Subscription_ID__c;
        } catch (Exception ex) {
            Logger.error('Error while upserting Payment_Transaction__c: ', ex);
            Logger.saveLog();
        }
    }
    public class SecurityException extends Exception {}
}