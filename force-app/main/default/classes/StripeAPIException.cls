/**
 * @description Exception thrown when a Stripe API server error occurs (api_error type).
 *              This error type indicates temporary problems with Stripe's servers and is extremely uncommon.
 *              These errors should typically be retried after a brief delay.
 */
public class StripeAPIException extends StripeException {
    /**
     * @description Constructor that creates an API exception with a message.
     * @param message The error message describing the API error
     */
    public StripeAPIException(String message) {
        super(message);
    }
}
