/**
 * @description Exception thrown when an invalid request error occurs in Stripe API (invalid_request_error type).
 *              This error type occurs when the request has invalid parameters, such as missing required
 *              fields, invalid data types, or malformed requests.
 */
public class StripeInvalidRequestException extends StripeException {
    /**
     * @description Constructor that creates an invalid request exception with a message.
     * @param message The error message describing the invalid request
     */
    public StripeInvalidRequestException(String message) {
        super(message);
    }
}
