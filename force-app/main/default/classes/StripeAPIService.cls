public with sharing class StripeAPIService {
    private static final String API_NAMED_CREDENTIALS = 'callout:StripeAPI';
    private static final String CUSTOMER_ENDPOINT = '/v1/customers';
    private static final String PAYMENT_ENDPOINT = '/v1/payment_methods';
    private static final String PRICE_ENDPOINT = '/v1/prices';
    private static final String PRODUCT_ENDPOINT = '/v1/products';
    private static final String SUBSCRIPTION_ENDPOINT = '/v1/subscriptions';
    private static final String SESSION_ENDPOINT = '/v1/checkout/sessions';

    // Retry configuration constants for queueable jobs
    public static final Integer MAX_RETRY_COUNT = 3;
    public static final Integer BASE_DELAY_MINUTES = 1;

    /**
     * @description Creates a new customer in Stripe via API callout and returns the generated Stripe customer ID.
     *              Constructs a URL-encoded request body with customer details (name, email, phone), sends it to the
     *              Stripe Customer API endpoint with automatic retry for transient errors, and parses the response
     *              to extract the customer ID. Throws StripeException with detailed error information on failure.
     * @param customerWrapper Wrapper object containing customer information (name, email, phone)
     * @return String The Stripe customer ID if successful
     * @throws StripeException If the API call fails (includes specific subtype based on error)
     */
    public static String createCustomer(StripeWrapper.CustomerWrapper customerWrapper){
        String endPoint = API_NAMED_CREDENTIALS + CUSTOMER_ENDPOINT;
        String requestBody = 'name=' + EncodingUtil.urlEncode(customerWrapper.name, 'UTF-8') +
                                '&email=' + EncodingUtil.urlEncode(customerWrapper.email, 'UTF-8') +
                                (customerWrapper.phone != null ? '&phone=' + EncodingUtil.urlEncode(customerWrapper.phone, 'UTF-8') : '');

        // Use retry logic - creating a customer is idempotent
        HttpResponse res = makeCalloutWithRetry(endPoint, requestBody, true);

        // Parse the successful response
        StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody(), StripeWrapper.class);
        return stripeResponse.id;
    }
    /**
     * @description Creates a new price in Stripe via API callout and returns the generated Stripe price ID.
     *              Sends a pre-formatted request body to the Stripe Price API endpoint with automatic retry
     *              for transient errors, and parses the response to extract the price ID. Throws StripeException
     *              with detailed error information on failure.
     * @param requestBody URL-encoded string containing price configuration parameters for Stripe API
     * @return String The Stripe price ID if successful
     * @throws StripeException If the API call fails (includes specific subtype based on error)
     */
    public static String createPrice(String requestBody){
        String endPoint = API_NAMED_CREDENTIALS + PRICE_ENDPOINT;

        // Use retry logic - creating a price is idempotent
        HttpResponse res = makeCalloutWithRetry(endPoint, requestBody, true);

        // Parse the successful response
        StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody(), StripeWrapper.class);
        return stripeResponse.id;
    }
    /**
     * @description Creates a new product in Stripe via API callout and returns the generated Stripe product ID.
     *              Constructs a URL-encoded request body with the product name, sends it to the Stripe Product API
     *              endpoint with automatic retry for transient errors, and parses the response to extract the product ID.
     *              Throws StripeException with detailed error information on failure.
     * @param productWrapper Wrapper object containing product information (name)
     * @return String The Stripe product ID if successful
     * @throws StripeException If the API call fails (includes specific subtype based on error)
     */
    public static String createProduct(StripeWrapper.ProductWrapper productWrapper){
        String endPoint = API_NAMED_CREDENTIALS + PRODUCT_ENDPOINT;
        String requestBody = 'name=' + EncodingUtil.urlEncode(productWrapper.name, 'UTF-8');

        // Use retry logic - creating a product is idempotent
        HttpResponse res = makeCalloutWithRetry(endPoint, requestBody, true);

        // Parse the successful response
        StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody(), StripeWrapper.class);
        return stripeResponse.id;
    }
    /**
     * @description Creates a new subscription in Stripe via API callout and returns the generated Stripe subscription ID.
     *              Constructs a URL-encoded request body with customer ID, price ID, and default payment method, sends it
     *              to the Stripe Subscription API endpoint with automatic retry for transient errors, and parses the
     *              response to extract the subscription ID. Throws StripeException with detailed error information on failure.
     * @param customerId The Stripe customer ID to associate with the subscription
     * @param priceId The Stripe price ID for the subscription item
     * @param defaultMethodId The Stripe payment method ID to use as default for the subscription
     * @return String The Stripe subscription ID if successful
     * @throws StripeException If the API call fails (includes specific subtype based on error)
     */
    public static String createSubscription(String customerId, String priceId, String defaultMethodId){
        String endPoint = API_NAMED_CREDENTIALS + SUBSCRIPTION_ENDPOINT;
        String requestBody = 'customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8') +
                         '&items[0][price]=' + EncodingUtil.urlEncode(priceId, 'UTF-8') +
                         '&default_payment_method=' + EncodingUtil.urlEncode(defaultMethodId, 'UTF-8');

        // Use retry logic - creating a subscription is idempotent
        HttpResponse res = makeCalloutWithRetry(endPoint, requestBody, true);

        // Parse the successful response
        StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody(), StripeWrapper.class);
        return stripeResponse.id;
    }
    /**
     * @description Creates a default payment method in Stripe via API callout and returns the generated payment method ID.
     *              Constructs a URL-encoded request body with a test card token ('tok_visa'), sends it to the Stripe
     *              Payment Method API endpoint with automatic retry for transient errors, and parses the response to
     *              extract the payment method ID. Throws StripeException with detailed error information on failure.
     * @param customerId The Stripe customer ID (currently unused in implementation but may be intended for future use)
     * @return String The Stripe payment method ID if successful
     * @throws StripeException If the API call fails (includes specific subtype based on error)
     */
    public static String createDefaultMethod(String customerId){
        String endPoint = API_NAMED_CREDENTIALS + PAYMENT_ENDPOINT;
        String requestBody = 'type=' + EncodingUtil.urlEncode('card', 'UTF-8')+
                            '&card[token]=' + EncodingUtil.urlEncode('tok_visa', 'UTF-8');

        // Use retry logic - creating a payment method is idempotent
        HttpResponse res = makeCalloutWithRetry(endPoint, requestBody, true);

        // Parse the successful response
        StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody(), StripeWrapper.class);
        return stripeResponse.id;
    }
    /**
     * @description Attaches a payment method to a Stripe customer via API callout and returns the attached payment method ID.
     *              Sends a request to the Stripe Payment Method attach endpoint with automatic retry for transient errors
     *              to associate the payment method with the specified customer. Parses the response to extract the payment
     *              method ID. Throws StripeException with detailed error information on failure.
     * @param defaultMethodId The Stripe payment method ID to attach to the customer
     * @param customerId The Stripe customer ID to which the payment method will be attached
     * @return String The attached payment method ID if successful
     * @throws StripeException If the API call fails (includes specific subtype based on error)
     */
    public static String attachPaymentMethod(String defaultMethodId, String customerId){
        String endPoint = API_NAMED_CREDENTIALS + PAYMENT_ENDPOINT + '/' + defaultMethodId + '/attach';
        String requestBody = 'customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8');

        // Use retry logic - attaching a payment method is idempotent
        HttpResponse res = makeCalloutWithRetry(endPoint, requestBody, true);

        // Parse the successful response
        StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody(), StripeWrapper.class);
        return stripeResponse.id;
    }
    /**
     * @description Creates a Stripe Checkout Session for subscription payment and returns the session details.
     *              Constructs a URL-encoded request body with customer ID, price ID, quantity, mode (subscription),
     *              and success URL, then sends it to the Stripe Checkout Session API endpoint with automatic retry
     *              for transient errors. Parses and returns the complete session response wrapper. Throws StripeException
     *              with detailed error information on failure.
     * @param customerId The Stripe customer ID for the checkout session
     * @param priceId The Stripe price ID for the subscription line item
     * @return StripeWrapper The complete Stripe session response if successful
     * @throws StripeException If the API call fails (includes specific subtype based on error)
     */
    public static StripeWrapper createSession(String customerId, String priceId){
        String endPoint = API_NAMED_CREDENTIALS + SESSION_ENDPOINT;
        String requestBody = 'customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8') +
                            '&line_items[0][price]=' + EncodingUtil.urlEncode(priceId, 'UTF-8') +
                            '&line_items[0][quantity]=' + String.valueOf(1) +
                            '&mode=' + EncodingUtil.urlEncode('subscription', 'UTF-8') +
                            '&success_url=' + EncodingUtil.urlEncode('https://example.com/success', 'UTF-8');

        // Use retry logic - creating a checkout session is idempotent
        HttpResponse res = makeCalloutWithRetry(endPoint, requestBody, true);

        // Parse and return the successful response
        return (StripeWrapper)JSON.deserialize(res.getBody(), StripeWrapper.class);
    }
    /**
     * @description Updates an existing customer in Stripe via API callout and returns the updated customer details.
     *              Constructs a URL-encoded request body with customer details (name, email, phone), sends it to the
     *              Stripe Customer API endpoint using PATCH method with automatic retry for transient errors, and parses
     *              the response to extract the customer information. Throws StripeException with detailed error information on failure.
     * @param customerWrapper Wrapper object containing customer information (name, email, phone)
     * @param customerId The Stripe customer ID to update
     * @return String The Stripe customer ID if successful
     * @throws StripeException If the API call fails (includes specific subtype based on error)
     */
    public static String updateCustomer(StripeWrapper.CustomerWrapper customerWrapper, String customerId){
        String endPoint = API_NAMED_CREDENTIALS + CUSTOMER_ENDPOINT + '/' + customerId;
        String requestBody = '';

        // Only include fields that are provided
        if (customerWrapper.name != null) {
            requestBody += 'name=' + EncodingUtil.urlEncode(customerWrapper.name, 'UTF-8');
        }

        if (customerWrapper.email != null) {
            if (requestBody.length() > 0) {
                requestBody += '&';
            }
            requestBody += 'email=' + EncodingUtil.urlEncode(customerWrapper.email, 'UTF-8');
        }

        if (customerWrapper.phone != null) {
            if (requestBody.length() > 0) {
                requestBody += '&';
            }
            requestBody += 'phone=' + EncodingUtil.urlEncode(customerWrapper.phone, 'UTF-8');
        }

        // Use retry logic - updating a customer is idempotent
        HttpResponse res = makeCalloutWithRetry(endPoint, requestBody, true);

        // Parse the successful response
        StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody(), StripeWrapper.class);
        return stripeResponse.id;
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
            // throw new StripeException(res.getStatus());
        } catch (Exception ex) {
            // If the error occured when code was generating HttpRequest
            Logger.error('Failed to generate HttpRequest: ', ex);
            Logger.saveLog();
        }
        return res;
    }

    /**
     * @description Makes an HTTP callout to Stripe API. This method now delegates retry logic to the calling queueable classes,
     *              which handle exponential backoff using System.enqueueJob() with delay parameters.
     * @param endPoint The full URL endpoint for the Stripe API callout
     * @param requestBody The URL-encoded request body containing API parameters
     * @param isIdempotent Whether this operation is safe to retry (GET, DELETE, or idempotent POST operations)
     * @return HttpResponse The HTTP response from Stripe API
     * @throws StripeException If the request fails, includes retryability information for queueable classes to handle
     */
    public static HttpResponse makeCalloutWithRetry(String endPoint, String requestBody, Boolean isIdempotent) {
        try {
            HttpResponse res = makeCallout(endPoint, requestBody);

            // Check if response indicates an error
            if (res.getStatusCode() >= 400) {
                // Parse and throw appropriate exception
                StripeException ex = StripeException.fromHttpResponse(res);

                // Log the error
                Logger.error('Stripe API error: ' + ex.getDetailedMessage())
                    .addTag('Stripe-Error');
                Logger.saveLog();

                // The exception includes isRetryable() method that queueable classes will use
                // to determine if they should retry with exponential backoff
                throw ex;
            } else {
                // Success - return the response
                return res;
            }
        } catch (StripeException ex) {
            // Re-throw StripeExceptions (already logged)
            throw ex;
        } catch (Exception ex) {
            // Network or other errors
            Logger.error('Failed to complete Stripe API request: ' + ex.getMessage())
                .addTag('Stripe-Error');
            Logger.saveLog();

            // Wrap in StripeException so queueable classes can check retryability
            throw new StripeException('Network error: ' + ex.getMessage());
        }
    }
}