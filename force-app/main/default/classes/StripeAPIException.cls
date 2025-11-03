/**
 * @description Exception thrown when a Stripe API server error occurs (api_error type).
 *              This error type indicates temporary problems with Stripe's servers and is extremely uncommon.
 *              These errors should typically be retried after a brief delay.
 *              Inherits all constructors from StripeException and Exception.
 */
public class StripeAPIException extends StripeException {
}