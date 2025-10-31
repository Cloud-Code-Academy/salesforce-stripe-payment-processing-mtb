/**
 * @description Exception thrown when an idempotency error occurs in Stripe API (idempotency_error type).
 *              This error type occurs when an idempotency key is reused with different request parameters,
 *              indicating a potential duplicate request with conflicting data.
 */
public class StripeIdempotencyException extends StripeException {
    /**
     * @description Constructor that creates an idempotency exception with a message.
     * @param message The error message describing the idempotency error
     */
    public StripeIdempotencyException(String message) {
        super(message);
    }
}
