public with sharing class ContactTriggerHelper {
        /**
     * @description Helper class for Contact trigger operations. Automatically creates Stripe Customer records
     *              when new Contacts are inserted, mapping relevant Contact data (email, name, phone) to the
     *              Stripe Customer object while enforcing object-level security and user-mode permissions.
     */
    public static void processContactAfterInsert(List<Contact> newList){
        List<Stripe_Customer__c> stripeCustomersForInsert = new List<Stripe_Customer__c>();
        try {
            for (Contact cont : newList) {
                Stripe_Customer__c customer = new Stripe_Customer__c();
                customer.Contact__c = cont.Id;
                if (cont.Email != null) {
                    customer.Customer_Email__c = cont.Email;
                }
                if (String.isNotBlank(cont.FirstName)) {
                    customer.Customer_Name__c = cont.LastName + ' ' + cont.FirstName;    
                } else {
                    customer.Customer_Name__c = cont.LastName;
                }
                if (cont.Phone != null) {
                    customer.Customer_Phone__c = cont.Phone;
                }
                stripeCustomersForInsert.add(customer);
            }
            //Check whether Stripe_Customer__c object is available for Create for User
            if (Schema.SObjectType.Stripe_Customer__c.isCreateable()) {
                insert as user  stripeCustomersForInsert;
            } else {
                throw new SecurityException('User does not have create access to Stripe_Customer__c object');
            }
        } catch (Exception ex) {
            Logger.error('Failed to insert Contact: ', ex);
            Logger.saveLog();
        }
    }
}