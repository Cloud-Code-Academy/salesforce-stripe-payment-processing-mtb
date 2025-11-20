/**
 * @description Test class for PaymentTransactionTriggerHelper
 * Tests invoice status updates when payment transactions succeed
 *
 * @author Cloud Code
 * @date 2025
 */
@isTest
private class PaymentTransactionTriggerHelperTest {

    /**
     * @description Sets up test data for all test methods
     */
    @TestSetup
    static void setup() {
        // Create test Contact (Customer)
        Contact testCustomer = new Contact(
            FirstName = 'Test',
            LastName = 'Customer',
            Email = 'test@example.com',
            Stripe_Customer_ID__c = 'cus_test123'
        );
        insert testCustomer;

        // Create test Stripe Subscription
        Stripe_Subscription__c testSubscription = new Stripe_Subscription__c(
            Contact__c = testCustomer.Id,
            Status__c = 'active',
            Stripe_Subscription_ID__c = 'sub_test123'
        );
        insert testSubscription;

        // Create test Stripe Invoices
        List<Stripe_Invoice__c> testInvoices = new List<Stripe_Invoice__c>();

        // Invoice 1: Open status (will be updated to paid)
        testInvoices.add(new Stripe_Invoice__c(
            Contact__c = testCustomer.Id,
            Stripe_Subscription__c = testSubscription.Id,
            Status__c = 'open',
            Amount__c = 100.00,
            Stripe_Invoice_ID__c = 'in_test001'
        ));

        // Invoice 2: Already paid (should not be updated)
        testInvoices.add(new Stripe_Invoice__c(
            Contact__c = testCustomer.Id,
            Stripe_Subscription__c = testSubscription.Id,
            Status__c = 'paid',
            Amount__c = 200.00,
            Stripe_Invoice_ID__c = 'in_test002'
        ));

        // Invoice 3: Draft status (will be updated to paid)
        testInvoices.add(new Stripe_Invoice__c(
            Contact__c = testCustomer.Id,
            Stripe_Subscription__c = testSubscription.Id,
            Status__c = 'draft',
            Amount__c = 150.00,
            Stripe_Invoice_ID__c = 'in_test003'
        ));

        insert testInvoices;
    }

    /**
     * @description Test that invoice status updates to paid when payment transaction is created as succeeded
     */
    @isTest
    static void testInvoiceStatusUpdateOnPaymentInsert() {
        // Get test invoice
        Stripe_Invoice__c testInvoice = [
            SELECT Id, Status__c
            FROM Stripe_Invoice__c
            WHERE Stripe_Invoice_ID__c = 'in_test001'
            LIMIT 1
        ];

        // Verify initial status
        System.assertEquals('open', testInvoice.Status__c, 'Invoice should initially be open');

        // Create payment transaction with succeeded status
        Test.startTest();
        Payment_Transaction__c payment = new Payment_Transaction__c(
            Stripe_Invoice__c = testInvoice.Id,
            Status__c = 'succeeded',
            Amount__c = 100.00,
            Currency__c = 'USD',
            Stripe_Payment_Intent_ID__c = 'pi_test001',
            Transaction_Type__c = 'initial_payment',
            Payment_Method_Type__c = 'card',
            Transaction_Date__c = DateTime.now()
        );
        insert payment;
        Test.stopTest();

        // Verify invoice status was updated
        testInvoice = [
            SELECT Id, Status__c
            FROM Stripe_Invoice__c
            WHERE Id = :testInvoice.Id
        ];
        System.assertEquals('paid', testInvoice.Status__c, 'Invoice status should be updated to paid');
    }

