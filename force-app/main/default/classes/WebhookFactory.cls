public with sharing class WebhookFactory {
   public static void processWebhook(String webhookType, RestRequest request){
    // Get the appropriate webhook processor
    IWebhookProcessor processor = getProcessor(webhookType);

    if (processor == null) {
        throw new WebhookException('Unsupported webhook type: ' + webhookType);
    }
    if (processor.validate(request)) {
        processor.process(request);
    } else {
        throw new WebhookException('Webhook validation failed for type: ' + webhookType);
    }

   }
   private static IWebhookProcessor getProcessor(String webhookType){
    switch on webhookType{
        when 'stripe' {
            return new StripeWebhookProcessor();
        }
        when else {
            return null;
        }
    }
   }
   public class WebhookException extends Exception{}
}