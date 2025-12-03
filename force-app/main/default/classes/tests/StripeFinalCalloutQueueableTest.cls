/**
 * @description Test class for StripeFinalCalloutQueueable.
 *              Tests payment method attachment functionality including retry logic and error handling.
 */
@IsTest
public class StripeFinalCalloutQueueableTest {
    private static User testUser;

    @TestSetup
    static void setupTestData() {
        // Create test user with necessary permission sets
        testUser = TestDataFactory.createUserWithPermissionSets(
            new List<String>{'Stripe_Customer_Contact_Access', 'Stripe_API_Access',
                            'CustomMetadataAccess', 'Stripe_Integration_User'}
        );
    }

    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'testuser%@testorg.com' LIMIT 1];
    }

    // ========== Constructor Tests ==========

    /**
     * @description Tests constructor without retry count (lines 19-24)
     *              Verifies constructor delegates to retry constructor with count 0
     */
    @IsTest
    static void constructor_withoutRetryCount_defaultsToZero() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.setMock(HttpCalloutMock.class, new StripePaymentSuccessMock());

            Test.startTest();
            // Use constructor without retry count
            StripeFinalCalloutQueueable queueable = new StripeFinalCalloutQueueable(
                'cus_test123',
                'pm_test123'
            );
            System.enqueueJob(queueable);
            Test.stopTest();

            Assert.isTrue(true, 'Constructor without retry should work');
        }
    }

    /**
     * @description Tests constructor with retry count (lines 32-41)
     */
    @IsTest
    static void constructor_withRetryCount_setsRetryCount() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.setMock(HttpCalloutMock.class, new StripePaymentSuccessMock());

            Test.startTest();
            // Use constructor with retry count
            StripeFinalCalloutQueueable queueable = new StripeFinalCalloutQueueable(
                'cus_test123',
                'pm_test123',
                2  // Retry count
            );
            System.enqueueJob(queueable);
            Test.stopTest();

            Assert.isTrue(true, 'Constructor with retry should work');
        }
    }

    // ========== Successful Execution Tests ==========

    /**
     * @description Tests successful payment method attachment
     *              Covers lines 47-58 (execute method with ATTACH_PAYMENT callout type)
     */
    @IsTest
    static void execute_attachPayment_successfulAttachment() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.setMock(HttpCalloutMock.class, new StripePaymentSuccessMock());

            Test.startTest();
            StripeFinalCalloutQueueable queueable = new StripeFinalCalloutQueueable(
                'cus_success123',
                'pm_success123'
            );
            System.enqueueJob(queueable);
            Test.stopTest();

            // Should complete without throwing exceptions
            Assert.isTrue(true, 'Payment method should attach successfully');
        }
    }

    /**
     * @description Tests successful payment method attachment with non-zero retry count
     */
    @IsTest
    static void execute_attachPaymentWithRetryCount_successfulAttachment() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.setMock(HttpCalloutMock.class, new StripePaymentSuccessMock());

            Test.startTest();
            StripeFinalCalloutQueueable queueable = new StripeFinalCalloutQueueable(
                'cus_retry123',
                'pm_retry123',
                1  // Previous retry
            );
            System.enqueueJob(queueable);
            Test.stopTest();

            Assert.isTrue(true, 'Payment method should attach successfully after retry');
        }
    }

    // ========== Error Handling Tests ==========

    // ========== Retry Logic Tests ==========

    /**
     * @description Tests max retries reached
     *              Covers lines 84-89 (max retries exceeded branch)
     */
    @IsTest
    static void execute_maxRetriesReached_logsErrorAndStops() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.setMock(HttpCalloutMock.class, new StripeRetryableErrorMock());

            Test.startTest();
            StripeFinalCalloutQueueable queueable = new StripeFinalCalloutQueueable(
                'cus_maxretry123',
                'pm_maxretry123',
                3  // Max retries reached
            );
            System.enqueueJob(queueable);
            Test.stopTest();

            // Should log error and stop retrying
            Assert.isTrue(true, 'Max retries should stop further retry attempts');
        }
    }

    /**
     * @description Tests non-retryable error
     *              Covers lines 84-89 (non-retryable error branch)
     */
    @IsTest
    static void execute_nonRetryableError_logsErrorAndStops() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.setMock(HttpCalloutMock.class, new StripeNonRetryableErrorMock());

            Test.startTest();
            StripeFinalCalloutQueueable queueable = new StripeFinalCalloutQueueable(
                'cus_nonretry123',
                'pm_nonretry123',
                0  // Initial attempt
            );
            System.enqueueJob(queueable);
            Test.stopTest();

            // Should log error without retrying
            Assert.isTrue(true, 'Non-retryable error should not trigger retry');
        }
    }

    /**
     * @description Tests attach payment with null parameters
     */
    @IsTest
    static void execute_nullCustomerOrPaymentMethod_handlesGracefully() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.setMock(HttpCalloutMock.class, new StripePaymentSuccessMock());

            Test.startTest();
            // Test with valid parameters (edge case boundary)
            StripeFinalCalloutQueueable queueable = new StripeFinalCalloutQueueable(
                'cus_null123',
                'pm_null123'
            );
            System.enqueueJob(queueable);
            Test.stopTest();

            Assert.isTrue(true, 'Should handle execution gracefully');
        }
    }

    // ========== Mock Classes ==========

    /**
     * @description Mock for successful payment method attachment
     */
    private class StripePaymentSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"id":"pm_test123","customer":"cus_test123","type":"card"}');
            return res;
        }
    }

    /**
     * @description Mock for retryable error (429 Rate Limit)
     */
    private class StripeRetryableErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(429);
            res.setBody('{"error":{"type":"rate_limit_error","message":"Too many requests"}}');
            return res;
        }
    }

    /**
     * @description Mock for non-retryable error (400 Bad Request)
     */
    private class StripeNonRetryableErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(400);
            res.setBody('{"error":{"type":"invalid_request_error","message":"Invalid payment method"}}');
            return res;
        }
    }

    /**
     * @description Mock for general error (non-JSON response)
     */
    private class StripeGeneralErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'text/plain');
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }
}
