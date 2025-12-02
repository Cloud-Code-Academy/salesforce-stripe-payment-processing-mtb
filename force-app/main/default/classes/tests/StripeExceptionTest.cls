/**
 * @description Test class for all Stripe exception classes to ensure 100% code coverage.
 *              Tests the factory method fromHttpResponse() and all exception types.
 */
@isTest
private class StripeExceptionTest {

    /**
     * @description Tests StripeRateLimitException creation from HTTP 429 response
     */
    @isTest
    static void testStripeRateLimitException_Http429() {
        // Create mock HTTP response for rate limit error
        HttpResponse res = new HttpResponse();
        res.setStatusCode(429);
        res.setStatus('Too Many Requests');
        res.setBody('{"error":{"type":"rate_limit_error","message":"Rate limit exceeded","code":"rate_limit"}}');

        Test.startTest();
        StripeException ex = StripeException.fromHttpResponse(res);
        Test.stopTest();

        // Verify correct exception type
        Assert.isTrue(ex instanceof StripeRateLimitException, 'Should create StripeRateLimitException for HTTP 429');
        Assert.areEqual(429, ex.httpStatusCode, 'HTTP status code should be 429');
        Assert.areEqual('rate_limit_error', ex.errorType, 'Error type should be rate_limit_error');
        Assert.areEqual('rate_limit', ex.errorCode, 'Error code should be rate_limit');
        Assert.isTrue(ex.isRetryable(), 'Rate limit errors should be retryable');
        Assert.isFalse(ex.isCardError(), 'Rate limit error is not a card error');
    }

    /**
     * @description Tests StripeAuthenticationException creation from HTTP 401 response
     */
    @isTest
    static void testStripeAuthenticationException_Http401() {
        // Create mock HTTP response for authentication error
        HttpResponse res = new HttpResponse();
        res.setStatusCode(401);
        res.setStatus('Unauthorized');
        res.setBody('{"error":{"type":"invalid_request_error","message":"Invalid API key provided","code":"invalid_api_key"}}');

        Test.startTest();
        StripeException ex = StripeException.fromHttpResponse(res);
        Test.stopTest();

        // Verify correct exception type
        Assert.isTrue(ex instanceof StripeAuthenticationException, 'Should create StripeAuthenticationException for HTTP 401');
        Assert.areEqual(401, ex.httpStatusCode, 'HTTP status code should be 401');
        Assert.areEqual('invalid_api_key', ex.errorCode, 'Error code should be invalid_api_key');
        Assert.isFalse(ex.isRetryable(), 'Authentication errors should not be retryable');
    }

    /**
     * @description Tests StripeAPIException creation from api_error type
     */
    @isTest
    static void testStripeAPIException_ApiErrorType() {
        // Create mock HTTP response for API error
        HttpResponse res = new HttpResponse();
        res.setStatusCode(500);
        res.setStatus('Internal Server Error');
        res.setBody('{"error":{"type":"api_error","message":"An error occurred on Stripe servers","code":"internal_error"}}');

        Test.startTest();
        StripeException ex = StripeException.fromHttpResponse(res);
        Test.stopTest();

        // Verify correct exception type
        Assert.isTrue(ex instanceof StripeAPIException, 'Should create StripeAPIException for api_error type');
        Assert.areEqual(500, ex.httpStatusCode, 'HTTP status code should be 500');
        Assert.areEqual('api_error', ex.errorType, 'Error type should be api_error');
        Assert.isTrue(ex.isRetryable(), 'API errors should be retryable');
    }

    /**
     * @description Tests StripeAPIException creation from HTTP 503 response
     */
    @isTest
    static void testStripeAPIException_Http503() {
        // Create mock HTTP response for server error
        HttpResponse res = new HttpResponse();
        res.setStatusCode(503);
        res.setStatus('Service Unavailable');
        res.setBody('{"error":{"type":"api_error","message":"Service temporarily unavailable"}}');

        Test.startTest();
        StripeException ex = StripeException.fromHttpResponse(res);
        Test.stopTest();

        // Verify retryable server error
        Assert.areEqual(503, ex.httpStatusCode, 'HTTP status code should be 503');
        Assert.isTrue(ex.isRetryable(), 'Server errors (503) should be retryable');
    }

