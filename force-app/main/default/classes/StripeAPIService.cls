public with sharing class StripeAPIService {
    private static final String API_NAMED_CREDENTIALS = 'callout:StripeAPI';
    private static final String CUSTOMER_ENDPOINT = '/v1/customers';
    private static final String PAYMENT_ENDPOINT = '/v1/payment_methods';
    private static final String PRICE_ENDPOINT = '/v1/prices';
    private static final String PRODUCT_ENDPOINT = '/v1/products';
    private static final String SUBSCRIPTION_ENDPOINT = '/v1/subscriptions';
    private static final String SESSION_ENDPOINT = '/v1/checkout/sessions';

    /**
     * @description Creates a new customer in Stripe via API callout and returns the generated Stripe customer ID.
     *              Constructs a URL-encoded request body with customer details (name, email, phone), sends it to the
     *              Stripe Customer API endpoint, and parses the response to extract the customer ID. Logs errors if
     *              the callout fails or returns a non-200 status code.
     * @param customerWrapper Wrapper object containing customer information (name, email, phone)
     * @return String The Stripe customer ID if successful, null if an error occurs
     */
    public static String createCustomer(StripeWrapper.CustomerWrapper customerWrapper){
        String customerId;
        try {
            String endPoint = API_NAMED_CREDENTIALS + CUSTOMER_ENDPOINT;
            String requestBody = 'name=' + EncodingUtil.urlEncode(customerWrapper.name, 'UTF-8') +
                                    '&email=' + EncodingUtil.urlEncode(customerWrapper.email, 'UTF-8') +
                                    '&phone=' + EncodingUtil.urlEncode(customerWrapper.phone, 'UTF-8');
            
            HttpResponse res = makeCallout(endPoint, requestBody);
            // If the HTTP response code is successful, parse the JSON response and Id of created Stripe Customer
            if (res.getStatusCode() == 200) {
                StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody().toString(), StripeWrapper.class);
                customerId = stripeResponse.id;
            } 
            // If the HTTP response code is not successful, throw StripeException
            throw new StripeException(); 
        } catch (Exception ex) {
            // If the error occured when code was generating HttpRequest
            Logger.error('Failed to generate HttpRequest: ', ex);
            Logger.saveLog();
        }
        return customerId;
    }
    /**
     * @description Creates a new price in Stripe via API callout and returns the generated Stripe price ID.
     *              Sends a pre-formatted request body to the Stripe Price API endpoint and parses the response
     *              to extract the price ID. Logs errors if the callout fails or encounters issues during execution.
     * @param requestBody URL-encoded string containing price configuration parameters for Stripe API
     * @return String The Stripe price ID if successful, null if an error occurs
     */
    public static String createPrice(String requestBody){
        String priceId;
        try {
            String endPoint = API_NAMED_CREDENTIALS + PRICE_ENDPOINT;
            HttpResponse res = makeCallout(endPoint, requestBody);
            if (res.getStatusCode() == 200) {
                StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody().toString(), StripeWrapper.class);
                priceId = stripeResponse.id;
            }
            //throw new StripeException();
        } catch (Exception ex) {
            Logger.error('Failed to generate HttpRequest: ', ex);
            Logger.saveLog();
        }
        return priceId;
    }
    /**
     * @description Creates a new product in Stripe via API callout and returns the generated Stripe product ID.
     *              Constructs a URL-encoded request body with the product name, sends it to the Stripe Product API
     *              endpoint, and parses the response to extract the product ID. Logs errors if the callout fails
     *              or encounters issues during execution.
     * @param productWrapper Wrapper object containing product information (name)
     * @return String The Stripe product ID if successful, null if an error occurs
     */
    public static String createProduct(StripeWrapper.ProductWrapper productWrapper){
        String productId;
        try {
            String endPoint = API_NAMED_CREDENTIALS + PRODUCT_ENDPOINT;
            String requestBody = 'name=' + EncodingUtil.urlEncode(productWrapper.name, 'UTF-8');
            HttpResponse res = makeCallout(endPoint, requestBody);
            if (res.getStatusCode() == 200) {
                StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody().toString(), StripeWrapper.class);
                productId = stripeResponse.id;
            }
            //throw new StripeException();
        } catch (Exception ex) {
            Logger.error('Failed to generate HttpRequest: ', ex);
            Logger.saveLog();
        }
        return productId;
    }
    /**
     * @description Creates a new subscription in Stripe via API callout and returns the generated Stripe subscription ID.
     *              Constructs a URL-encoded request body with customer ID, price ID, and default payment method, sends it
     *              to the Stripe Subscription API endpoint, and parses the response to extract the subscription ID. Logs
     *              errors if the callout fails or encounters issues during execution.
     * @param customerId The Stripe customer ID to associate with the subscription
     * @param priceId The Stripe price ID for the subscription item
     * @param defaultMethodId The Stripe payment method ID to use as default for the subscription
     * @return String The Stripe subscription ID if successful, null if an error occurs
     */
    public static String createSubscription(String customerId, String priceId, String defaultMethodId){
        String subscriptionId;
        try {
            String endPoint = API_NAMED_CREDENTIALS + SUBSCRIPTION_ENDPOINT;
            String requestBody = 'customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8') +
                             '&items[0][price]=' + EncodingUtil.urlEncode(priceId, 'UTF-8') + 
                             '&default_payment_method=' + EncodingUtil.urlEncode(defaultMethodId, 'UTF-8');
            HttpResponse res = makeCallout(endPoint, requestBody);
            if (res.getStatusCode() == 200) {
                StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody().toString(), StripeWrapper.class);
                subscriptionId = stripeResponse.id;
            }
        } catch (Exception ex) {
            Logger.error('Failed to generate HttpRequest: ', ex);
            Logger.saveLog();
        }
        return subscriptionId;
    }
    /**
     * @description Creates a default payment method in Stripe via API callout and returns the generated payment method ID.
     *              Constructs a URL-encoded request body with a test card token ('tok_visa'), sends it to the Stripe
     *              Payment Method API endpoint, and parses the response to extract the payment method ID. Logs errors
     *              if the callout fails or encounters issues during execution.
     * @param customerId The Stripe customer ID (currently unused in implementation but may be intended for future use)
     * @return String The Stripe payment method ID if successful, null if an error occurs
     */
    public static String createDefaultMethod(String customerId){
        String defaultMethodId;
        try {
            String endPoint = API_NAMED_CREDENTIALS + PAYMENT_ENDPOINT;
            String requestBody = 'type=' + EncodingUtil.urlEncode('card', 'UTF-8')+
                                '&card[token]=' + EncodingUtil.urlEncode('tok_visa', 'UTF-8');
            HttpResponse res = makeCallout(endPoint, requestBody);
            if (res.getStatusCode() == 200) {
                StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody().toString(), StripeWrapper.class);
                defaultMethodId = stripeResponse.id;
            }
        } catch (Exception ex) {
            Logger.error('Failed to generate HttpRequest: ', ex);
            Logger.saveLog();
        }
        return defaultMethodId;
    }
    /**
     * @description Attaches a payment method to a Stripe customer via API callout and returns the attached payment method ID.
     *              Sends a request to the Stripe Payment Method attach endpoint to associate the payment method with the
     *              specified customer. Parses the response to extract the payment method ID. Logs errors if the callout
     *              fails or encounters issues during execution.
     * @param defaultMethodId The Stripe payment method ID to attach to the customer
     * @param customerId The Stripe customer ID to which the payment method will be attached
     * @return String The attached payment method ID if successful, null if an error occurs
     */
    public static String attachPaymentMethod(String defaultMethodId, String customerId){
        String attachedMethodId;
        try {
            String endPoint = API_NAMED_CREDENTIALS + PAYMENT_ENDPOINT + '/' + defaultMethodId + '/attach';
            String requestBody = 'customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8');
            HttpResponse res = makeCallout(endPoint, requestBody);
            if (res.getStatusCode() == 200) {
                StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody().toString(), StripeWrapper.class);
                defaultMethodId = stripeResponse.id;
            }
        } catch (Exception ex) {
            Logger.error('Failed to generate HttpRequest: ', ex);
            Logger.saveLog();
        }
        return attachedMethodId;
    }
    /**
     * @description Creates a Stripe Checkout Session for subscription payment and returns the session details.
     *              Constructs a URL-encoded request body with customer ID, price ID, quantity, mode (subscription),
     *              and success URL, then sends it to the Stripe Checkout Session API endpoint. Parses and returns
     *              the complete session response wrapper. Logs errors if the callout fails or encounters issues.
     * @param customerId The Stripe customer ID for the checkout session
     * @param priceId The Stripe price ID for the subscription line item
     * @return StripeWrapper The complete Stripe session response if successful, null if an error occurs
     */
    public static StripeWrapper createSession(String customerId, String priceId){
        StripeWrapper stripeResponse;
        try {
            String endPoint = API_NAMED_CREDENTIALS + SESSION_ENDPOINT;
            String requestBody = 'customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8') + 
                                '&line_items[0][price]=' + EncodingUtil.urlEncode(priceId, 'UTF-8') +
                                '&line_items[0][quantity]=' + String.valueOf(1) +
                                '&mode=' + EncodingUtil.urlEncode('subscription', 'UTF-8') +
                                '&success_url=' + EncodingUtil.urlEncode('https://example.com/success', 'UTF-8');
            HttpResponse res = makeCallout(endPoint, requestBody);
            if (res.getStatusCode() == 200) {
                stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody().toString(), StripeWrapper.class);
            }
        } catch (Exception ex) {
            Logger.error('Failed to generate HttpRequest: ', ex);
            Logger.saveLog();
        }
        return stripeResponse;
    }
    /**
     * @description Executes an HTTP POST callout to Stripe API and returns the response.
     *              Constructs and sends an HTTP request with URL-encoded content type to the specified endpoint,
     *              logs the response status and body for debugging, and handles exceptions. Always throws a
     *              StripeException after receiving a response (appears to be incomplete error handling logic).
     * @param endPoint The full URL endpoint for the Stripe API callout
     * @param requestBody The URL-encoded request body containing API parameters
     * @return HttpResponse The HTTP response from Stripe API if successful, null if an error occurs
     */
    public static HttpResponse makeCallout(String endPoint, String requestBody){
        HttpResponse res;
        try {
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endPoint);
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setMethod('POST');
            req.setBody(requestBody);
            res = http.send(req);
            Logger.info('HTTP Response Received')
                .setMessage('Status Code: ' + res.getStatusCode())
                .addTag('HTTP-Response');
            
            Logger.finest('Response Body: ' + res.getBody());
            // If the HTTP response code is not successful, throw StripeException
            throw new StripeException(); 
        } catch (Exception ex) {
            // If the error occured when code was generating HttpRequest
            Logger.error('Failed to generate HttpRequest: ', ex);
            Logger.saveLog();
        }
        return res;
    }
}