/**
 * @description Exception thrown when an invalid request error occurs in Stripe API (invalid_request_error type).
 *              This error type occurs when the request has invalid parameters, such as missing required
 *              fields, invalid data types, or malformed requests.
 *              Inherits all constructors from StripeException and Exception.
 */
public class StripeInvalidRequestException extends StripeException {
}