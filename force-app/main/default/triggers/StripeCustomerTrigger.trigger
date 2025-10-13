trigger StripeCustomerTrigger on Stripe_Customer__c (before insert, after insert) {
    switch on Trigger.operationType {
        when BEFORE_INSERT{
            StripeCustomerTriggerHandler.beforeInsert(Trigger.new);
        }
        when AFTER_INSERT {
            StripeCustomerTriggerHandler.afterInsert(Trigger.new);
        }
    }
}