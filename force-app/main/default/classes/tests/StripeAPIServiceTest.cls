@isTest
private class StripeAPIServiceTest {

    private static User testUser;

    @TestSetup
    static void setupTestData() {
        // Create test user with Stripe API Access permission set
        testUser = TestDataFactory.createUserWithPermissionSets(
            new List<String>{'Stripe_API_Access'}
        );
    }

    // Helper method to get test user
    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'testuser%@testorg.com' LIMIT 1];
    }

    // Mock class for successful HTTP callout
    private class StripeAPISuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Verify the request
            Assert.areEqual('POST', req.getMethod());
            Assert.areEqual('callout:StripeAPI/v1/customers', req.getEndpoint());
            Assert.areEqual('application/x-www-form-urlencoded', req.getHeader('Content-Type'));

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
            String customerId = StripeAPIService.createCustomer(customerWrapper);
            Test.stopTest();

            // Verify the result - should return null due to exception handling
            Assert.areEqual(null, customerId, 'Customer ID should be null when HTTP request fails');
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
            String customerId = StripeAPIService.createCustomer(customerWrapper);
            Test.stopTest();

            // Verify the result
            Assert.areEqual(null, customerId, 'Customer ID should be null when authentication fails');
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
            String customerId = StripeAPIService.createCustomer(customerWrapper);
            Test.stopTest();

            // Verify the result
            Assert.areEqual(null, customerId, 'Customer ID should be null when server error occurs');
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
            String customerId = StripeAPIService.createCustomer(customerWrapper);
            Test.stopTest();

            // Verify the result - should return null due to exception handling
            Assert.areEqual(null, customerId, 'Customer ID should be null when callout exception occurs');
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
            String customerId = StripeAPIService.createCustomer(customerWrapper);
            Test.stopTest();

            // Verify the result
            Assert.areEqual(null, customerId, 'Customer ID should be null when JSON is malformed');
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
}
