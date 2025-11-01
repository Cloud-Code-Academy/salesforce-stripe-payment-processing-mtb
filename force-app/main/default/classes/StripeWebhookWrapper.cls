public class StripeWebhookWrapper {
    public DataClass data;
    public String type;
    public class DataClass{
        public ObjectWrapper object_x;
    }
    public class ObjectWrapper{
        public String object_x;
        public String id;
        public String email;
        public String phone;
        public String name;
        public String subscription;
        public String invoice;
        public Integer amount;
        public String currency_x;
        public Integer created;
        public String customer;
        public List<String> payment_method_types;
        public String status;
        public PaymentDetailsClass payment_details;
        public ItemsList items;
    }
    public class PaymentDetailsClass{
        public String order_reference;
    }
    public class ItemsList{
        public List<ItemData> data;
    }
    public class ItemData{
        public Integer current_period_end;
        public Integer current_period_start;
        public PlanWrapper plan;
    }
    public class PlanWrapper{
        public Integer amount;
    }
}