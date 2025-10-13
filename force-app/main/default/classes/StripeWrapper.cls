public class StripeWrapper {
    // Used to get Id of created Stripe Customer
    public String id { get; set; }

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
}