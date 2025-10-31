/**
 * @description Exception thrown when an authentication error occurs (HTTP 401).
 *              This error indicates that the API key used in the request is invalid, expired,
 *              or missing. Requests cannot proceed without valid authentication credentials.
 */
public class StripeAuthenticationException extends StripeException {
    /**
     * @description Constructor that creates an authentication exception with a message.
     * @param message The error message describing the authentication error
     */
    public StripeAuthenticationException(String message) {
        super(message);
    }
}
