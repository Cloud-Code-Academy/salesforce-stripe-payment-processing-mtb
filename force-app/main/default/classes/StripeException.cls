/**
 * @description Base exception class for all Stripe API errors. Captures detailed error information
 *              from Stripe error responses including error type, code, HTTP status, and additional
 *              metadata to enable proper error handling and user messaging.
 */
public class StripeException extends Exception {
    // The Stripe error type (e.g., 'card_error', 'invalid_request_error', 'api_error', 'idempotency_error')
    public String errorType { get; private set; }

    // The specific error code from Stripe (e.g., 'card_declined', 'insufficient_funds')
    public String errorCode { get; private set; }

    // The HTTP status code from the response (e.g., 400, 401, 402, 403, 404, 429, 500)
    public Integer httpStatusCode { get; private set; }

    // The parameter that caused the error (for validation errors)
    public String param { get; private set; }

    // The decline code for card errors (e.g., 'insufficient_funds', 'stolen_card')
    public String declineCode { get; private set; }

    // URL to Stripe documentation for this error code
    public String docUrl { get; private set; }

    // URL to the request log in Stripe dashboard
    public String requestLogUrl { get; private set; }

    // The full error response object from Stripe
    public StripeWrapper.ErrorResponse errorResponse { get; private set; }

    /**
     * @description Default constructor that creates an exception with a message.
     * @param message The error message
     */
    public StripeException(String message) {
        super(message);
    }

    /**
     * @description Constructor that creates an exception with message and HTTP status code.
     * @param message The error message
     * @param statusCode The HTTP status code from the response
     */
    public StripeException(String message, Integer statusCode) {
        super(message);
        this.httpStatusCode = statusCode;
    }

    /**
     * @description Factory method to create a StripeException from an HTTP response.
     *              Parses the error response body and populates all error fields.
     * @param res The HTTP response from Stripe API
     * @return StripeException The appropriate exception type based on the error
     */
    public static StripeException fromHttpResponse(HttpResponse res) {
        Integer statusCode = res.getStatusCode();
        String responseBody = res.getBody();

        // Try to parse the error response
        StripeWrapper.ErrorResponse errorDetails = parseErrorResponse(responseBody);

        // Determine the appropriate exception type and message
        String errorMessage = buildErrorMessage(errorDetails, statusCode, res.getStatus());
        StripeException ex = createTypedException(errorDetails, errorMessage, statusCode);

        // Populate exception fields
        ex.httpStatusCode = statusCode;
        ex.errorResponse = errorDetails;

        if (errorDetails != null) {
            ex.errorType = errorDetails.type;
            ex.errorCode = errorDetails.code;
            ex.param = errorDetails.param;
            ex.declineCode = errorDetails.decline_code;
            ex.docUrl = errorDetails.doc_url;
            ex.requestLogUrl = errorDetails.request_log_url;
        }

        return ex;
    }

    /**
     * @description Parses the JSON error response from Stripe.
     * @param responseBody The response body as a string
     * @return StripeWrapper.ErrorResponse The parsed error response, or null if parsing fails
     */
    private static StripeWrapper.ErrorResponse parseErrorResponse(String responseBody) {
        try {
            if (String.isNotBlank(responseBody)) {
                StripeWrapper.StripeErrorWrapper errorWrapper =
                    (StripeWrapper.StripeErrorWrapper)JSON.deserialize(responseBody, StripeWrapper.StripeErrorWrapper.class);
                return errorWrapper.error;
            }
        } catch (Exception e) {
            // If parsing fails, return null and use fallback error message
            Logger.error('Failed to parse Stripe error response: ' + e.getMessage());
        }
        return null;
    }

