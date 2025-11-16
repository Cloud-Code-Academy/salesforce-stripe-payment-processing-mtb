@isTest
private class StripeInvoiceTriggerHelperTest {
    
    /**
     * @description Test data setup - creates Contacts and Stripe Invoices for testing
     */
    @TestSetup
    static void setupTestData() {
        // Create test Contacts (Stripe Customers)
        List<Contact> testContacts = new List<Contact>{
            new Contact(FirstName = 'John', LastName = 'Doe', Email = 'john.doe@test.com'),
            new Contact(FirstName = 'Jane', LastName = 'Smith', Email = 'jane.smith@test.com'),
            new Contact(FirstName = 'Bob', LastName = 'Johnson', Email = 'bob.johnson@test.com')
        };
        insert testContacts;
    }
    
    /**
     * @description Test INSERT operation - new paid invoices should update customer revenue
     */
    @isTest
    static void testInsertPaidInvoices() {
        // Get test contact
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Doe' LIMIT 1];
        
        Test.startTest();
        
        // Insert paid invoices
        List<Stripe_Invoice__c> invoices = new List<Stripe_Invoice__c>{
            new Stripe_Invoice__c(
                Contact__c = testContact.Id,
                Amount__c = 100.00,
                Status__c = 'paid',
                Stripe_Invoice_ID__c = 'in_test_001'
            ),
            new Stripe_Invoice__c(
                Contact__c = testContact.Id,
                Amount__c = 150.00,
                Status__c = 'paid',
                Stripe_Invoice_ID__c = 'in_test_002'
            )
        };
        insert invoices;
        
        Test.stopTest();
        
        // Verify Total Revenue was calculated
        Contact updatedContact = [SELECT Total_Revenue__c FROM Contact WHERE Id = :testContact.Id];
        System.assertEquals(250.00, updatedContact.Total_Revenue__c, 
            'Total Revenue should be sum of paid invoices (100 + 150)');
    }
    
    /**
     * @description Test INSERT operation - unpaid invoices should not affect revenue
     */
    @isTest
    static void testInsertUnpaidInvoices() {
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Smith' LIMIT 1];
        
        Test.startTest();
        
        // Insert unpaid invoices
        List<Stripe_Invoice__c> invoices = new List<Stripe_Invoice__c>{
            new Stripe_Invoice__c(
                Contact__c = testContact.Id,
                Amount__c = 200.00,
                Status__c = 'open',
                Stripe_Invoice_ID__c = 'in_test_003'
            ),
            new Stripe_Invoice__c(
                Contact__c = testContact.Id,
                Amount__c = 300.00,
                Status__c = 'draft',
                Stripe_Invoice_ID__c = 'in_test_004'
            )
        };
        insert invoices;
        
        Test.stopTest();
        
        // Verify Total Revenue is still null or zero
        Contact updatedContact = [SELECT Total_Revenue__c FROM Contact WHERE Id = :testContact.Id];
        System.assert(updatedContact.Total_Revenue__c == null || updatedContact.Total_Revenue__c == 0, 
            'Total Revenue should be zero for unpaid invoices');
    }
    
    /**
     * @description Test UPDATE operation - status change to paid should update revenue
     */
    @isTest
    static void testUpdateStatusToPaid() {
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Doe' LIMIT 1];
        
        // Insert draft invoice
        Stripe_Invoice__c invoice = new Stripe_Invoice__c(
            Contact__c = testContact.Id,
            Amount__c = 500.00,
            Status__c = 'draft',
            Stripe_Invoice_ID__c = 'in_test_005'
        );
        insert invoice;
        
        Test.startTest();
        
        // Update status to paid
        invoice.Status__c = 'paid';
        update invoice;
        
        Test.stopTest();
        
        // Verify Total Revenue was updated
        Contact updatedContact = [SELECT Total_Revenue__c FROM Contact WHERE Id = :testContact.Id];
        System.assertEquals(500.00, updatedContact.Total_Revenue__c, 
            'Total Revenue should reflect newly paid invoice');
    }
    
    /**
     * @description Test UPDATE operation - amount change on paid invoice should recalculate
     */
    @isTest
    static void testUpdateAmountOnPaidInvoice() {
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Smith' LIMIT 1];
        
        // Insert paid invoice
        Stripe_Invoice__c invoice = new Stripe_Invoice__c(
            Contact__c = testContact.Id,
            Amount__c = 1000.00,
            Status__c = 'paid',
            Stripe_Invoice_ID__c = 'in_test_006'
        );
        insert invoice;
        
        Test.startTest();
        
        // Update amount
        invoice.Amount__c = 1500.00;
        update invoice;
        
        Test.stopTest();
        
        // Verify Total Revenue was recalculated
        Contact updatedContact = [SELECT Total_Revenue__c FROM Contact WHERE Id = :testContact.Id];
        System.assertEquals(1500.00, updatedContact.Total_Revenue__c, 
            'Total Revenue should reflect updated amount');
    }
    
