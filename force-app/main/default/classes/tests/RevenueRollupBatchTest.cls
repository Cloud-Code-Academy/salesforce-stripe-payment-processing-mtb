@isTest
private class RevenueRollupBatchTest {

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
            List<Contact> contacts = TestDataFactory.createContacts(2);

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
     * Test customer revenue rollup batch
     */
    @isTest
    static void testRevenueRollupBatch_CustomerRollup() {
        System.runAs(getTestUser()) {
            // Get test customers
            List<Stripe_Customer__c> customers = [SELECT Id FROM Stripe_Customer__c];

            // Create subscriptions and invoices for each customer
            for (Stripe_Customer__c customer : customers) {
                Stripe_Subscription__c subscription = TestDataFactory.createStripeSubscriptions(1, customer.Id)[0];

                // Create mix of paid and open invoices
                TestDataFactory.createStripeInvoices(3, customer.Id, subscription.Id, 'paid');
                TestDataFactory.createStripeInvoices(2, customer.Id, subscription.Id, 'open');
            }

            // Clear any existing rollup values
            for (Stripe_Customer__c customer : customers) {
                customer.Total_Revenue__c = null;
                customer.MRR__c = null;
            }
            update customers;

            // Run batch job for customer rollup
            Test.startTest();
            RevenueRollupBatch batch = new RevenueRollupBatch('customer');
            Database.executeBatch(batch);
            Test.stopTest();

            // Verify Total_Revenue__c was calculated correctly (only paid invoices)
            customers = [SELECT Id, Total_Revenue__c, MRR__c FROM Stripe_Customer__c ORDER BY Id];
            for (Stripe_Customer__c customer : customers) {
                Assert.areEqual(89.97, customer.Total_Revenue__c,
                    'Total revenue should be sum of 3 paid invoices (3 x 29.99)');
                Assert.areEqual(29.99, customer.MRR__c,
                    'MRR should equal active subscription amount');
            }
        }
    }

