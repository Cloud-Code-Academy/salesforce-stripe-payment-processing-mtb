public with sharing class StripeAPIService {
    private static final String API_NAMED_CREDENTIALS = 'callout:StripeAPI';
    
    public static String createCustomer(StripeWrapper.CustomerWrapper customerWrapper){
        String customerId;
        try {
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            String endPoint = '/v1/customers';
            req.setEndpoint(API_NAMED_CREDENTIALS + endPoint);
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setMethod('POST');
            req.setBody(JSON.serialize(customerWrapper));
            System.debug('req: ' + req);
            HttpResponse res = http.send(req);
            System.debug('res: ' + res.getBody());
            if (res.getStatusCode() == 200) {
                System.debug('StatusCode: ' + res.getStatusCode());
                StripeWrapper stripeResponse = (StripeWrapper)JSON.deserialize(res.getBody().toString(), StripeWrapper.class);
                customerId = stripeResponse.id;
            }
        } catch (Exception ex) {
            System.debug('Error happened while request: ' + ex.getMessage());
            customerId = 'Error';
        }
        return customerId;
    }
}