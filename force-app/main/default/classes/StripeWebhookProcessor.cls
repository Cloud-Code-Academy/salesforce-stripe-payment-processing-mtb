public class StripeWebhookProcessor implements IWebhookProcessor{

    public Boolean validate(RestRequest request){
        Boolean valid;
        try {

            String requestBody = request.requestBody.toString();
            Map<String, Object> payload = (Map<String,Object>)JSON.deserializeUntyped(requestBody);
            if (payload.containsKey('data')) {
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
            StripeWebhookWrapper payload = (StripeWebhookWrapper)JSON.deserialize(request.requestBody.toString().replace('object', 'object_x'), StripeWebhookWrapper.class);
            EventBus.publish(new WebhookEvent__e(
                EventType__c = payload.type,
                Payload__c = request.requestBody.toString()
            ));
        } catch (Exception ex) {
            Logger.error('Error while processing webhook: ', ex);
            Logger.saveLog();
        }
    }
}