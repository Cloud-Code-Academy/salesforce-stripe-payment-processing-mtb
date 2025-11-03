/**
 * @description Exception thrown when a permission error occurs (HTTP 403).
 *              This error indicates that the API key lacks the necessary permissions to perform
 *              the requested operation. The key may be valid but restricted in scope.
 *              Inherits all constructors from StripeException and Exception.
 */
public class StripePermissionException extends StripeException {
}