    /**
     * @description Test UPDATE operation - updating unpaid invoice should not affect revenue
     */
    @isTest
    static void testUpdateUnpaidInvoice() {
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Johnson' LIMIT 1];
        
        // Insert draft invoice
        Stripe_Invoice__c invoice = new Stripe_Invoice__c(
            Contact__c = testContact.Id,
            Amount__c = 750.00,
            Status__c = 'draft',
            Stripe_Invoice_ID__c = 'in_test_007'
        );
        insert invoice;
        
        Test.startTest();
        
        // Update amount but keep status as draft
        invoice.Amount__c = 800.00;
        update invoice;
        
        Test.stopTest();
        
        // Verify Total Revenue is still zero
        Contact updatedContact = [SELECT Total_Revenue__c FROM Contact WHERE Id = :testContact.Id];
        System.assert(updatedContact.Total_Revenue__c == null || updatedContact.Total_Revenue__c == 0, 
            'Total Revenue should remain zero for unpaid invoices');
    }
    
    /**
     * @description Test DELETE operation - deleting paid invoice should recalculate revenue
     */
    @isTest
    static void testDeletePaidInvoice() {
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Doe' LIMIT 1];
        
        // Insert two paid invoices
        List<Stripe_Invoice__c> invoices = new List<Stripe_Invoice__c>{
            new Stripe_Invoice__c(
                Contact__c = testContact.Id,
                Amount__c = 400.00,
                Status__c = 'paid',
                Stripe_Invoice_ID__c = 'in_test_008'
            ),
            new Stripe_Invoice__c(
                Contact__c = testContact.Id,
                Amount__c = 600.00,
                Status__c = 'paid',
                Stripe_Invoice_ID__c = 'in_test_009'
            )
        };
        insert invoices;
        
        Test.startTest();
        
        // Delete one invoice
        delete invoices[0];
        
        Test.stopTest();
        
        // Verify Total Revenue reflects remaining invoice only
        Contact updatedContact = [SELECT Total_Revenue__c FROM Contact WHERE Id = :testContact.Id];
        System.assertEquals(600.00, updatedContact.Total_Revenue__c, 
            'Total Revenue should be 600 after deleting 400 invoice');
    }
    
    /**
     * @description Test DELETE operation - deleting all paid invoices should set revenue to zero
     */
    @isTest
    static void testDeleteAllPaidInvoices() {
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Smith' LIMIT 1];
        
        // Insert paid invoices
        List<Stripe_Invoice__c> invoices = new List<Stripe_Invoice__c>{
            new Stripe_Invoice__c(
                Contact__c = testContact.Id,
                Amount__c = 300.00,
                Status__c = 'paid',
                Stripe_Invoice_ID__c = 'in_test_010'
            ),
            new Stripe_Invoice__c(
                Contact__c = testContact.Id,
                Amount__c = 200.00,
                Status__c = 'paid',
                Stripe_Invoice_ID__c = 'in_test_011'
            )
        };
        insert invoices;
        
        Test.startTest();
        
        // Delete all invoices
        delete invoices;
        
        Test.stopTest();
        
        // Verify Total Revenue is set to zero
        Contact updatedContact = [SELECT Total_Revenue__c FROM Contact WHERE Id = :testContact.Id];
        System.assertEquals(0, updatedContact.Total_Revenue__c, 
            'Total Revenue should be zero after deleting all invoices');
    }
    
    /**
     * @description Test bulk operation - multiple customers with multiple invoices
     */
    @isTest
    static void testBulkOperations() {
        List<Contact> contacts = [SELECT Id FROM Contact ORDER BY LastName];
        
        Test.startTest();
        
        // Insert multiple invoices for multiple customers
        List<Stripe_Invoice__c> invoices = new List<Stripe_Invoice__c>();
        Integer counter = 100;
        for (Contact c : contacts) {
            invoices.add(new Stripe_Invoice__c(
                Contact__c = c.Id,
                Amount__c = 100.00,
                Status__c = 'paid',
                Stripe_Invoice_ID__c = 'in_bulk_' + counter++
            ));
            invoices.add(new Stripe_Invoice__c(
                Contact__c = c.Id,
                Amount__c = 200.00,
                Status__c = 'paid',
                Stripe_Invoice_ID__c = 'in_bulk_' + counter++
            ));
        }
        insert invoices;
        
        Test.stopTest();
        
        // Verify all customers have correct revenue
        List<Contact> updatedContacts = [SELECT Total_Revenue__c FROM Contact WHERE Id IN :contacts];
        for (Contact c : updatedContacts) {
            System.assertEquals(300.00, c.Total_Revenue__c, 
                'Each customer should have revenue of 300 (100 + 200)');
        }
    }
    
