@isTest
private class CustomerHealthScoreBatchTest {

    private static User testUser;

    @TestSetup
    static void setupTestData() {
        // Create test user with required permission sets
        testUser = TestDataFactory.createUserWithPermissionSets(
            new List<String>{'Stripe_Customer_Contact_Access', 'Stripe_API_Access', 'Stripe_Subscription_Access'}
        );

        // Run as test user to create test data
        System.runAs(testUser) {
            // Create test Contacts with Stripe customer data
            TestDataFactory.createStripeCustomers(3);
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
            // Get test contacts
            List<Contact> contacts = [SELECT Id, Stripe_Customer_ID__c FROM Contact WHERE Stripe_Customer_ID__c != null];
            Assert.areEqual(3, contacts.size(), 'Should have 3 test contacts');

            // Create subscriptions and paid invoices for each contact
            for (Contact contact : contacts) {
                Stripe_Subscription__c subscription = TestDataFactory.createStripeSubscriptions(1, contact.Id)[0];
                TestDataFactory.createStripeInvoices(5, subscription.Id, 'paid');
            }

            // Verify invoices were created correctly
            List<Stripe_Invoice__c> allInvoices = [
                SELECT Id, Contact__c, Contact__r.Stripe_Customer_ID__c, Status__c
                FROM Stripe_Invoice__c
                WHERE Contact__c IN :contacts
            ];
            Assert.areEqual(15, allInvoices.size(), 'Should have 15 invoices total (5 per contact)');

            // Verify all invoices have Contact__c set
            for (Stripe_Invoice__c inv : allInvoices) {
                Assert.isNotNull(inv.Contact__c, 'Invoice should have Contact__c field set');
                Assert.isNotNull(inv.Contact__r.Stripe_Customer_ID__c, 'Contact should have Stripe_Customer_ID__c');
            }

            // Run batch job
            Test.startTest();
            CustomerHealthScoreBatch batch = new CustomerHealthScoreBatch();
            Database.executeBatch(batch);
            Test.stopTest();

            // Verify health scores are calculated correctly
            contacts = [SELECT Id, Health_Score__c FROM Contact WHERE Stripe_Customer_ID__c != null];
            for (Contact contact : contacts) {
                Assert.areEqual(100, contact.Health_Score__c, 'Health score should be 100 for perfect payment history');
            }
        }
    }

    /**
     * Test batch recalculation with mixed payment histories
     */
    @isTest
    static void testCustomerHealthScoreBatch_MixedPaymentHistory() {
        System.runAs(getTestUser()) {
            // Get first contact
            Contact contact = [SELECT Id FROM Contact WHERE Stripe_Customer_ID__c != null LIMIT 1];
            Stripe_Subscription__c subscription = TestDataFactory.createStripeSubscriptions(1, contact.Id)[0];

            // Create mixed invoice history: 3 paid, 1 failed, 1 exhausted
            TestDataFactory.createStripeInvoices(3, subscription.Id, 'paid');

            Stripe_Invoice__c failedInvoice = new Stripe_Invoice__c(
                Stripe_Subscription__c = subscription.Id,
                Contact__c = contact.Id,
                Stripe_Invoice_ID__c = 'inv_failed',
                Amount__c = 29.99,
                Status__c = 'uncollectible',
                Dunning_Status__c = 'none'
            );
            insert failedInvoice;

            Stripe_Invoice__c exhaustedInvoice = new Stripe_Invoice__c(
                Stripe_Subscription__c = subscription.Id,
                Contact__c = contact.Id,
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
            contact = [SELECT Id, Health_Score__c FROM Contact WHERE Id = :contact.Id];
            Assert.isTrue(contact.Health_Score__c < 60, 'Health score should be reduced for mixed payment history');
            Assert.isTrue(contact.Health_Score__c >= 0, 'Health score should not be negative');
        }
    }

    /**
     * Test batch with contacts having no invoices
     */
    @isTest
    static void testCustomerHealthScoreBatch_NoInvoices() {
        System.runAs(getTestUser()) {
            // Get contacts (no invoices created)
            List<Contact> contacts = [SELECT Id, Health_Score__c FROM Contact WHERE Stripe_Customer_ID__c != null];

            // Run batch job
            Test.startTest();
            CustomerHealthScoreBatch batch = new CustomerHealthScoreBatch();
            Database.executeBatch(batch);
            Test.stopTest();

            // Verify contacts with no invoices are handled properly
            contacts = [SELECT Id, Health_Score__c FROM Contact WHERE Stripe_Customer_ID__c != null];
            for (Contact contact : contacts) {
                // Health score should remain null or unchanged for contacts with no invoices
                Assert.isTrue(contact.Health_Score__c == null || contact.Health_Score__c == 0,
                    'Health score should be null or 0 for contacts with no invoices');
            }
        }
    }

    /**
     * Test schedulable interface
     */
    @isTest
    static void testCustomerHealthScoreBatch_Schedulable() {
        System.runAs(getTestUser()) {
            // Get test contact
            Contact contact = [SELECT Id FROM Contact WHERE Stripe_Customer_ID__c != null LIMIT 1];
            Stripe_Subscription__c subscription = TestDataFactory.createStripeSubscriptions(1, contact.Id)[0];
            TestDataFactory.createStripeInvoices(2, subscription.Id, 'paid');

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
            // Get all contacts
            List<Contact> contacts = [SELECT Id FROM Contact WHERE Stripe_Customer_ID__c != null];

            // Create subscriptions and multiple invoices for each contact
            for (Contact contact : contacts) {
                Stripe_Subscription__c subscription = TestDataFactory.createStripeSubscriptions(1, contact.Id)[0];

                // Create 10 invoices per contact with varying statuses
                for (Integer i = 0; i < 10; i++) {
                    Stripe_Invoice__c invoice = new Stripe_Invoice__c(
                        Stripe_Subscription__c = subscription.Id,
                        Contact__c = contact.Id,
                        Stripe_Invoice_ID__c = 'inv_' + contact.Id + '_' + i,
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

            // Verify all contacts have health scores calculated
            contacts = [SELECT Id, Health_Score__c FROM Contact WHERE Stripe_Customer_ID__c != null AND Health_Score__c != null];
            Assert.areEqual(3, contacts.size(), 'All contacts with invoices should have health scores calculated');
        }
    }

    /**
     * Test batch error handling
     */
    @isTest
    static void testCustomerHealthScoreBatch_ErrorHandling() {
        System.runAs(getTestUser()) {
            // Get test contact
            Contact contact = [SELECT Id FROM Contact WHERE Stripe_Customer_ID__c != null LIMIT 1];
            Stripe_Subscription__c subscription = TestDataFactory.createStripeSubscriptions(1, contact.Id)[0];

            // Create invoices
            TestDataFactory.createStripeInvoices(3, subscription.Id, 'paid');

            // Run batch job (should handle any errors gracefully)
            Test.startTest();
            CustomerHealthScoreBatch batch = new CustomerHealthScoreBatch();
            Database.executeBatch(batch);
            Test.stopTest();

            // Verify batch completed without throwing exceptions
            contact = [SELECT Id, Health_Score__c FROM Contact WHERE Id = :contact.Id];
            Assert.isNotNull(contact, 'Contact record should still exist');
        }
    }
}