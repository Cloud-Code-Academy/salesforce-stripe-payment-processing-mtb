/**
 * @description Interface for webhook processors
 * All webhook processors should implement this interface
 * @author Buyan Suvan
 */
public interface IWebhookProcessor {
    
    /**
     * @description Validates the incoming webhook request
     * @param request The REST request containing the webhook payload
     * @return Boolean True if the request is valid, false otherwise
     */
    Boolean validate(RestRequest request);
    
    /**
     * @description Processes the webhook request
     * @param request The REST request containing the webhook payload
     */
    void process(RestRequest request);
} 