    /**
     * @description Test that invoice status updates to paid when payment transaction is updated to succeeded
     */
    @isTest
    static void testInvoiceStatusUpdateOnPaymentUpdate() {
        // Get test invoice
        Stripe_Invoice__c testInvoice = [
            SELECT Id, Status__c
            FROM Stripe_Invoice__c
            WHERE Stripe_Invoice_ID__c = 'in_test001'
            LIMIT 1
        ];

        // Create payment transaction with processing status
        Payment_Transaction__c payment = new Payment_Transaction__c(
            Stripe_Invoice__c = testInvoice.Id,
            Status__c = 'processing',
            Amount__c = 100.00,
            Currency__c = 'USD',
            Stripe_Payment_Intent_ID__c = 'pi_test001',
            Transaction_Type__c = 'initial_payment',
            Payment_Method_Type__c = 'card',
            Transaction_Date__c = DateTime.now()
        );
        insert payment;

        // Verify invoice is still open
        testInvoice = [
            SELECT Id, Status__c
            FROM Stripe_Invoice__c
            WHERE Id = :testInvoice.Id
        ];
        System.assertEquals('open', testInvoice.Status__c, 'Invoice should still be open');

        // Update payment transaction to succeeded
        Test.startTest();
        payment.Status__c = 'succeeded';
        update payment;
        Test.stopTest();

        // Verify invoice status was updated
        testInvoice = [
            SELECT Id, Status__c
            FROM Stripe_Invoice__c
            WHERE Id = :testInvoice.Id
        ];
        System.assertEquals('paid', testInvoice.Status__c, 'Invoice status should be updated to paid');
    }

    /**
     * @description Test that already paid invoices are not updated
     */
    @isTest
    static void testAlreadyPaidInvoiceNotUpdated() {
        // Get already paid invoice
        Stripe_Invoice__c paidInvoice = [
            SELECT Id, Status__c
            FROM Stripe_Invoice__c
            WHERE Stripe_Invoice_ID__c = 'in_test002'
            LIMIT 1
        ];

        // Verify initial status is paid
        System.assertEquals('paid', paidInvoice.Status__c, 'Invoice should initially be paid');

        // Create payment transaction with succeeded status
        Test.startTest();
        Payment_Transaction__c payment = new Payment_Transaction__c(
            Stripe_Invoice__c = paidInvoice.Id,
            Status__c = 'succeeded',
            Amount__c = 200.00,
            Currency__c = 'USD',
            Stripe_Payment_Intent_ID__c = 'pi_test002',
            Transaction_Type__c = 'recurring_payment',
            Payment_Method_Type__c = 'card',
            Transaction_Date__c = DateTime.now()
        );
        insert payment;
        Test.stopTest();

        // Verify invoice status is still paid (no unnecessary update)
        paidInvoice = [
            SELECT Id, Status__c
            FROM Stripe_Invoice__c
            WHERE Id = :paidInvoice.Id
        ];
        System.assertEquals('paid', paidInvoice.Status__c, 'Invoice status should remain paid');
    }

    /**
     * @description Test bulk operations - multiple payment transactions at once
     */
    @isTest
    static void testBulkPaymentTransactions() {
        // Get test invoices
        List<Stripe_Invoice__c> testInvoices = [
            SELECT Id, Status__c, Stripe_Invoice_ID__c
            FROM Stripe_Invoice__c
            WHERE Stripe_Invoice_ID__c IN ('in_test001', 'in_test003')
            ORDER BY Stripe_Invoice_ID__c
        ];

        // Create multiple payment transactions
        List<Payment_Transaction__c> payments = new List<Payment_Transaction__c>();
        Integer counter = 1;
        for (Stripe_Invoice__c invoice : testInvoices) {
            payments.add(new Payment_Transaction__c(
                Stripe_Invoice__c = invoice.Id,
                Status__c = 'succeeded',
                Amount__c = 100.00 * counter,
                Currency__c = 'USD',
                Stripe_Payment_Intent_ID__c = 'pi_bulk_' + counter,
                Transaction_Type__c = 'initial_payment',
                Payment_Method_Type__c = 'card',
                Transaction_Date__c = DateTime.now()
            ));
            counter++;
        }

        Test.startTest();
        insert payments;
        Test.stopTest();

        // Verify all invoices were updated to paid
        testInvoices = [
            SELECT Id, Status__c
            FROM Stripe_Invoice__c
            WHERE Id IN :new Map<Id, Stripe_Invoice__c>(testInvoices).keySet()
        ];

        for (Stripe_Invoice__c invoice : testInvoices) {
            System.assertEquals('paid', invoice.Status__c, 'All invoices should be updated to paid');
        }
    }