    /**
     * @description Tests StripeInvalidRequestException creation from invalid_request_error type
     */
    @isTest
    static void testStripeInvalidRequestException_InvalidRequestError() {
        // Create mock HTTP response for invalid request error
        HttpResponse res = new HttpResponse();
        res.setStatusCode(400);
        res.setStatus('Bad Request');
        res.setBody('{"error":{"type":"invalid_request_error","message":"Missing required param: amount","code":"parameter_missing","param":"amount","doc_url":"https://stripe.com/docs/error-codes/parameter-missing"}}');

        Test.startTest();
        StripeException ex = StripeException.fromHttpResponse(res);
        Test.stopTest();

        // Verify correct exception type
        Assert.isTrue(ex instanceof StripeInvalidRequestException, 'Should create StripeInvalidRequestException for invalid_request_error type');
        Assert.areEqual(400, ex.httpStatusCode, 'HTTP status code should be 400');
        Assert.areEqual('invalid_request_error', ex.errorType, 'Error type should be invalid_request_error');
        Assert.areEqual('parameter_missing', ex.errorCode, 'Error code should be parameter_missing');
        Assert.areEqual('amount', ex.param, 'Param should be amount');
        Assert.areEqual('https://stripe.com/docs/error-codes/parameter-missing', ex.docUrl, 'Doc URL should be set');
        Assert.isFalse(ex.isRetryable(), 'Invalid request errors should not be retryable');
    }

    /**
     * @description Tests StripeCardException creation from card_error type
     */
    @isTest
    static void testStripeCardException_CardError() {
        // Create mock HTTP response for card error
        HttpResponse res = new HttpResponse();
        res.setStatusCode(402);
        res.setStatus('Payment Required');
        res.setBody('{"error":{"type":"card_error","message":"Your card was declined","code":"card_declined","decline_code":"insufficient_funds","param":"payment_method"}}');

        Test.startTest();
        StripeException ex = StripeException.fromHttpResponse(res);
        Test.stopTest();

        // Verify correct exception type
        Assert.isTrue(ex instanceof StripeCardException, 'Should create StripeCardException for card_error type');
        Assert.areEqual(402, ex.httpStatusCode, 'HTTP status code should be 402');
        Assert.areEqual('card_error', ex.errorType, 'Error type should be card_error');
        Assert.areEqual('card_declined', ex.errorCode, 'Error code should be card_declined');
        Assert.areEqual('insufficient_funds', ex.declineCode, 'Decline code should be insufficient_funds');
        Assert.isTrue(ex.isCardError(), 'Should be identified as a card error');
        Assert.isFalse(ex.isRetryable(), 'Card errors should not be retryable');
    }

    /**
     * @description Tests exception creation with null/empty response body
     */
    @isTest
    static void testStripeException_NullResponseBody() {
        // Create mock HTTP response with null body
        HttpResponse res = new HttpResponse();
        res.setStatusCode(400);
        res.setStatus('Bad Request');
        res.setBody('');

        Test.startTest();
        StripeException ex = StripeException.fromHttpResponse(res);
        Test.stopTest();

        // Verify fallback error message is used
        Assert.areEqual(400, ex.httpStatusCode, 'HTTP status code should be 400');
        Assert.isTrue(ex.getMessage().contains('Bad Request'), 'Should use fallback error message');
    }

    /**
     * @description Tests exception creation with malformed JSON response
     */
    @isTest
    static void testStripeException_MalformedJSON() {
        // Create mock HTTP response with malformed JSON
        HttpResponse res = new HttpResponse();
        res.setStatusCode(500);
        res.setStatus('Internal Server Error');
        res.setBody('{"invalid json structure');

        Test.startTest();
        StripeException ex = StripeException.fromHttpResponse(res);
        Test.stopTest();

        // Verify fallback behavior for malformed JSON
        Assert.areEqual(500, ex.httpStatusCode, 'HTTP status code should be 500');
        Assert.isTrue(ex.getMessage().contains('Stripe Server Error') || ex.getMessage().contains('Internal Server Error'),
            'Should use fallback error message for malformed JSON');
    }

