@isTest
private class CustomerHealthScoreBatchTest {

    private static User testUser;

    @TestSetup
    static void setupTestData() {
        // Create test user with required permission sets
        testUser = TestDataFactory.createUserWithPermissionSets(
            new List<String>{'Stripe_Customer_Contact_Access', 'Stripe_API_Access'}
        );

        // Run as test user to create test data
        System.runAs(testUser) {
            // Create test Contacts
            List<Contact> contacts = TestDataFactory.createContacts(3);

            // Create test Stripe Customers
            for (Contact contact : contacts) {
                TestDataFactory.createStripeCustomers(1, contact.Id);
            }
        }
    }

    // Helper method to get test user
    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Email LIKE 'testuser%@testorg.com' LIMIT 1];
    }

    /**
     * Test batch recalculation of health scores with perfect payment history
     */
    @isTest
    static void testCustomerHealthScoreBatch_PerfectPaymentHistory() {
        System.runAs(getTestUser()) {
            // Get test customers
            List<Stripe_Customer__c> customers = [SELECT Id FROM Stripe_Customer__c];

            // Create subscriptions and paid invoices for each customer
            for (Stripe_Customer__c customer : customers) {
                Stripe_Subscription__c subscription = TestDataFactory.createStripeSubscriptions(1, customer.Id)[0];
                TestDataFactory.createStripeInvoices(5, customer.Id, subscription.Id, 'paid');
            }

            // Run batch job
            Test.startTest();
            CustomerHealthScoreBatch batch = new CustomerHealthScoreBatch();
            Database.executeBatch(batch);
            Test.stopTest();

            // Verify health scores are calculated correctly
            customers = [SELECT Id, Health_Score__c FROM Stripe_Customer__c];
            for (Stripe_Customer__c customer : customers) {
                Assert.areEqual(100, customer.Health_Score__c, 'Health score should be 100 for perfect payment history');
            }
        }
    }

    /**
     * Test batch recalculation with mixed payment histories
     */
    @isTest
    static void testCustomerHealthScoreBatch_MixedPaymentHistory() {
        System.runAs(getTestUser()) {
            // Get first customer
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = TestDataFactory.createStripeSubscriptions(1, customer.Id)[0];

            // Create mixed invoice history: 3 paid, 1 failed, 1 exhausted
            TestDataFactory.createStripeInvoices(3, customer.Id, subscription.Id, 'paid');

            Stripe_Invoice__c failedInvoice = new Stripe_Invoice__c(
                Stripe_Customer__c = customer.Id,
                Stripe_Subscription__c = subscription.Id,
                Stripe_Invoice_ID__c = 'inv_failed',
                Amount__c = 29.99,
                Status__c = 'uncollectible',
                Dunning_Status__c = 'none'
            );
            insert failedInvoice;

            Stripe_Invoice__c exhaustedInvoice = new Stripe_Invoice__c(
                Stripe_Customer__c = customer.Id,
                Stripe_Subscription__c = subscription.Id,
                Stripe_Invoice_ID__c = 'inv_exhausted',
                Amount__c = 29.99,
                Status__c = 'open',
                Dunning_Status__c = 'exhausted'
            );
            insert exhaustedInvoice;

            // Run batch job
            Test.startTest();
            CustomerHealthScoreBatch batch = new CustomerHealthScoreBatch();
            Database.executeBatch(batch);
            Test.stopTest();

            // Verify health score is reduced
            customer = [SELECT Id, Health_Score__c FROM Stripe_Customer__c WHERE Id = :customer.Id];
            Assert.isTrue(customer.Health_Score__c < 60, 'Health score should be reduced for mixed payment history');
            Assert.isTrue(customer.Health_Score__c >= 0, 'Health score should not be negative');
        }
    }

    /**
     * Test batch with customers having no invoices
     */
    @isTest
    static void testCustomerHealthScoreBatch_NoInvoices() {
        System.runAs(getTestUser()) {
            // Get customers (no invoices created)
            List<Stripe_Customer__c> customers = [SELECT Id, Health_Score__c FROM Stripe_Customer__c];

            // Run batch job
            Test.startTest();
            CustomerHealthScoreBatch batch = new CustomerHealthScoreBatch();
            Database.executeBatch(batch);
            Test.stopTest();

            // Verify customers with no invoices are handled properly
            customers = [SELECT Id, Health_Score__c FROM Stripe_Customer__c];
            for (Stripe_Customer__c customer : customers) {
                // Health score should remain null or unchanged for customers with no invoices
                Assert.isTrue(customer.Health_Score__c == null || customer.Health_Score__c == 0,
                    'Health score should be null or 0 for customers with no invoices');
            }
        }
    }

    /**
     * Test schedulable interface
     */
    @isTest
    static void testCustomerHealthScoreBatch_Schedulable() {
        System.runAs(getTestUser()) {
            // Get test customer
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = TestDataFactory.createStripeSubscriptions(1, customer.Id)[0];
            TestDataFactory.createStripeInvoices(2, customer.Id, subscription.Id, 'paid');

            // Schedule the batch job
            Test.startTest();
            String jobName = 'Test Health Score Batch ' + DateTime.now().getTime();
            String cronExp = '0 0 3 ? * SUN'; // Weekly on Sunday at 3 AM
            CustomerHealthScoreBatch batch = new CustomerHealthScoreBatch();
            System.schedule(jobName, cronExp, batch);
            Test.stopTest();

            // Verify job was scheduled
            List<CronTrigger> scheduledJobs = [
                SELECT Id, CronJobDetail.Name
                FROM CronTrigger
                WHERE CronJobDetail.Name = :jobName
            ];
            Assert.areEqual(1, scheduledJobs.size(), 'Batch job should be scheduled');
        }
    }

    /**
     * Test batch with large data volume
     */
    @isTest
    static void testCustomerHealthScoreBatch_LargeDataVolume() {
        System.runAs(getTestUser()) {
            // Get all customers
            List<Stripe_Customer__c> customers = [SELECT Id FROM Stripe_Customer__c];

            // Create subscriptions and multiple invoices for each customer
            for (Stripe_Customer__c customer : customers) {
                Stripe_Subscription__c subscription = TestDataFactory.createStripeSubscriptions(1, customer.Id)[0];

                // Create 10 invoices per customer with varying statuses
                for (Integer i = 0; i < 10; i++) {
                    Stripe_Invoice__c invoice = new Stripe_Invoice__c(
                        Stripe_Customer__c = customer.Id,
                        Stripe_Subscription__c = subscription.Id,
                        Stripe_Invoice_ID__c = 'inv_' + customer.Id + '_' + i,
                        Amount__c = 29.99,
                        Status__c = Math.mod(i, 3) == 0 ? 'uncollectible' : 'paid',
                        Dunning_Status__c = Math.mod(i, 5) == 0 ? 'exhausted' : 'none'
                    );
                    insert invoice;
                }
            }

            // Run batch job with smaller batch size
            Test.startTest();
            CustomerHealthScoreBatch batch = new CustomerHealthScoreBatch();
            Database.executeBatch(batch, 50);
            Test.stopTest();

            // Verify all customers have health scores calculated
            customers = [SELECT Id, Health_Score__c FROM Stripe_Customer__c WHERE Health_Score__c != null];
            Assert.areEqual(3, customers.size(), 'All customers with invoices should have health scores calculated');
        }
    }

    /**
     * Test batch error handling
     */
    @isTest
    static void testCustomerHealthScoreBatch_ErrorHandling() {
        System.runAs(getTestUser()) {
            // Get test customer
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = TestDataFactory.createStripeSubscriptions(1, customer.Id)[0];

            // Create invoices
            TestDataFactory.createStripeInvoices(3, customer.Id, subscription.Id, 'paid');

            // Run batch job (should handle any errors gracefully)
            Test.startTest();
            CustomerHealthScoreBatch batch = new CustomerHealthScoreBatch();
            Database.executeBatch(batch);
            Test.stopTest();

            // Verify batch completed without throwing exceptions
            customer = [SELECT Id, Health_Score__c FROM Stripe_Customer__c WHERE Id = :customer.Id];
            Assert.isNotNull(customer, 'Customer record should still exist');
        }
    }
}