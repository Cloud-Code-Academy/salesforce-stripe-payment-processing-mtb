public class StripeWrapper {
    public String id { get; set; }

    // Wrapper for Customer Object
    public class CustomerWrapper{
        public String name;
        public String email;
        public String phone;

        public CustomerWrapper(String name, String email, String phone){
            this.name = name;
            this.email = email;
            this.phone = phone;
        }
    }
}