    /**
     * @description Tests getDetailedMessage method
     */
    @isTest
    static void testStripeException_GetDetailedMessage() {
        // Create mock HTTP response with full error details
        HttpResponse res = new HttpResponse();
        res.setStatusCode(402);
        res.setStatus('Payment Required');
        res.setBody('{"error":{"type":"card_error","message":"Your card was declined","code":"card_declined","decline_code":"insufficient_funds","param":"payment_method"}}');

        Test.startTest();
        StripeException ex = StripeException.fromHttpResponse(res);
        String detailedMessage = ex.getDetailedMessage();
        Test.stopTest();

        // Verify detailed message contains all relevant information
        Assert.isTrue(detailedMessage.contains('Stripe Error'), 'Should contain error prefix');
        Assert.isTrue(detailedMessage.contains('HTTP 402'), 'Should contain HTTP status code');
        Assert.isTrue(detailedMessage.contains('card_error'), 'Should contain error type');
        Assert.isTrue(detailedMessage.contains('card_declined'), 'Should contain error code');
        Assert.isTrue(detailedMessage.contains('payment_method'), 'Should contain param');
        Assert.isTrue(detailedMessage.contains('insufficient_funds'), 'Should contain decline code');
    }

    /**
     * @description Tests getUserMessage method with error response
     */
    @isTest
    static void testStripeException_GetUserMessage() {
        // Create mock HTTP response
        HttpResponse res = new HttpResponse();
        res.setStatusCode(402);
        res.setStatus('Payment Required');
        res.setBody('{"error":{"type":"card_error","message":"Your card was declined"}}');

        Test.startTest();
        StripeException ex = StripeException.fromHttpResponse(res);
        String userMessage = ex.getUserMessage();
        Test.stopTest();

        // Verify user message
        Assert.areEqual('Your card was declined', userMessage, 'User message should match error message');
    }

