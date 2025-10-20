public class StripeException extends Exception(HttpRequest req, HttpResponse res){
    Integer statusCode = res.getStatusCode();
    HttpResponseException ex;
        
        switch on statusCode {
            when 400 {
                ex = new Http400Exception(req, res);
            }
            when 401 {
                ex = new Http401Exception(req, res);
            }
            when 403 {
                ex = new Http403Exception(req, res);
            }
            when 404 {
                ex = new Http404Exception(req, res);
            }
            when 500, 502, 503, 504 {
                ex = new Http500Exception(req, res);
            }
            when else {
                ex = new HttpResponseException(req, res);
            }
        }
        
        // Log the specific error with custom exception
        Logger.error('HTTP Error Response', ex)
            .setMessage('Status: ' + statusCode + ' | Endpoint: ' + req.getEndpoint())
            .addTag('HTTP-Error')
            .addTag('Status-' + statusCode);
        
        Logger.saveLog();
}