    /**
     * @description Builds an appropriate error message based on the error details.
     * @param errorDetails The parsed error response
     * @param statusCode The HTTP status code
     * @param statusText The HTTP status text
     * @return String The error message
     */
    private static String buildErrorMessage(StripeWrapper.ErrorResponse errorDetails, Integer statusCode, String statusText) {
        if (errorDetails != null && String.isNotBlank(errorDetails.message)) {
            return errorDetails.message;
        }

        // Fallback to status-based messages
        if (statusCode == 400) {
            return 'Bad Request: The request was invalid or missing required parameters.';
        } else if (statusCode == 401) {
            return 'Authentication Failed: Invalid API key provided.';
        } else if (statusCode == 402) {
            return 'Request Failed: The request parameters were valid but the request failed.';
        } else if (statusCode == 403) {
            return 'Forbidden: The API key lacks permissions for this request.';
        } else if (statusCode == 404) {
            return 'Not Found: The requested resource does not exist.';
        } else if (statusCode == 409) {
            return 'Conflict: Idempotency key reused with different parameters.';
        } else if (statusCode == 429) {
            return 'Rate Limit Exceeded: Too many requests. Please retry after a delay.';
        } else if (statusCode >= 500) {
            return 'Stripe Server Error: An error occurred on Stripe\'s servers. Please retry.';
        }

        return 'Stripe API Error: ' + statusText;
    }

    /**
     * @description Creates the appropriate typed exception based on error details.
     * @param errorDetails The parsed error response
     * @param message The error message
     * @param statusCode The HTTP status code
     * @return StripeException The appropriate exception type
     */
    private static StripeException createTypedException(StripeWrapper.ErrorResponse errorDetails, String message, Integer statusCode) {
        // Create specific exception based on HTTP status code first
        if (statusCode == 401) {
            return new StripeAuthenticationException(message);
        } else if (statusCode == 403) {
            return new StripePermissionException(message);
        } else if (statusCode == 409) {
            return new StripeIdempotencyException(message);
        } else if (statusCode == 429) {
            return new StripeRateLimitException(message);
        }

        // Then check error type from response
        if (errorDetails != null && String.isNotBlank(errorDetails.type)) {
            if (errorDetails.type == 'card_error') {
                return new StripeCardException(message);
            } else if (errorDetails.type == 'invalid_request_error') {
                return new StripeInvalidRequestException(message);
            } else if (errorDetails.type == 'api_error') {
                return new StripeAPIException(message);
            } else if (errorDetails.type == 'idempotency_error') {
                return new StripeIdempotencyException(message);
            }
        }

        // Default to base StripeException
        return new StripeException(message, statusCode);
    }

    /**
     * @description Checks if this error should be retried with exponential backoff.
     * @return Boolean True if the error is retryable (rate limits, server errors, api_error)
     */
    public Boolean isRetryable() {
        // Retry rate limits (429) and server errors (500+)
        if (httpStatusCode != null && (httpStatusCode == 429 || httpStatusCode >= 500)) {
            return true;
        }

        // Retry api_error types
        if (errorType == 'api_error') {
            return true;
        }

        return false;
    }

    /**
     * @description Checks if this is a card-related error.
     * @return Boolean True if the error type is card_error
     */
    public Boolean isCardError() {
        return errorType == 'card_error';
    }

    /**
     * @description Gets a user-friendly error message suitable for displaying to end users.
     * @return String The user-friendly error message
     */
    public String getUserMessage() {
        if (errorResponse != null) {
            return errorResponse.getUserMessage();
        }
        return getMessage();
    }

    /**
     * @description Gets a detailed error message for logging purposes.
     * @return String Detailed error information including type, code, and status
     */
    public String getDetailedMessage() {
        String details = 'Stripe Error: ' + getMessage();
        if (httpStatusCode != null) {
            details += ' (HTTP ' + httpStatusCode + ')';
        }
        if (String.isNotBlank(errorType)) {
            details += ' [Type: ' + errorType + ']';
        }
        if (String.isNotBlank(errorCode)) {
            details += ' [Code: ' + errorCode + ']';
        }
        if (String.isNotBlank(param)) {
            details += ' [Param: ' + param + ']';
        }
        if (String.isNotBlank(declineCode)) {
            details += ' [Decline: ' + declineCode + ']';
        }
        return details;
    }
}