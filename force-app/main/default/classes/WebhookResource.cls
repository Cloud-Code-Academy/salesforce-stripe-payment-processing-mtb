/**
 * @description REST resource to handle incoming webhooks from various systems
 * Current implementation supports Jira webhooks at /webhook/jira
 * 
 * @author Buyan Suvan
 */
@RestResource(urlMapping='/webhooks/*')
global class WebhookResource {
    @HttpPost
    global static ResponseWrapper doPost(){
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        String status;
        String message;

        ResponseWrapper respWrapper = new ResponseWrapper(status, message);
        return respWrapper;
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