public with sharing class StripeSubscriptionService {
    private static final String API_NAMED_CREDENTIALS = 'callout:StripeAPI';
    private static final String SESSION_ENDPOINT = '/v1/checkout/sessions';

    public static Map<String, Object> createSession(String customerId, String priceId){
        Map<String, Object> payload;
        try {
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setEndpoint(API_NAMED_CREDENTIALS + SESSION_ENDPOINT);
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setMethod('POST');
            String reqBody = 'customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8') + 
                                '&line_items[0][price]=' + EncodingUtil.urlEncode(priceId, 'UTF-8') +
                                '&line_items[0][quantity]=' + String.valueOf(1) +
                                '&mode=' + EncodingUtil.urlEncode('subscription', 'UTF-8') +
                                '&success_url=' + EncodingUtil.urlEncode('https://example.com/success', 'UTF-8');
            req.setBody(reqBody);
            HttpResponse res = http.send(req);
            if (res.getStatusCode() == 200) {
                payload = (Map<String, Object>)JSON.deserializeUntyped(res.getBody().toString());
            }
        } catch (Exception ex) {
            Logger.error('Failed to generate HttpRequest: ', ex);
            Logger.saveLog();
        }
        return payload;
    }
}