    /**
     * @description Test that canceled payment transactions don't update invoice status
     */
    @isTest
    static void testFailedPaymentDoesNotUpdateInvoice() {
        // Get test invoice
        Stripe_Invoice__c testInvoice = [
            SELECT Id, Status__c
            FROM Stripe_Invoice__c
            WHERE Stripe_Invoice_ID__c = 'in_test001'
            LIMIT 1
        ];

        // Create payment transaction with canceled status
        Test.startTest();
        Payment_Transaction__c payment = new Payment_Transaction__c(
            Stripe_Invoice__c = testInvoice.Id,
            Status__c = 'canceled',
            Amount__c = 100.00,
            Currency__c = 'USD',
            Stripe_Payment_Intent_ID__c = 'pi_test_canceled',
            Transaction_Type__c = 'initial_payment',
            Payment_Method_Type__c = 'card',
            Transaction_Date__c = DateTime.now(),
            Failure_Reason__c = 'Card declined'
        );
        insert payment;
        Test.stopTest();

        // Verify invoice status was NOT updated
        testInvoice = [
            SELECT Id, Status__c
            FROM Stripe_Invoice__c
            WHERE Id = :testInvoice.Id
        ];
        System.assertEquals('open', testInvoice.Status__c, 'Invoice status should remain open for canceled payment');
    }

    /**
     * @description Test status change from succeeded to another status doesn't affect invoice
     */
    @isTest
    static void testStatusChangeFromSucceeded() {
        // Get test invoice
        Stripe_Invoice__c testInvoice = [
            SELECT Id, Status__c
            FROM Stripe_Invoice__c
            WHERE Stripe_Invoice_ID__c = 'in_test001'
            LIMIT 1
        ];

        // Create and insert succeeded payment
        Payment_Transaction__c payment = new Payment_Transaction__c(
            Stripe_Invoice__c = testInvoice.Id,
            Status__c = 'succeeded',
            Amount__c = 100.00,
            Currency__c = 'USD',
            Stripe_Payment_Intent_ID__c = 'pi_test001',
            Transaction_Type__c = 'initial_payment',
            Payment_Method_Type__c = 'card',
            Transaction_Date__c = DateTime.now()
        );
        insert payment;

        // Verify invoice was updated to paid
        testInvoice = [
            SELECT Id, Status__c
            FROM Stripe_Invoice__c
            WHERE Id = :testInvoice.Id
        ];
        System.assertEquals('paid', testInvoice.Status__c, 'Invoice should be paid');

        // Now update payment to canceled (this shouldn't trigger any invoice update)
        Test.startTest();
        payment.Status__c = 'canceled';
        update payment;
        Test.stopTest();

        // Verify invoice remains paid
        testInvoice = [
            SELECT Id, Status__c
            FROM Stripe_Invoice__c
            WHERE Id = :testInvoice.Id
        ];
        System.assertEquals('paid', testInvoice.Status__c, 'Invoice should remain paid even if payment is later canceled');
    }

    /**
     * @description Test helper method getSuccessfulTransactions
     */
    @isTest
    static void testGetSuccessfulTransactions() {
        // Create test payment transactions
        List<Payment_Transaction__c> testTransactions = new List<Payment_Transaction__c>();

        // Get an invoice for testing
        Stripe_Invoice__c testInvoice = [
            SELECT Id FROM Stripe_Invoice__c LIMIT 1
        ];

        // Create various status transactions
        testTransactions.add(new Payment_Transaction__c(
            Stripe_Invoice__c = testInvoice.Id,
            Status__c = 'succeeded',
            Amount__c = 100.00
        ));
        testTransactions.add(new Payment_Transaction__c(
            Stripe_Invoice__c = testInvoice.Id,
            Status__c = 'failed',
            Amount__c = 200.00
        ));
        testTransactions.add(new Payment_Transaction__c(
            Stripe_Invoice__c = testInvoice.Id,
            Status__c = 'processing',
            Amount__c = 150.00
        ));

        Test.startTest();
        // Test for insert scenario (no old map)
        List<Payment_Transaction__c> successfulOnes = PaymentTransactionTriggerHelper.getSuccessfulTransactions(
            testTransactions,
            null
        );
        Test.stopTest();

        // Should only return the succeeded one
        System.assertEquals(1, successfulOnes.size(), 'Should return only succeeded transaction');
        System.assertEquals('succeeded', successfulOnes[0].Status__c, 'Transaction should have succeeded status');
    }
}