    /**
     * Test subscription invoice rollup batch
     */
    @isTest
    static void testRevenueRollupBatch_SubscriptionRollup() {
        System.runAs(getTestUser()) {
            // Get test customer
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];

            // Create multiple subscriptions
            List<Stripe_Subscription__c> subscriptions = TestDataFactory.createStripeSubscriptions(2, customer.Id);

            // Create invoices for each subscription
            for (Stripe_Subscription__c subscription : subscriptions) {
                TestDataFactory.createStripeInvoices(4, customer.Id, subscription.Id, 'paid');
            }

            // Clear any existing rollup values
            for (Stripe_Subscription__c subscription : subscriptions) {
                subscription.Total_Invoiced__c = null;
            }
            update subscriptions;

            // Run batch job for subscription rollup
            Test.startTest();
            RevenueRollupBatch batch = new RevenueRollupBatch('subscription');
            Database.executeBatch(batch);
            Test.stopTest();

            // Verify Total_Invoiced__c was calculated correctly
            subscriptions = [SELECT Id, Total_Invoiced__c FROM Stripe_Subscription__c ORDER BY Id];
            for (Stripe_Subscription__c subscription : subscriptions) {
                Assert.areEqual(119.96, subscription.Total_Invoiced__c,
                    'Total invoiced should be sum of all 4 invoices (4 x 29.99)');
            }
        }
    }

    /**
     * Test batch with no invoices
     */
    @isTest
    static void testRevenueRollupBatch_NoInvoices() {
        System.runAs(getTestUser()) {
            // Get test customers (no invoices created)
            List<Stripe_Customer__c> customers = [SELECT Id FROM Stripe_Customer__c];

            // Create subscriptions without invoices
            for (Stripe_Customer__c customer : customers) {
                TestDataFactory.createStripeSubscriptions(1, customer.Id);
            }

            // Run batch job
            Test.startTest();
            RevenueRollupBatch batch = new RevenueRollupBatch('customer');
            Database.executeBatch(batch);
            Test.stopTest();

            // Verify rollup values are 0 or null
            customers = [SELECT Id, Total_Revenue__c FROM Stripe_Customer__c];
            for (Stripe_Customer__c customer : customers) {
                Assert.isTrue(customer.Total_Revenue__c == null || customer.Total_Revenue__c == 0,
                    'Total revenue should be 0 or null when no paid invoices exist');
            }
        }
    }

    /**
     * Test schedulable interface
     */
    @isTest
    static void testRevenueRollupBatch_Schedulable() {
        System.runAs(getTestUser()) {
            // Get test customer
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = TestDataFactory.createStripeSubscriptions(1, customer.Id)[0];
            TestDataFactory.createStripeInvoices(1, customer.Id, subscription.Id, 'paid');

            // Schedule the batch job
            Test.startTest();
            String jobName = 'Test Revenue Rollup ' + DateTime.now().getTime();
            String cronExp = '0 0 4 1 * ?'; // Monthly on 1st at 4 AM
            RevenueRollupBatch batch = new RevenueRollupBatch();
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
     * Test MRR calculation for active subscriptions
     */
    @isTest
    static void testRevenueRollupBatch_MRRCalculation() {
        System.runAs(getTestUser()) {
            // Get test customer
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];

            // Create multiple active subscriptions with different amounts
            List<Stripe_Subscription__c> subscriptions = new List<Stripe_Subscription__c>();
            subscriptions.add(new Stripe_Subscription__c(
                Stripe_Customer__c = customer.Id,
                Stripe_Subscription_ID__c = 'sub_mrr_1',
                Status__c = 'active',
                Amount__c = 49.99,
                Currency__c = 'USD'
            ));
            subscriptions.add(new Stripe_Subscription__c(
                Stripe_Customer__c = customer.Id,
                Stripe_Subscription_ID__c = 'sub_mrr_2',
                Status__c = 'active',
                Amount__c = 99.99,
                Currency__c = 'USD'
            ));
            // Inactive subscription (should not count towards MRR)
            subscriptions.add(new Stripe_Subscription__c(
                Stripe_Customer__c = customer.Id,
                Stripe_Subscription_ID__c = 'sub_mrr_3',
                Status__c = 'canceled',
                Amount__c = 29.99,
                Currency__c = 'USD'
            ));
            insert subscriptions;

            // Create some paid invoices
            TestDataFactory.createStripeInvoices(2, customer.Id, subscriptions[0].Id, 'paid');

            // Run batch job
            Test.startTest();
            RevenueRollupBatch batch = new RevenueRollupBatch('customer');
            Database.executeBatch(batch);
            Test.stopTest();

            // Verify MRR calculation (only active subscriptions)
            customer = [SELECT Id, MRR__c FROM Stripe_Customer__c WHERE Id = :customer.Id];
            Assert.areEqual(149.98, customer.MRR__c,
                'MRR should be sum of active subscription amounts (49.99 + 99.99)');
        }
    }

    /**
     * Test batch with large data volume
     */
    @isTest
    static void testRevenueRollupBatch_LargeDataVolume() {
        System.runAs(getTestUser()) {
            // Get all customers
            List<Stripe_Customer__c> customers = [SELECT Id FROM Stripe_Customer__c];

            // Create multiple subscriptions and invoices for each customer
            for (Stripe_Customer__c customer : customers) {
                // Create 2 subscriptions per customer
                List<Stripe_Subscription__c> subscriptions = TestDataFactory.createStripeSubscriptions(2, customer.Id);

                // Create 10 invoices per subscription
                for (Stripe_Subscription__c subscription : subscriptions) {
                    for (Integer i = 0; i < 10; i++) {
                        Stripe_Invoice__c invoice = new Stripe_Invoice__c(
                            Stripe_Customer__c = customer.Id,
                            Stripe_Subscription__c = subscription.Id,
                            Stripe_Invoice_ID__c = 'inv_vol_' + subscription.Id + '_' + i,
                            Amount__c = 29.99 + i, // Varying amounts
                            Status__c = Math.mod(i, 2) == 0 ? 'paid' : 'open'
                        );
                        insert invoice;
                    }
                }
            }

            // Run batch job with smaller batch size
            Test.startTest();
            RevenueRollupBatch batch = new RevenueRollupBatch('customer');
            Database.executeBatch(batch, 50);
            Test.stopTest();

            // Verify all customers have revenue calculated
            customers = [SELECT Id, Total_Revenue__c FROM Stripe_Customer__c WHERE Total_Revenue__c > 0];
            Assert.areEqual(2, customers.size(), 'All customers with paid invoices should have revenue calculated');
        }
    }

    /**
     * Test error handling in batch
     */
    @isTest
    static void testRevenueRollupBatch_ErrorHandling() {
        System.runAs(getTestUser()) {
            // Get test customer
            Stripe_Customer__c customer = [SELECT Id FROM Stripe_Customer__c LIMIT 1];
            Stripe_Subscription__c subscription = TestDataFactory.createStripeSubscriptions(1, customer.Id)[0];

            // Create invoices with null amounts (edge case)
            Stripe_Invoice__c invoice = new Stripe_Invoice__c(
                Stripe_Customer__c = customer.Id,
                Stripe_Subscription__c = subscription.Id,
                Stripe_Invoice_ID__c = 'inv_null_amount',
                Amount__c = null,
                Status__c = 'paid'
            );
            insert invoice;

            // Run batch job (should handle null values gracefully)
            Test.startTest();
            RevenueRollupBatch batch = new RevenueRollupBatch('customer');
            Database.executeBatch(batch);
            Test.stopTest();

            // Verify batch completed without throwing exceptions
            customer = [SELECT Id, Total_Revenue__c FROM Stripe_Customer__c WHERE Id = :customer.Id];
            Assert.isNotNull(customer, 'Customer record should still exist');
            Assert.isTrue(customer.Total_Revenue__c == null || customer.Total_Revenue__c == 0,
                'Total revenue should handle null invoice amounts gracefully');
        }
    }
}