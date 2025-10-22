/**
 * @description Wrapper classes for Stripe API request and response data. Provides structured objects for serializing
 *              and deserializing JSON data when communicating with Stripe endpoints. Includes wrappers for customers,
 *              products, pricing plans, and API responses.
 */
public class StripeWrapper {
    // Used to get Id of created Stripe Customer
    public String id { get; set; }
    public String url { get; set; }

    // Wrapper for Customer Object
    public class CustomerWrapper{
        public String name;
        public String email;
        public String phone;
        /**
         * @description Constructor to initialize customer wrapper with contact information.
         * @param name Full name of the customer
         * @param email Email address of the customer
         * @param phone Phone number of the customer
         */
        public CustomerWrapper(String name, String email, String phone){
            this.name = name;
            this.email = email;
            this.phone = phone;
        }
    }
    /**
     * @description Wrapper class for Stripe Product data used in API requests.
     */
    public class ProductWrapper{
        public String name;
        /**
         * @description Constructor to initialize product wrapper with product name.
         * @param productName Name/description of the Stripe product
         */
        public ProductWrapper(String productName){
            this.name = productName;
        }
    }
}