/**
 * @description Exception thrown when an idempotency error occurs in Stripe API (idempotency_error type).
 *              This error type occurs when an idempotency key is reused with different request parameters,
 *              indicating a potential duplicate request with conflicting data.
 *              Inherits all constructors from StripeException and Exception.
 */
public class StripeIdempotencyException extends StripeException {
}
