/**
 * @description REST resource to handle incoming webhooks from various systems
 * Current implementation supports Jira webhooks at /webhook/jira
 * 
 * @author Buyan Suvan
 */
@RestResource(urlMapping='/webhook/stripe/*')
global class WebhookResource {
    @HttpPost
    global static ResponseWrapper doPost(){
        RestRequest request = RestContext.request;
        String webhookType = getWebhookTypeFromPath(request.requestURI);
        Logger.info('Stripe Webhook Request: ' + JSON.serialize(request));
        Logger.saveLog();
        RestResponse response = RestContext.response;
        String status;
        String message;
        try {
            if (webhookType == 'stripe') {
                WebhookFactory.processWebhook(webhookType, request);
                status = 'sucess';
                message = 'webhook was received correctly';
            } else {
                status = 'error';
                message = 'Unsupported webhook type';
            }
        } catch (Exception ex) {
            status = 'exception error';
            message = ex.getMessage();
            Logger.error('exception occured: ', ex);
            Logger.saveLog();
        }

        ResponseWrapper respWrapper = new ResponseWrapper(status, message);
        return respWrapper;
    }
    private static String getWebhookTypeFromPath(String path){
        String result;
        Logger.info('getWebhookTypeFromPath: ' + path);
        Logger.saveLog();
        if (path == null) {
            return result;
        }

        Integer webhookIndex = path.indexOf('/webhook/');

        if (webhookIndex >= 0) {
            String remaining = path.substring(webhookIndex + 9);
            Logger.info('remaining: ' + remaining);
            Logger.saveLog();

            Integer nextSlash = remaining.indexOf('/');
            if (nextSlash > 0) {
                Logger.info('nextSlash: ' + nextSlash);
                Logger.saveLog();
                result = remaining.substring(0, nextSlash).toLowerCase();
                return result;
            }
            result = remaining.toLowerCase();
            return result;
        }
        return result;
    }
    /**
     * @description Response wrapper class for consistent response format
     */
    global class ResponseWrapper {
        public String status;
        public String message;
        
        public ResponseWrapper(String status, String message) {
            this.status = status;
            this.message = message;
        }
    }
}