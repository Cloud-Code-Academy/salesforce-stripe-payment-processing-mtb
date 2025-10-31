/**
 * @description Exception thrown when a rate limit error occurs (HTTP 429).
 *              This error indicates that too many requests have been sent to the API in a given
 *              timeframe. Requests should be retried after a delay using exponential backoff.
 */
public class StripeRateLimitException extends StripeException {
    /**
     * @description Constructor that creates a rate limit exception with a message.
     * @param message The error message describing the rate limit error
     */
    public StripeRateLimitException(String message) {
        super(message);
    }
}
