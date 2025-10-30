@isTest
public class ContactTriggerHelperTest {
    @IsTest
    static void processContactAfterInsert_insertContactWithLastNameAndFirstName_success(){
        Contact cont = new Contact(
            FirstName = 'Test',
            LastName = 'Testov',
            Email = 'testovtest@gmail.com.au',
            Phone = '423423423423423'
        );
        Test.startTest();
        insert cont;
        Test.stopTest();
        List<Stripe_Customer__c> insertedStripeCustomers = [SELECT Customer_Name__c, Customer_Email__c, Customer_Phone__c FROM Stripe_Customer__c WHERE Contact__c =: cont.Id];
        System.assertEquals(1, insertedStripeCustomers.size(), 'Stripe Customer is inserted');
        System.assertEquals(cont.LastName + ' ' + cont.FirstName, insertedStripeCustomers[0].Customer_Name__c, 'Name is same');
        System.assertEquals(cont.Email, insertedStripeCustomers[0].Customer_Email__c, 'Email is same');
        System.assertEquals(cont.Phone, insertedStripeCustomers[0].Customer_Phone__c, 'Phone is same');
    }
    @IsTest
    static void processContactAfterInsert_insertContactWithOnlyLastName_success(){
        Contact cont = new Contact(
            LastName = 'Testov',
            Email = 'testovtest@gmail.com.au',
            Phone = '423423423423423'
        );
        Test.startTest();
        insert cont;
        Test.stopTest();
        List<Stripe_Customer__c> insertedStripeCustomers = [SELECT Customer_Name__c, Customer_Email__c, Customer_Phone__c FROM Stripe_Customer__c WHERE Contact__c =: cont.Id];
        System.assertEquals(1, insertedStripeCustomers.size(), 'Stripe Customer is inserted');
        System.assertEquals(cont.LastName, insertedStripeCustomers[0].Customer_Name__c, 'Name is same');
        System.assertEquals(cont.Email, insertedStripeCustomers[0].Customer_Email__c, 'Email is same');
        System.assertEquals(cont.Phone, insertedStripeCustomers[0].Customer_Phone__c, 'Phone is same');
    }
}