public class StripeWrapper {
    // Used to get Id of created Stripe Customer
    public String id { get; set; }
    public String url { get; set; }

    // Wrapper for Customer Object
    public class CustomerWrapper{
        public String name;
        public String email;
        public String phone;
        // Assigning incoming parameters to Wrapper Class variables
        public CustomerWrapper(String name, String email, String phone){
            this.name = name;
            this.email = email;
            this.phone = phone;
        }
    }
    public class PricingPlanWrapper{
        public String currency_x;
        public RecurringDetails recurring;
        public String product;
        public Decimal unit_amount;

        public PricingPlanWrapper(String currencyName, String interval, Decimal amount, String product){
            this.currency_x = currencyName;
            this.recurring = new RecurringDetails();
            this.recurring.interval = interval;
            this.unit_amount = amount;
            this.product = product;
        }
    }
    public class RecurringDetails{
        public String interval;
    }
    public class ProductWrapper{
        public String name;
        public ProductWrapper(String productName){
            this.name = productName;
        }
    }
}