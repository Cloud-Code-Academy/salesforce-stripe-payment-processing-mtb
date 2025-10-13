public class StripeException extends Exception{
    public StripeException(HttpResponse respponse, String className){
        System.debug('ClassName: ' + className);
        System.debug('Error Status Code: ' + respponse.getStatusCode());
        Map<String, Object> payload = (Map<String, Object>)JSON.deserializeUntyped(respponse.getBody().toString());
        Map<String, Object> error = (Map<String, Object>)payload.get('error');
        System.debug('Error code: ' + String.valueOf(error.get('code')));
        System.debug('Error message: ' + String.valueOf(error.get('message')));
        System.debug('Error param: ' + String.valueOf(error.get('param')));
        System.debug('Error type: ' + String.valueOf(error.get('type')));
    }
}