public with sharing class StripeAPIService {
    private static final String API_NAMED_CREDENTIALS = 'callout:StripeAPI';
    private static final String CUSTOMER_ENDPOINT = '/v1/customers';

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
            if (res.getStatusCode() = 200) {
                StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody().toString(), StripeWrapper.class);
                customerId = stripeResponse.id;
            } 
            // If the HTTP response code is not successful, throw StripeException
            throw new StripeException(res.getStatus()); 
        } catch (Exception ex) {
            // If the error occured when code was generating HttpRequest
            System.debug('Error happened while generating request: ' + ex.getMessage());
        }
        return customerId;
    }
}