/**
 * @description Exception thrown when a rate limit error occurs (HTTP 429).
 *              This error indicates that too many requests have been sent to the API in a given
 *              timeframe. Requests should be retried after a delay using exponential backoff.
 *              Inherits all constructors from StripeException and Exception.
 */
public class StripeRateLimitException extends StripeException {
}