    /**
     * @description Tests all fallback error messages by status code
     */
    @isTest
    static void testStripeException_FallbackMessages() {
        Map<Integer, String> statusCodeToExpectedMessage = new Map<Integer, String>{
            400 => 'Bad Request',
            401 => 'Authentication Failed',
            402 => 'Request Failed',
            403 => 'Forbidden',
            404 => 'Not Found',
            409 => 'Conflict',
            429 => 'Rate Limit Exceeded',
            500 => 'Stripe Server Error',
            502 => 'Stripe Server Error'
        };

        Test.startTest();
        for (Integer statusCode : statusCodeToExpectedMessage.keySet()) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setStatus('Test Status');
            res.setBody('');

            StripeException ex = StripeException.fromHttpResponse(res);

            Assert.isTrue(
                ex.getMessage().contains(statusCodeToExpectedMessage.get(statusCode)),
                'Status code ' + statusCode + ' should return message containing: ' + statusCodeToExpectedMessage.get(statusCode)
            );
        }
        Test.stopTest();
    }

    /**
     * @description Tests StripePermissionException creation from HTTP 403 response
     */
    @isTest
    static void testStripePermissionException_Http403() {
        // Create mock HTTP response for permission error
        HttpResponse res = new HttpResponse();
        res.setStatusCode(403);
        res.setStatus('Forbidden');
        res.setBody('{"error":{"type":"invalid_request_error","message":"The API key lacks permissions","code":"permission_error"}}');

        Test.startTest();
        StripeException ex = StripeException.fromHttpResponse(res);
        Test.stopTest();

        // Verify correct exception type
        Assert.isTrue(ex instanceof StripePermissionException, 'Should create StripePermissionException for HTTP 403');
        Assert.areEqual(403, ex.httpStatusCode, 'HTTP status code should be 403');
    }

    /**
     * @description Tests StripeIdempotencyException creation from HTTP 409 response
     */
    @isTest
    static void testStripeIdempotencyException_Http409() {
        // Create mock HTTP response for idempotency error
        HttpResponse res = new HttpResponse();
        res.setStatusCode(409);
        res.setStatus('Conflict');
        res.setBody('{"error":{"type":"idempotency_error","message":"Idempotency key reused with different parameters","code":"idempotency_error"}}');

        Test.startTest();
        StripeException ex = StripeException.fromHttpResponse(res);
        Test.stopTest();

        // Verify correct exception type
        Assert.isTrue(ex instanceof StripeIdempotencyException, 'Should create StripeIdempotencyException for HTTP 409');
        Assert.areEqual(409, ex.httpStatusCode, 'HTTP status code should be 409');
    }

    /**
     * @description Tests exception with request_log_url field
     */
    @isTest
    static void testStripeException_WithRequestLogUrl() {
        // Create mock HTTP response with request log URL
        HttpResponse res = new HttpResponse();
        res.setStatusCode(400);
        res.setStatus('Bad Request');
        res.setBody('{"error":{"type":"invalid_request_error","message":"Invalid request","request_log_url":"https://dashboard.stripe.com/test/logs/req_123"}}');

        Test.startTest();
        StripeException ex = StripeException.fromHttpResponse(res);
        Test.stopTest();

        // Verify request log URL is captured
        Assert.areEqual('https://dashboard.stripe.com/test/logs/req_123', ex.requestLogUrl, 'Request log URL should be set');
    }

    /**
     * @description Tests base StripeException when no specific type matches
     */
    @isTest
    static void testStripeException_BaseException() {
        // Create mock HTTP response with unknown error type
        HttpResponse res = new HttpResponse();
        res.setStatusCode(418);
        res.setStatus('I\'m a teapot');
        res.setBody('{"error":{"type":"unknown_error","message":"Unknown error occurred"}}');

        Test.startTest();
        StripeException ex = StripeException.fromHttpResponse(res);
        Test.stopTest();

        // Verify base exception is created
        Assert.areEqual('StripeException', String.valueOf(ex).substringBefore(':'), 'Should create base StripeException for unknown types');
        Assert.areEqual(418, ex.httpStatusCode, 'HTTP status code should be 418');
    }

    /**
     * @description Tests direct exception instantiation (covers constructors)
     */
    @isTest
    static void testExceptionDirectInstantiation() {
        Test.startTest();

        // Test direct instantiation of each exception type
        StripeRateLimitException rateLimitEx = new StripeRateLimitException('Rate limit test');
        Assert.areEqual('Rate limit test', rateLimitEx.getMessage(), 'Rate limit exception message should match');

        StripeInvalidRequestException invalidRequestEx = new StripeInvalidRequestException('Invalid request test');
        Assert.areEqual('Invalid request test', invalidRequestEx.getMessage(), 'Invalid request exception message should match');

        StripeAuthenticationException authEx = new StripeAuthenticationException('Auth test');
        Assert.areEqual('Auth test', authEx.getMessage(), 'Authentication exception message should match');

        StripeAPIException apiEx = new StripeAPIException('API error test');
        Assert.areEqual('API error test', apiEx.getMessage(), 'API exception message should match');

        StripeCardException cardEx = new StripeCardException('Card error test');
        Assert.areEqual('Card error test', cardEx.getMessage(), 'Card exception message should match');

        Test.stopTest();
    }

    /**
     * @description Tests throwing and catching each exception type to ensure code coverage
     */
    @isTest
    static void testExceptionThrowAndCatch() {
        Test.startTest();

        // Test StripeRateLimitException throw/catch
        try {
            throw new StripeRateLimitException('Rate limit exceeded');
        } catch (StripeRateLimitException e) {
            Assert.areEqual('Rate limit exceeded', e.getMessage(), 'Rate limit exception should be caught');
        }

        // Test StripeInvalidRequestException throw/catch
        try {
            throw new StripeInvalidRequestException('Invalid request');
        } catch (StripeInvalidRequestException e) {
            Assert.areEqual('Invalid request', e.getMessage(), 'Invalid request exception should be caught');
        }

        // Test StripeAuthenticationException throw/catch
        try {
            throw new StripeAuthenticationException('Authentication failed');
        } catch (StripeAuthenticationException e) {
            Assert.areEqual('Authentication failed', e.getMessage(), 'Authentication exception should be caught');
        }

        // Test StripeAPIException throw/catch
        try {
            throw new StripeAPIException('API error');
        } catch (StripeAPIException e) {
            Assert.areEqual('API error', e.getMessage(), 'API exception should be caught');
        }

        // Test StripeCardException throw/catch
        try {
            throw new StripeCardException('Card declined');
        } catch (StripeCardException e) {
            Assert.areEqual('Card declined', e.getMessage(), 'Card exception should be caught');
        }

        Test.stopTest();
    }
}
