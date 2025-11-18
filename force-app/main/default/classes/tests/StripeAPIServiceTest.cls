@isTest
private class StripeAPIServiceTest {

    private static User testUser;

    @TestSetup
    static void setupTestData() {
        // Create test user with Stripe API Access permission set
        testUser = TestDataFactory.createUserWithPermissionSets(
            new List<String>{'Stripe_API_Access', 'CustomMetadataAccess','Stripe_Integration_User','PricingPlanAndPricingTier'}
        );
    }

    // Helper method to get test user
    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'testuser%@testorg.com' LIMIT 1];
    }

    // Mock class for successful HTTP callout
    private class StripeAPISuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {

            // Create a successful response
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"cus_test123","name":"Test Customer","email":"test@example.com"}');
            res.setStatusCode(200);
            return res;
        }
    }

    // Mock class for failed HTTP callout
    private class StripeAPIFailureMock implements HttpCalloutMock {
        private Integer statusCode;
        private String status;

        public StripeAPIFailureMock(Integer statusCode, String status) {
            this.statusCode = statusCode;
            this.status = status;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":{"message":"' + this.status + '"}}');
            res.setStatusCode(this.statusCode);
            res.setStatus(this.status);
            return res;
        }
    }

    // Mock class that throws an exception
    private class StripeAPIExceptionMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new CalloutException('Connection timeout');
        }
    }

    @isTest
    static void testCreateCustomer_Success() {
        System.runAs(getTestUser()) {
            // Set the mock callout
            Test.setMock(HttpCalloutMock.class, new StripeAPISuccessMock());

            // Create test data
            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                'Test Customer',
                'test@example.com',
                '+1234567890'
            );

            // Start test context
            Test.startTest();
            String customerId = StripeAPIService.createCustomer(customerWrapper);
            Test.stopTest();

            // Verify the result
            Assert.areNotEqual(null, customerId, 'Customer ID should not be null');
            Assert.areEqual('cus_test123', customerId, 'Customer ID should match the mock response');
        }
    }

    @isTest
    static void testCreateCustomer_HttpFailure_400() {
        System.runAs(getTestUser()) {
            // Set the mock callout for 400 Bad Request
            Test.setMock(HttpCalloutMock.class, new StripeAPIFailureMock(400, 'Bad Request'));

            // Create test data
            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                'Test Customer',
                'invalid-email',
                'invalid-phone'
            );

            // Start test context
            Test.startTest();
            try {
                StripeAPIService.createCustomer(customerWrapper);
                Assert.fail('Expected StripeException to be thrown');
            } catch (StripeException ex) {
                Assert.areEqual(400, ex.httpStatusCode, 'HTTP status code should be 400');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void testCreateCustomer_HttpFailure_401() {
        System.runAs(getTestUser()) {
            // Set the mock callout for 401 Unauthorized
            Test.setMock(HttpCalloutMock.class, new StripeAPIFailureMock(401, 'Unauthorized'));

            // Create test data
            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                'Test Customer',
                'test@example.com',
                '+1234567890'
            );

            // Start test context
            Test.startTest();
            try {
                StripeAPIService.createCustomer(customerWrapper);
                Assert.fail('Expected StripeException to be thrown');
            } catch (StripeException ex) {
                Assert.areEqual(401, ex.httpStatusCode, 'HTTP status code should be 401');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void testCreateCustomer_HttpFailure_500() {
        System.runAs(getTestUser()) {
            // Set the mock callout for 500 Internal Server Error
            Test.setMock(HttpCalloutMock.class, new StripeAPIFailureMock(500, 'Internal Server Error'));

            // Create test data
            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                'Test Customer',
                'test@example.com',
                '+1234567890'
            );

            // Start test context
            Test.startTest();
            try {
                StripeAPIService.createCustomer(customerWrapper);
                Assert.fail('Expected StripeException to be thrown after retries');
            } catch (StripeException ex) {
                Assert.areEqual(500, ex.httpStatusCode, 'HTTP status code should be 500');
                Assert.areEqual(true, ex.isRetryable(), 'Error should be retryable');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void testCreateCustomer_CalloutException() {
        System.runAs(getTestUser()) {
            // Set the mock callout that throws an exception
            Test.setMock(HttpCalloutMock.class, new StripeAPIExceptionMock());

            // Create test data
            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                'Test Customer',
                'test@example.com',
                '+1234567890'
            );

            // Start test context
            Test.startTest();
            try {
                StripeAPIService.createCustomer(customerWrapper);
                Assert.fail('Expected StripeException to be thrown after network error retries');
            } catch (StripeException ex) {
                Assert.isTrue(ex.getMessage().contains('Network error'), 'Exception message should indicate network error');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void testCreateCustomer_EmptyResponseBody() {
        System.runAs(getTestUser()) {
            // Custom mock for empty response body
            Test.setMock(HttpCalloutMock.class, new EmptyResponseMock());

            // Create test data
            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                'Test Customer',
                'test@example.com',
                '+1234567890'
            );

            // Start test context
            Test.startTest();
            String customerId = StripeAPIService.createCustomer(customerWrapper);
            Test.stopTest();

            // Verify the result
            Assert.areEqual(null, customerId, 'Customer ID should be null when response body is empty');
        }
    }

    // Mock class for empty response body
    private class EmptyResponseMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{}');
            res.setStatusCode(200);
            return res;
        }
    }

    @isTest
    static void testCreateCustomer_MalformedJSON() {
        System.runAs(getTestUser()) {
            // Custom mock for malformed JSON
            Test.setMock(HttpCalloutMock.class, new MalformedJSONMock());

            // Create test data
            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                'Test Customer',
                'test@example.com',
                '+1234567890'
            );

            // Start test context
            Test.startTest();
            try {
                StripeAPIService.createCustomer(customerWrapper);
                Assert.fail('Expected exception to be thrown for malformed JSON');
            } catch (Exception ex) {
                // JSON deserialization will throw an exception
                Assert.isTrue(ex instanceof JSONException || ex instanceof StripeException,
                    'Exception should be JSONException or StripeException');
            }
            Test.stopTest();
        }
    }

    // Mock class for malformed JSON response
    private class MalformedJSONMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"invalid json structure');
            res.setStatusCode(200);
            return res;
        }
    }
    @IsTest 
    static void processPricingPlanAfterInsert_insertPricingPlanAndSendToStripeAndGetProductId_success(){
        System.runAs(getTestUser()) {
            // Set mock to handle callouts
            Test.setMock(HttpCalloutMock.class, new StripeCalloutMock(200, 'products'));
            Stripe_Subscription__c subscription = new Stripe_Subscription__c(
                Product_Plan_Name__c = 'Orange'
            );
            insert subscription;
            Test.startTest();
            StripeWrapper.ProductWrapper productWrapper = new StripeWrapper.ProductWrapper(subscription.Product_Plan_Name__c);
            String productId = StripeAPIService.createProduct(productWrapper);
            Test.stopTest();
            Assert.areNotEqual(null, productId, 'ProductId was retrieved correctly');
        }
    }
    @IsTest
    static void processPricingPlanAfterInsert_insertPricingPlanAndSendToStripeAndGetPriceId_success(){
        // Set mock to handle callouts
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeCalloutMock(200, 'prices'));
            Stripe_Subscription__c subscription = new Stripe_Subscription__c(
                Product_Plan_Name__c = 'Orange'
            );
            insert subscription;
            Pricing_Plan__c pricePlan = new Pricing_Plan__c(
                ProductName__c = 'Orange',
                Currency__c = 'usd',
                Recurrency_Type__c = 'week',
                Amount__c = 24
            );
            insert pricePlan;
            Test.startTest();
            String requestBody = 'currency=' + EncodingUtil.urlEncode(pricePlan.Currency__c, 'UTF-8') +
                                            '&recurring[interval]=' + EncodingUtil.urlEncode(pricePlan.Recurrency_Type__c.toLowerCase(), 'UTF-8') +
                                            '&unit_amount=' + String.valueOf(pricePlan.Amount__c.longValue()) +
                                            '&product=' + EncodingUtil.urlEncode('prod_THa4qnfsETOFa2', 'UTF-8');
            String priceId = StripeAPIService.createPrice(requestBody);
            Test.stopTest();
            Assert.areNotEqual(null, priceId, 'ProductId was retrieved correctly');
        }
    }

    // ========== Tests for createSubscription ==========

    @isTest
    static void testCreateSubscription_Success() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeCalloutMock(200, 'subscriptions'));

            Test.startTest();
            String subscriptionId = StripeAPIService.createSubscription('cus_test123', 'price_test456', 'pm_test789');
            Test.stopTest();

            Assert.areNotEqual(null, subscriptionId, 'Subscription ID should not be null');
            Assert.areEqual('sub_1SL0dlF3hNTtzVuGK5JQfCji', subscriptionId, 'Subscription ID should match mock response');
        }
    }

    @isTest
    static void testCreateSubscription_Error() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeAPIErrorMock(400, 'invalid_request_error', 'Invalid price ID'));

            Test.startTest();
            try {
                StripeAPIService.createSubscription('cus_test123', 'invalid_price', 'pm_test789');
                Assert.fail('Expected StripeException to be thrown');
            } catch (StripeException ex) {
                Assert.areEqual(400, ex.httpStatusCode, 'HTTP status code should be 400');
            }
            Test.stopTest();
        }
    }

    // ========== Tests for createDefaultMethod ==========

    @isTest
    static void testCreateDefaultMethod_Success() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeCalloutMock(200, 'payment_methods'));

            Test.startTest();
            String paymentMethodId = StripeAPIService.createDefaultMethod('cus_test123');
            Test.stopTest();

            Assert.areNotEqual(null, paymentMethodId, 'Payment method ID should not be null');
            Assert.areEqual('pm_1SL0s9F3hNTtzVuGZuInzLMb', paymentMethodId, 'Payment method ID should match mock response');
        }
    }

    @isTest
    static void testCreateDefaultMethod_Error() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeAPIErrorMock(402, 'card_error', 'Card declined'));

            Test.startTest();
            try {
                StripeAPIService.createDefaultMethod('cus_test123');
                Assert.fail('Expected StripeException to be thrown');
            } catch (StripeException ex) {
                Assert.areEqual(402, ex.httpStatusCode, 'HTTP status code should be 402');
            }
            Test.stopTest();
        }
    }

    // ========== Tests for attachPaymentMethod ==========

    @isTest
    static void testAttachPaymentMethod_Success() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeCalloutMock(200, 'payment_methods'));

            Test.startTest();
            String attachedMethodId = StripeAPIService.attachPaymentMethod('pm_test123', 'cus_test456');
            Test.stopTest();

            Assert.areNotEqual(null, attachedMethodId, 'Attached payment method ID should not be null');
            Assert.areEqual('pm_1SL0s9F3hNTtzVuGZuInzLMb', attachedMethodId, 'Attached payment method ID should match mock response');
        }
    }

    @isTest
    static void testAttachPaymentMethod_Error() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeAPIErrorMock(404, 'invalid_request_error', 'Payment method not found'));

            Test.startTest();
            try {
                StripeAPIService.attachPaymentMethod('pm_invalid', 'cus_test456');
                Assert.fail('Expected StripeException to be thrown');
            } catch (StripeException ex) {
                Assert.areEqual(404, ex.httpStatusCode, 'HTTP status code should be 404');
            }
            Test.stopTest();
        }
    }

    // ========== Tests for updateCustomer ==========

    @isTest
    static void testUpdateCustomer_Success() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new UpdateCustomerSuccessMock());

            // Create test data
            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                'Updated Name',
                'updated@example.com',
                '+0987654321'
            );

            Test.startTest();
            String customerId = StripeAPIService.updateCustomer(customerWrapper, 'cus_test123');
            Test.stopTest();

            Assert.areNotEqual(null, customerId, 'Customer ID should not be null');
            Assert.areEqual('cus_test123', customerId, 'Customer ID should match the response');
        }
    }

    @isTest
    static void testUpdateCustomer_PartialUpdate() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new UpdateCustomerSuccessMock());

            // Create test data with only some fields
            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                null,  // No name update
                'newemail@example.com',  // Only update email
                null   // No phone update
            );

            Test.startTest();
            String customerId = StripeAPIService.updateCustomer(customerWrapper, 'cus_test123');
            Test.stopTest();

            Assert.areNotEqual(null, customerId, 'Customer ID should not be null for partial update');
            Assert.areEqual('cus_test123', customerId, 'Customer ID should match');
        }
    }

    @isTest
    static void testUpdateCustomer_AllFieldsNull() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new UpdateCustomerSuccessMock());

            // Create test data with all null fields
            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                null,
                null,
                null
            );

            Test.startTest();
            String customerId = StripeAPIService.updateCustomer(customerWrapper, 'cus_test123');
            Test.stopTest();

            // Should still work even with empty request body
            Assert.areNotEqual(null, customerId, 'Customer ID should not be null even with empty update');
        }
    }

    @isTest
    static void testUpdateCustomer_HttpFailure_400() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeAPIFailureMock(400, 'Invalid customer ID'));

            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                'Test Name',
                'test@example.com',
                '+1234567890'
            );

            Test.startTest();
            try {
                StripeAPIService.updateCustomer(customerWrapper, 'cus_invalid');
                Assert.fail('Expected StripeException to be thrown');
            } catch (StripeException ex) {
                Assert.areEqual(400, ex.httpStatusCode, 'HTTP status code should be 400');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void testUpdateCustomer_HttpFailure_404() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeAPIFailureMock(404, 'Customer not found'));

            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                'Test Name',
                'test@example.com',
                '+1234567890'
            );

            Test.startTest();
            try {
                StripeAPIService.updateCustomer(customerWrapper, 'cus_nonexistent');
                Assert.fail('Expected StripeException to be thrown');
            } catch (StripeException ex) {
                Assert.areEqual(404, ex.httpStatusCode, 'HTTP status code should be 404');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void testUpdateCustomer_RetryableError() {
        System.runAs(getTestUser()) {
            // Mock that fails with 503 then succeeds
            Test.setMock(HttpCalloutMock.class, new RetrySuccessMock(1));

            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                'Test Name',
                'test@example.com',
                '+1234567890'
            );

            Test.startTest();
            String customerId = StripeAPIService.updateCustomer(customerWrapper, 'cus_test123');
            Test.stopTest();

            Assert.areNotEqual(null, customerId, 'Customer ID should not be null after retry');
            Assert.areEqual('cus_test123', customerId, 'Customer ID should match after successful retry');
        }
    }

    @isTest
    static void testUpdateCustomer_SpecialCharacters() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new UpdateCustomerSuccessMock());

            // Test with special characters that need URL encoding
            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                'José María O\'Brien-Smith',
                'josé.maría@example.com',
                '+1 (555) 123-4567'
            );

            Test.startTest();
            String customerId = StripeAPIService.updateCustomer(customerWrapper, 'cus_test123');
            Test.stopTest();

            Assert.areNotEqual(null, customerId, 'Customer ID should handle special characters');
            Assert.areEqual('cus_test123', customerId, 'Customer ID should match');
        }
    }

    // Mock class for successful customer updates
    private class UpdateCustomerSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"id":"cus_test123","name":"Updated Name","email":"updated@example.com"}');
            return res;
        }
    }

    // ========== Tests for createSession ==========

    @isTest
    static void testCreateSession_Success() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeCalloutMock(200, 'sessions'));

            Test.startTest();
            StripeWrapper session = StripeAPIService.createSession('cus_test123', 'price_test456');
            Test.stopTest();

            Assert.areNotEqual(null, session, 'Session should not be null');
            Assert.areNotEqual(null, session.id, 'Session ID should not be null');
            Assert.areEqual('cs_test_a1APLw6wEYwl7TijcXg8BbeHzO4YFQJ3RYmUAFyMWab3YT4BSq9c9x3PlM', session.id, 'Session ID should match mock response');
        }
    }

    @isTest
    static void testCreateSession_Error() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeAPIErrorMock(400, 'invalid_request_error', 'Invalid customer ID'));

            Test.startTest();
            try {
                StripeAPIService.createSession('invalid_customer', 'price_test456');
                Assert.fail('Expected StripeException to be thrown');
            } catch (StripeException ex) {
                Assert.areEqual(400, ex.httpStatusCode, 'HTTP status code should be 400');
            }
            Test.stopTest();
        }
    }

    // ========== Error handling tests for createProduct ==========

    @isTest
    static void testCreateProduct_Error400() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeAPIErrorMock(400, 'invalid_request_error', 'Product name is required'));

            StripeWrapper.ProductWrapper productWrapper = new StripeWrapper.ProductWrapper('');

            Test.startTest();
            try {
                StripeAPIService.createProduct(productWrapper);
                Assert.fail('Expected StripeException to be thrown');
            } catch (StripeException ex) {
                Assert.areEqual(400, ex.httpStatusCode, 'HTTP status code should be 400');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void testCreateProduct_RateLimitError() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new RetryableMock(429, 3));

            StripeWrapper.ProductWrapper productWrapper = new StripeWrapper.ProductWrapper('Test Product');

            Test.startTest();
            try {
                StripeAPIService.createProduct(productWrapper);
                Assert.fail('Expected StripeException to be thrown after max retries');
            } catch (StripeException ex) {
                Assert.areEqual(429, ex.httpStatusCode, 'HTTP status code should be 429');
            }
            Test.stopTest();
        }
    }

    // ========== Error handling tests for createPrice ==========

    @isTest
    static void testCreatePrice_Error401() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new StripeAPIErrorMock(401, 'authentication_error', 'Invalid API key'));

            String requestBody = 'currency=usd&recurring[interval]=month&unit_amount=1000&product=prod_test123';

            Test.startTest();
            try {
                StripeAPIService.createPrice(requestBody);
                Assert.fail('Expected StripeException to be thrown');
            } catch (StripeException ex) {
                Assert.areEqual(401, ex.httpStatusCode, 'HTTP status code should be 401');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void testCreatePrice_ServerError() {
        System.runAs(getTestUser()) {
            Test.setMock(HttpCalloutMock.class, new RetryableMock(500, 3));

            String requestBody = 'currency=usd&recurring[interval]=month&unit_amount=1000&product=prod_test123';

            Test.startTest();
            try {
                StripeAPIService.createPrice(requestBody);
                Assert.fail('Expected StripeException to be thrown after max retries');
            } catch (StripeException ex) {
                Assert.areEqual(500, ex.httpStatusCode, 'HTTP status code should be 500');
            }
            Test.stopTest();
        }
    }

    // ========== Retry logic tests ==========

    @isTest
    static void testRetryLogic_RetryableErrorThrown() {
        System.runAs(getTestUser()) {
            // Mock that returns a retryable error
            Test.setMock(HttpCalloutMock.class, new RetryableMock(429, 1));

            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                'Test Customer',
                'test@example.com',
                '+1234567890'
            );

            Test.startTest();
            try {
                StripeAPIService.createCustomer(customerWrapper);
                Assert.fail('Expected StripeException to be thrown for retryable error');
            } catch (StripeException ex) {
                Assert.areEqual(429, ex.httpStatusCode, 'HTTP status code should be 429');
                Assert.areEqual(true, ex.isRetryable(), 'Error should be retryable');
                Assert.isTrue(ex.getMessage().contains('rate_limit'), 'Error should indicate rate limit');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void testRetryLogic_NonRetryableError() {
        System.runAs(getTestUser()) {
            // 400 errors should not be retried
            Test.setMock(HttpCalloutMock.class, new StripeAPIErrorMock(400, 'invalid_request_error', 'Bad Request'));

            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                'Test Customer',
                'test@example.com',
                '+1234567890'
            );

            Test.startTest();
            try {
                StripeAPIService.createCustomer(customerWrapper);
                Assert.fail('Expected StripeException to be thrown without retry');
            } catch (StripeException ex) {
                Assert.areEqual(400, ex.httpStatusCode, 'HTTP status code should be 400');
                Assert.areEqual(false, ex.isRetryable(), 'Error should not be retryable');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void testRetryLogic_ServerErrorRetryable() {
        System.runAs(getTestUser()) {
            // Mock that returns a server error which is retryable
            Test.setMock(HttpCalloutMock.class, new RetryableMock(503, 1));

            StripeWrapper.CustomerWrapper customerWrapper = new StripeWrapper.CustomerWrapper(
                'Test Customer',
                'test@example.com',
                '+1234567890'
            );

            Test.startTest();
            try {
                StripeAPIService.createCustomer(customerWrapper);
                Assert.fail('Expected StripeException to be thrown for server error');
            } catch (StripeException ex) {
                Assert.areEqual(503, ex.httpStatusCode, 'HTTP status code should be 503');
                Assert.areEqual(true, ex.isRetryable(), 'Server error should be retryable');
            }
            Test.stopTest();
        }
    }

    // ========== Additional Mock Classes ==========

    // Mock for Stripe API errors with detailed error response
    private class StripeAPIErrorMock implements HttpCalloutMock {
        private Integer statusCode;
        private String errorType;
        private String errorMessage;

        public StripeAPIErrorMock(Integer statusCode, String errorType, String errorMessage) {
            this.statusCode = statusCode;
            this.errorType = errorType;
            this.errorMessage = errorMessage;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":{"type":"' + errorType + '","message":"' + errorMessage + '"}}');
            res.setStatusCode(statusCode);
            return res;
        }
    }

    // Mock that fails a specified number of times with retryable errors, then succeeds
    private class RetrySuccessMock implements HttpCalloutMock {
        private Integer failuresBeforeSuccess;
        private Integer callCount = 0;

        public RetrySuccessMock(Integer failuresBeforeSuccess) {
            this.failuresBeforeSuccess = failuresBeforeSuccess;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            if (callCount < failuresBeforeSuccess) {
                callCount++;
                res.setStatusCode(503);
                res.setBody('{"error":{"type":"api_error","message":"Service temporarily unavailable"}}');
            } else {
                res.setStatusCode(200);
                res.setBody('{"id":"cus_test123","name":"Test Customer","email":"test@example.com"}');
            }

            return res;
        }
    }

    // Mock that always fails with a retryable error (for testing max retries)
    private class RetryableMock implements HttpCalloutMock {
        private Integer statusCode;
        private Integer maxCalls;
        private Integer callCount = 0;

        public RetryableMock(Integer statusCode, Integer maxCalls) {
            this.statusCode = statusCode;
            this.maxCalls = maxCalls;
        }

        public HTTPResponse respond(HTTPRequest req) {
            callCount++;
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(statusCode);

            String errorType = statusCode == 429 ? 'rate_limit_error' : 'api_error';
            String errorMessage = statusCode == 429 ? 'Rate limit exceeded' : 'Server error';
            res.setBody('{"error":{"type":"' + errorType + '","message":"' + errorMessage + '"}}');

            return res;
        }
    }
}