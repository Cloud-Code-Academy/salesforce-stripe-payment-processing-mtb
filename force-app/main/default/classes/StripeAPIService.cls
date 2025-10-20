public with sharing class StripeAPIService {
    private static final String API_NAMED_CREDENTIALS = 'callout:StripeAPI';
    private static final String CUSTOMER_ENDPOINT = '/v1/customers';
    private static final String PAYMENT_ENDPOINT = '/v1/payment_methods';
    private static final String PRICE_ENDPOINT = '/v1/prices';
    private static final String PRODUCT_ENDPOINT = '/v1/products';
    private static final String SUBSCRIPTION_ENDPOINT = '/v1/subscriptions';

    // @param StripeWrapper.CustomerWrapper from the created Stripe Customer that contains its details.
    public static String createCustomer(StripeWrapper.CustomerWrapper customerWrapper){
        String customerId;
        try {
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(API_NAMED_CREDENTIALS + CUSTOMER_ENDPOINT);
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setMethod('POST');
            req.setBody(JSON.serialize(customerWrapper));
            HttpResponse res = http.send(req);
            // If the HTTP response code is successful, parse the JSON response and Id of created Stripe Customer
            if (res.getStatusCode() == 200) {
                StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody().toString(), StripeWrapper.class);
                customerId = stripeResponse.id;
            } 
            // If the HTTP response code is not successful, throw StripeException
            throw new StripeException(res.getStatus()); 
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
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(API_NAMED_CREDENTIALS + PRICE_ENDPOINT);
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setMethod('POST');
            req.setBody(requestBody);
            HttpResponse res = http.send(req);
            Logger.info('HTTP Response Received')
                .setMessage('Status Code: ' + res.getStatusCode())
                .addTag('HTTP-Response');
            
            Logger.finest('Response Body: ' + res.getBody());
            if (res.getStatusCode() == 200) {
                Map<String, Object> payload = (Map<String, Object>)JSON.deserializeUntyped(res.getBody().toString());
                priceId = (String)payload.get('id');
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
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(API_NAMED_CREDENTIALS + PRODUCT_ENDPOINT);
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setMethod('POST');
            String reqBody = 'name=' + EncodingUtil.urlEncode(productWrapper.name, 'UTF-8');
            req.setBody(reqBody);
            HttpResponse res = http.send(req);
            Logger.info('HTTP Response Received')
                .setMessage('Status Code: ' + res.getStatusCode())
                .addTag('HTTP-Response');
            
            Logger.finest('Response Body: ' + res.getBody());
            if (res.getStatusCode() == 200) {
                Map<String, Object> payload = (Map<String, Object>)JSON.deserializeUntyped(res.getBody().toString());
                productId = (String)payload.get('id');
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
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(API_NAMED_CREDENTIALS + SUBSCRIPTION_ENDPOINT);
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setMethod('POST');
            String reqBody = 'customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8') +
                             '&items[0][price]=' + EncodingUtil.urlEncode(priceId, 'UTF-8') + 
                             '&default_payment_method=' + EncodingUtil.urlEncode(defaultMethodId, 'UTF-8');
            req.setBody(reqBody);
            HttpResponse res = http.send(req);
            Logger.info('HTTP Response Received')
                .setMessage('Status Code: ' + res.getStatusCode())
                .addTag('HTTP-Response');
            
            Logger.finest('Response Body: ' + res.getBody());
            if (res.getStatusCode() == 200) {
                Map<String, Object> payload = (Map<String, Object>)JSON.deserializeUntyped(res.getBody().toString());
                subscriptionId = (String)payload.get('id');
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
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(API_NAMED_CREDENTIALS + PAYMENT_ENDPOINT);
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setMethod('POST');
            String reqBody = 'type=' + EncodingUtil.urlEncode('card', 'UTF-8')+
                                '&card[token]=' + EncodingUtil.urlEncode('tok_visa', 'UTF-8');
            req.setBody(reqBody);
            HttpResponse res = http.send(req);
            Logger.info('HTTP Response Received')
                .setMessage('Status Code: ' + res.getStatusCode())
                .addTag('HTTP-Response');
            
            Logger.finest('Response Body: ' + res.getBody());
            if (res.getStatusCode() == 200) {
                Map<String, Object> payload = (Map<String, Object>)JSON.deserializeUntyped(res.getBody().toString());
                defaultMethodId = (String)payload.get('id');
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
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(API_NAMED_CREDENTIALS + PAYMENT_ENDPOINT + '/' + defaultMethodId + '/attach');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setMethod('POST');
            String reqBody = 'customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8');
            req.setBody(reqBody);
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                Map<String, Object> payload = (Map<String, Object>)JSON.deserializeUntyped(res.getBody().toString());
                defaultMethodId = (String)payload.get('id');
            }
        } catch (Exception ex) {
            Logger.error('Failed to generate HttpRequest: ', ex);
            Logger.saveLog();
        }
        return attachedMethodId;
    }
}