    /**
     * @description Test edge case - invoice without Contact should not cause errors
     */
    @isTest
    static void testInvoiceWithoutContact() {
        Test.startTest();
        
        // Insert invoice without Contact
        Stripe_Invoice__c invoice = new Stripe_Invoice__c(
            Contact__c = null,
            Amount__c = 999.00,
            Status__c = 'paid',
            Stripe_Invoice_ID__c = 'in_test_999'
        );
        insert invoice;
        
        Test.stopTest();
        
        // Should not throw exception - method should handle gracefully
        System.assert(true, 'Invoice without contact should be handled gracefully');
    }
    
    /**
     * @description Test edge case - null or empty list handling
     */
    @isTest
    static void testNullOrEmptyList() {
        Test.startTest();
        
        // Call with null list
        StripeInvoiceTriggerHelper.calculateTotalRevenueOfStripeCustomer(null, null);
        
        // Call with empty list
        StripeInvoiceTriggerHelper.calculateTotalRevenueOfStripeCustomer(
            new List<Stripe_Invoice__c>(), 
            null
        );
        
        Test.stopTest();
        
        // Should not throw exception
        System.assert(true, 'Null and empty list should be handled gracefully');
    }
    
    /**
     * @description Test mixed status scenario - only paid invoices should count
     */
    @isTest
    static void testMixedStatusInvoices() {
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Johnson' LIMIT 1];
        
        Test.startTest();
        
        // Insert invoices with different statuses
        List<Stripe_Invoice__c> invoices = new List<Stripe_Invoice__c>{
            new Stripe_Invoice__c(
                Contact__c = testContact.Id,
                Amount__c = 100.00,
                Status__c = 'paid',
                Stripe_Invoice_ID__c = 'in_mixed_001'
            ),
            new Stripe_Invoice__c(
                Contact__c = testContact.Id,
                Amount__c = 200.00,
                Status__c = 'open',
                Stripe_Invoice_ID__c = 'in_mixed_002'
            ),
            new Stripe_Invoice__c(
                Contact__c = testContact.Id,
                Amount__c = 150.00,
                Status__c = 'paid',
                Stripe_Invoice_ID__c = 'in_mixed_003'
            ),
            new Stripe_Invoice__c(
                Contact__c = testContact.Id,
                Amount__c = 300.00,
                Status__c = 'void',
                Stripe_Invoice_ID__c = 'in_mixed_004'
            )
        };
        insert invoices;
        
        Test.stopTest();
        
        // Verify only paid invoices are counted
        Contact updatedContact = [SELECT Total_Revenue__c FROM Contact WHERE Id = :testContact.Id];
        System.assertEquals(250.00, updatedContact.Total_Revenue__c, 
            'Total Revenue should only include paid invoices (100 + 150)');
    }
    
    /**
     * @description Test governor limits - ensure bulkification works with 200+ records
     */
    @isTest
    static void testGovernorLimits() {
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Doe' LIMIT 1];
        
        List<Stripe_Invoice__c> invoices = new List<Stripe_Invoice__c>();
        
        // Create 200 invoices
        for (Integer i = 0; i < 200; i++) {
            invoices.add(new Stripe_Invoice__c(
                Contact__c = testContact.Id,
                Amount__c = 1.00,
                Status__c = 'paid',
                Stripe_Invoice_ID__c = 'in_load_test_' + i
            ));
        }
        
        Test.startTest();
        insert invoices;
        Test.stopTest();
        
        // Verify total revenue
        Contact updatedContact = [SELECT Total_Revenue__c FROM Contact WHERE Id = :testContact.Id];
        System.assertEquals(200.00, updatedContact.Total_Revenue__c, 
            'Should handle 200 invoices without hitting governor limits');
        
        // Verify query limits not exceeded
        System.assert(Limits.getQueries() < Limits.getLimitQueries(), 
            'Should not exceed SOQL query limits');
    }
}