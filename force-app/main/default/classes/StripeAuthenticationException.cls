/**
 * @description Exception thrown when an authentication error occurs (HTTP 401).
 *              This error indicates that the API key used in the request is invalid, expired,
 *              or missing. Requests cannot proceed without valid authentication credentials.
 *              Inherits all constructors from StripeException and Exception.
 */
public class StripeAuthenticationException extends StripeException {
}