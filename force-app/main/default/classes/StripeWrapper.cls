/**
 * @description Wrapper classes for Stripe API request and response data. Provides structured objects for serializing
 *              and deserializing JSON data when communicating with Stripe endpoints. Includes wrappers for customers,
 *              products, pricing plans, and API responses.
 */
public class StripeWrapper {
    // Used to get Id of created Stripe Customer
    public String id { get; set; }
    public String url { get; set; }

    // Wrapper for Customer Object
    public class CustomerWrapper{
        public String name;
        public String email;
        public String phone;
        /**
         * @description Constructor to initialize customer wrapper with contact information.
         * @param name Full name of the customer
         * @param email Email address of the customer
         * @param phone Phone number of the customer
         */
        public CustomerWrapper(String name, String email, String phone){
            this.name = name;
            this.email = email;
            this.phone = phone;
        }
    }
    /**
     * @description Wrapper class for Stripe Product data used in API requests.
     */
    public class ProductWrapper{
        public String name;
        /**
         * @description Constructor to initialize product wrapper with product name.
         * @param productName Name/description of the Stripe product
         */
        public ProductWrapper(String productName){
            this.name = productName;
        }
    }

    /**
     * @description Wrapper class for Stripe API error responses. Maps to the error object structure
     *              returned by Stripe when an API request fails. Contains all error attributes needed
     *              to properly handle and display error information to users.
     */
    public class ErrorResponse {
        // The type of error returned (e.g., 'card_error', 'invalid_request_error', 'api_error', 'idempotency_error')
        public String type;

        // Human-readable message providing more details about the error (can be shown to users for card errors)
        public String message;

        // Short string indicating the error code (for programmatic handling of specific errors)
        public String code;

        // The parameter the error relates to if the error is parameter-specific (useful for form validation)
        public String param;

        // Card issuer's advice on how to proceed with the decline
        public String advice_code;

        // The reason for the card decline as provided by the card issuer
        public String decline_code;

        // 2-digit code from the card network indicating how to handle the error
        public String network_advice_code;

        // Alphanumeric code from the card network for the payment decline reason
        public String network_decline_code;

        // ID of the failed charge (for card errors)
        public String charge;

        // URL to more information about the error code reported
        public String doc_url;

        // URL to the request log entry in the Stripe dashboard
        public String request_log_url;

        // ID of the PaymentIntent object for errors involving PaymentIntents
        public String payment_intent;

        // ID of the PaymentMethod object for errors involving PaymentMethods
        public String payment_method;

        // Type of payment method (e.g., 'card', 'bank_account') that had an issue
        public String payment_method_type;

        // ID of the SetupIntent object for errors involving SetupIntents
        public String setup_intent;

        // ID of the source object for errors involving sources
        public String source;

        /**
         * @description Checks if this error type should be retried (transient errors).
         * @return Boolean True if the error is retryable (api_error), false otherwise
         */
        public Boolean isRetryable() {
            return type == 'api_error';
        }

        /**
         * @description Checks if this is a card-related error.
         * @return Boolean True if the error type is card_error, false otherwise
         */
        public Boolean isCardError() {
            return type == 'card_error';
        }

        /**
         * @description Gets a user-friendly error message suitable for displaying to end users.
         * @return String The error message, or a generic message if none is available
         */
        public String getUserMessage() {
            if (String.isNotBlank(message)) {
                return message;
            }
            return 'An error occurred processing your request. Please try again.';
        }
    }

    /**
     * @description Wrapper for the complete error response structure from Stripe.
     *              Stripe returns errors in a JSON object with an 'error' key containing the ErrorResponse.
     */
    public class StripeErrorWrapper {
        public ErrorResponse error;
    }
}