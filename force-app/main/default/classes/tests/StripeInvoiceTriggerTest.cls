@isTest
private class StripeInvoiceTriggerTest {

    private static User testUser;

    @TestSetup
    static void setupTestData() {
        // Create test user with required permission sets
        testUser = TestDataFactory.createUserWithPermissionSets(
            new List<String>{'Stripe_Customer_Contact_Access', 'Stripe_API_Access', 'Stripe_Subscription_Access', 'Stripe_Invoice_Access'}
        );

        // Create test Contact
        Contact testContact = TestDataFactory.createContacts(1)[0];

        // Create test Stripe Customer
        Stripe_Customer__c customer = TestDataFactory.createStripeCustomers(1, testContact.Id)[0];

        // Create test Stripe Subscription
        Stripe_Subscription__c subscription = TestDataFactory.createStripeSubscriptions(1, customer.Id)[0];
    }

    // Helper method to get test user
    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'testuser%@testorg.com' LIMIT 1];
    }

    // ========== REVENUE ROLLUP TESTS ==========

    /**
     * Test revenue rollup to customer on invoice insert
     */
    @isTest
    static void testRollupRevenueToCustomer_OnInsert() {
        System.runAs(getTestUser()) {
            // Get test data
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = [SELECT Id FROM Stripe_Subscription__c LIMIT 1];

            // Create multiple paid invoices
            Test.startTest();
            List<Stripe_Invoice__c> invoices = TestDataFactory.createStripeInvoices(3, customer.Id, subscription.Id, 'paid');
            Test.stopTest();

            // Verify Total_Revenue__c was updated
            customer = [SELECT Id, Total_Revenue__c FROM Stripe_Customer__c WHERE Id = :customer.Id];
            Assert.areEqual(89.97, customer.Total_Revenue__c, 'Total revenue should be sum of 3 paid invoices (3 x 29.99)');
        }
    }

    /**
     * Test revenue rollup to subscription on invoice insert
     */
    @isTest
    static void testRollupRevenueToSubscription_OnInsert() {
        System.runAs(getTestUser()) {
            // Get test data
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = [SELECT Id FROM Stripe_Subscription__c LIMIT 1];

            // Create multiple invoices (both paid and unpaid)
            Test.startTest();
            List<Stripe_Invoice__c> paidInvoices = TestDataFactory.createStripeInvoices(2, customer.Id, subscription.Id, 'paid');
            List<Stripe_Invoice__c> openInvoices = TestDataFactory.createStripeInvoices(1, customer.Id, subscription.Id, 'open');
            Test.stopTest();

            // Verify Total_Invoiced__c includes all invoices
            subscription = [SELECT Id, Total_Invoiced__c FROM Stripe_Subscription__c WHERE Id = :subscription.Id];
            Assert.areEqual(89.97, subscription.Total_Invoiced__c, 'Total invoiced should include all invoices (3 x 29.99)');
        }
    }

    /**
     * Test revenue rollup on status change from open to paid
     */
    @isTest
    static void testRollupRevenue_OnStatusUpdate() {
        System.runAs(getTestUser()) {
            // Get test data
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = [SELECT Id FROM Stripe_Subscription__c LIMIT 1];

            // Create an open invoice
            List<Stripe_Invoice__c> invoices = TestDataFactory.createStripeInvoices(1, customer.Id, subscription.Id, 'open');

            // Change status to paid
            Test.startTest();
            invoices[0].Status__c = 'paid';
            update invoices[0];
            Test.stopTest();

            // Verify Total_Revenue__c was updated
            customer = [SELECT Id, Total_Revenue__c FROM Stripe_Customer__c WHERE Id = :customer.Id];
            Assert.areEqual(29.99, customer.Total_Revenue__c, 'Total revenue should include newly paid invoice');
        }
    }

    // ========== FINANCE NOTIFICATIONS TESTS ==========

    /**
     * Test failure notifications on invoice insert with uncollectible status
     */
    @isTest
    static void testSendFailureNotifications_OnInsert() {
        System.runAs(getTestUser()) {
            // Get test data
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = [SELECT Id FROM Stripe_Subscription__c LIMIT 1];

            // Count existing tasks
            Integer taskCountBefore = [SELECT COUNT() FROM Task];

            // Create uncollectible invoice
            Test.startTest();
            List<Stripe_Invoice__c> invoices = TestDataFactory.createStripeInvoices(1, customer.Id, subscription.Id, 'uncollectible');
            Test.stopTest();

            // Verify follow-up task was created
            Integer taskCountAfter = [SELECT COUNT() FROM Task];
            Assert.areEqual(taskCountBefore + 1, taskCountAfter, 'One follow-up task should be created for failed payment');

            Task followUpTask = [SELECT Subject, Priority FROM Task WHERE WhatId = :invoices[0].Id];
            Assert.isTrue(followUpTask.Subject.contains('failed payment'), 'Task subject should mention failed payment');
            Assert.areEqual('Normal', followUpTask.Priority, 'Task priority should be Normal for uncollectible');
        }
    }

    /**
     * Test high-priority notifications for exhausted dunning
     */
    @isTest
    static void testSendFailureNotifications_ExhaustedDunning() {
        System.runAs(getTestUser()) {
            // Get test data
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = [SELECT Id FROM Stripe_Subscription__c LIMIT 1];

            // Create invoice with exhausted dunning
            Stripe_Invoice__c invoice = new Stripe_Invoice__c(
                Stripe_Customer__c = customer.Id,
                Stripe_Subscription__c = subscription.Id,
                Stripe_Invoice_ID__c = 'inv_exhausted',
                Amount__c = 29.99,
                Status__c = 'open',
                Dunning_Status__c = 'exhausted'
            );

            Test.startTest();
            insert invoice;
            Test.stopTest();

            // Verify high-priority task was created
            Task followUpTask = [SELECT Subject, Priority FROM Task WHERE WhatId = :invoice.Id];
            Assert.isTrue(followUpTask.Subject.contains('URGENT'), 'Task subject should be marked as URGENT');
            Assert.areEqual('High', followUpTask.Priority, 'Task priority should be High for exhausted dunning');
        }
    }

    // ========== HEALTH SCORING TESTS ==========

    /**
     * Test customer health score calculation with all paid invoices
     */
    @isTest
    static void testCalculateHealthScore_AllPaid() {
        // Get test data
        Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
        Stripe_Subscription__c subscription = [SELECT Id FROM Stripe_Subscription__c LIMIT 1];

        // Create all paid invoices
        Test.startTest();
        List<Stripe_Invoice__c> invoices = TestDataFactory.createStripeInvoices(5, customer.Id, subscription.Id, 'paid');
        Test.stopTest();

        // Verify perfect health score
        customer = [SELECT Id, Health_Score__c FROM Stripe_Customer__c WHERE Id = :customer.Id];
        Assert.areEqual(100, customer.Health_Score__c, 'Health score should be 100 for all paid invoices');
    }

    /**
     * Test customer health score calculation with mixed payment history
     */
    @isTest
    static void testCalculateHealthScore_MixedHistory() {
        System.runAs(getTestUser()) {
            // Get test data
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = [SELECT Id FROM Stripe_Subscription__c LIMIT 1];

            // Create mixed invoice history
            Test.startTest();
            // 3 paid, 1 uncollectible, 1 with exhausted dunning
            List<Stripe_Invoice__c> paidInvoices = TestDataFactory.createStripeInvoices(3, customer.Id, subscription.Id, 'paid');

            Stripe_Invoice__c uncollectibleInvoice = new Stripe_Invoice__c(
                Stripe_Customer__c = customer.Id,
                Stripe_Subscription__c = subscription.Id,
                Stripe_Invoice_ID__c = 'inv_uncoll',
                Amount__c = 29.99,
                Status__c = 'uncollectible',
                Dunning_Status__c = 'none'
            );
            insert uncollectibleInvoice;

            Stripe_Invoice__c exhaustedInvoice = new Stripe_Invoice__c(
                Stripe_Customer__c = customer.Id,
                Stripe_Subscription__c = subscription.Id,
                Stripe_Invoice_ID__c = 'inv_exhaust',
                Amount__c = 29.99,
                Status__c = 'open',
                Dunning_Status__c = 'exhausted'
            );
            insert exhaustedInvoice;
            Test.stopTest();

            // Verify reduced health score
            // 60% paid (3/5), 20% failed penalty, 30% dunning penalty
            customer = [SELECT Id, Health_Score__c FROM Stripe_Customer__c WHERE Id = :customer.Id];
            Assert.isTrue(customer.Health_Score__c < 60, 'Health score should be reduced for mixed payment history');
        }
    }

    // ========== CHURN RISK TESTS ==========

    /**
     * Test churn risk detection - Low risk
     */
    @isTest
    static void testDetectChurnRisk_Low() {
        System.runAs(getTestUser()) {
            // Get test data
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = [SELECT Id FROM Stripe_Subscription__c LIMIT 1];

            // Create mostly paid invoices
            Test.startTest();
            List<Stripe_Invoice__c> invoices = TestDataFactory.createStripeInvoices(5, customer.Id, subscription.Id, 'paid');
            Test.stopTest();

            // Verify low churn risk
            customer = [SELECT Id, Churn_Risk__c FROM Stripe_Customer__c WHERE Id = :customer.Id];
            Assert.areEqual('Low', customer.Churn_Risk__c, 'Churn risk should be Low for good payment history');
        }
    }

    /**
     * Test churn risk detection - Critical risk
     */
    @isTest
    static void testDetectChurnRisk_Critical() {
        System.runAs(getTestUser()) {
            // Get test data
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = [SELECT Id FROM Stripe_Subscription__c LIMIT 1];

            // Create multiple exhausted dunning invoices
            Test.startTest();
            List<Stripe_Invoice__c> invoices = new List<Stripe_Invoice__c>();
            for (Integer i = 0; i < 3; i++) {
                invoices.add(new Stripe_Invoice__c(
                    Stripe_Customer__c = customer.Id,
                    Stripe_Subscription__c = subscription.Id,
                    Stripe_Invoice_ID__c = 'inv_fail_' + i,
                    Amount__c = 29.99,
                    Status__c = 'uncollectible',
                    Dunning_Status__c = 'exhausted'
                ));
            }
            insert invoices;
            Test.stopTest();

            // Verify critical churn risk
            customer = [SELECT Id, Churn_Risk__c FROM Stripe_Customer__c WHERE Id = :customer.Id];
            Assert.areEqual('Critical', customer.Churn_Risk__c, 'Churn risk should be Critical for multiple exhausted dunning');
        }
    }

    /**
     * Test churn risk updates on dunning status change
     */
    @isTest
    static void testDetectChurnRisk_OnDunningChange() {
        System.runAs(getTestUser()) {
            // Get test data
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = [SELECT Id FROM Stripe_Subscription__c LIMIT 1];

            // Create invoice with trying dunning
            Stripe_Invoice__c invoice = new Stripe_Invoice__c(
                Stripe_Customer__c = customer.Id,
                Stripe_Subscription__c = subscription.Id,
                Stripe_Invoice_ID__c = 'inv_dunning',
                Amount__c = 29.99,
                Status__c = 'open',
                Dunning_Status__c = 'trying'
            );
            insert invoice;

            // Update dunning status to exhausted
            Test.startTest();
            invoice.Dunning_Status__c = 'exhausted';
            update invoice;
            Test.stopTest();

            // Verify churn risk was updated
            customer = [SELECT Id, Churn_Risk__c FROM Stripe_Customer__c WHERE Id = :customer.Id];
            Assert.areNotEqual('Low', customer.Churn_Risk__c, 'Churn risk should increase when dunning is exhausted');
        }
    }

    // ========== DUNNING ESCALATION TESTS ==========

    /**
     * Test dunning escalation logging
     */
    @isTest
    static void testEscalateDunningStatus() {
        System.runAs(getTestUser()) {
            // Get test data
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = [SELECT Id FROM Stripe_Subscription__c LIMIT 1];

            // Create invoice with trying dunning
            Stripe_Invoice__c invoice = new Stripe_Invoice__c(
                Stripe_Customer__c = customer.Id,
                Stripe_Subscription__c = subscription.Id,
                Stripe_Invoice_ID__c = 'inv_escalate',
                Amount__c = 29.99,
                Status__c = 'open',
                Dunning_Status__c = 'trying'
            );
            insert invoice;

            // Update status to uncollectible (triggers escalation logging)
            Test.startTest();
            invoice.Status__c = 'uncollectible';
            update invoice;
            Test.stopTest();

            // Verify invoice was processed (no exceptions thrown)
            Stripe_Invoice__c updatedInvoice = [SELECT Id, Status__c FROM Stripe_Invoice__c WHERE Id = :invoice.Id];
            Assert.areEqual('uncollectible', updatedInvoice.Status__c, 'Invoice status should be updated');
        }
    }

    /**
     * Test MRR calculation for active subscriptions
     */
    @isTest
    static void testMRRCalculation() {
        System.runAs(getTestUser()) {
            // Get test data
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = [SELECT Id, Amount__c FROM Stripe_Subscription__c LIMIT 1];

            // Create paid invoice to trigger MRR calculation
            Test.startTest();
            List<Stripe_Invoice__c> invoices = TestDataFactory.createStripeInvoices(1, customer.Id, subscription.Id, 'paid');
            Test.stopTest();

            // Verify MRR was calculated
            customer = [SELECT Id, MRR__c FROM Stripe_Customer__c WHERE Id = :customer.Id];
            Assert.areEqual(subscription.Amount__c, customer.MRR__c, 'MRR should equal active subscription amount');
        }
    }
}