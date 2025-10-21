public with sharing class StripeAPIService {
    private static final String API_NAMED_CREDENTIALS = 'callout:StripeAPI';
    private static final String CUSTOMER_ENDPOINT = '/v1/customers';
    private static final String PAYMENT_ENDPOINT = '/v1/payment_methods';
    private static final String PRICE_ENDPOINT = '/v1/prices';
    private static final String PRODUCT_ENDPOINT = '/v1/products';
    private static final String SUBSCRIPTION_ENDPOINT = '/v1/subscriptions';
    private static final String SESSION_ENDPOINT = '/v1/checkout/sessions';

    // @param StripeWrapper.CustomerWrapper from the created Stripe Customer that contains its details.
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