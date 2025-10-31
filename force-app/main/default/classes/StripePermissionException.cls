/**
 * @description Exception thrown when a permission error occurs (HTTP 403).
 *              This error indicates that the API key lacks the necessary permissions to perform
 *              the requested operation. The key may be valid but restricted in scope.
 */
public class StripePermissionException extends StripeException {
    /**
     * @description Constructor that creates a permission exception with a message.
     * @param message The error message describing the permission error
     */
    public StripePermissionException(String message) {
        super(message);
    }
}
