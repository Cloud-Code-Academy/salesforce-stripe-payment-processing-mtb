"""
Salesforce Record Models

Pydantic models for Salesforce API operations.
"""

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field


class SalesforceCustomer(BaseModel):
    """Deprecated: Use SalesforceContact instead. Maintained for backward compatibility."""

    Stripe_Customer_ID__c: str = Field(description="External ID - Stripe customer ID")
    Default_Payment_Method__c: Optional[str] = None
    Subscription_Status__c: Optional[
        Literal["None", "Active", "Past Due", "Canceled"]
    ] = "None"
    Contact__c: Optional[str] = Field(None, description="Lookup to Contact")

    class Config:
        json_schema_extra = {
            "example": {
                "Stripe_Customer_ID__c": "cus_ABC123",
                "Subscription_Status__c": "Active",
            }
        }


class SalesforceSubscription(BaseModel):
    """Salesforce Stripe_Subscription__c record"""

    Stripe_Subscription_ID__c: str = Field(
        description="External ID - Stripe subscription ID"
    )
    Contact__c: Optional[str] = Field(
        None, description="Lookup to Contact (Contact.Id)"
    )
    Pricing_Plan__c: Optional[str] = Field(
        None, description="Lookup to Pricing_Plan__c"
    )
    Status__c: Optional[
        Literal[
            "active",
            "canceled",
            "incomplete",
            "incomplete_expired",
            "past_due",
            "trialing",
            "unpaid",
        ]
    ] = None
    Current_Period_Start__c: Optional[datetime] = None
    Current_Period_End__c: Optional[datetime] = None
    Amount__c: Optional[float] = None
    Currency__c: Optional[str] = None
    Quantity__c: Optional[int] = Field(None, description="Quantity of the subscription")
    Product_Plan_Name__c: Optional[str] = None
    Stripe_Checkout_Session_ID__c: Optional[str] = None
    Checkout_URL__c: Optional[str] = None
    Sync_Status__c: Optional[Literal["Pending", "Checkout Created", "Completed", "Failed"]] = (
        None
    )
    Error_Message__c: Optional[str] = None

    class Config:
        json_schema_extra = {
            "example": {
                "Stripe_Subscription_ID__c": "sub_ABC123",
                "Contact__c": "0031700000IZ3STABC",
                "Status__c": "active",
                "Amount__c": 29.99,
                "Currency__c": "USD",
            }
        }


class SalesforceInvoice(BaseModel):
    """Salesforce Stripe_Invoice__c record"""

    Stripe_Invoice_ID__c: str = Field(
        description="External ID - Stripe invoice ID"
    )
    Stripe_Subscription__c: Optional[str] = Field(
        None, description="Lookup to Stripe_Subscription__c"
    )
    Contact__c: Optional[str] = Field(
        None, description="Lookup to Contact (Contact.Id)"
    )
    Line_Items__c: Optional[str] = None
    Invoice_PDF_URL__c: Optional[str] = None
    Period_Start__c: Optional[datetime] = None
    Period_End__c: Optional[datetime] = None
    Due_Date__c: Optional[datetime] = None
    Tax_Amount__c: Optional[float] = None
    Discounts_Applied__c: Optional[float] = None
    Status__c: Optional[
        Literal["draft", "open", "paid", "uncollectible", "void"]
    ] = None
    Dunning_Status__c: Optional[
        Literal["none", "trying", "exhausted"]
    ] = "none"

    class Config:
        json_schema_extra = {
            "example": {
                "Stripe_Invoice_ID__c": "in_ABC123",
                "Stripe_Subscription__c": "sub_ABC123",
                "Contact__c": "0031700000IZ3STABC",
                "Status__c": "paid",
                "Tax_Amount__c": 2.50,
                "Discounts_Applied__c": 5.00,
            }
        }


class SalesforcePaymentTransaction(BaseModel):
    """Salesforce Payment_Transaction__c record"""

    Stripe_Payment_Intent_ID__c: str = Field(
        description="External ID - Stripe payment intent ID"
    )
    Amount__c: Optional[float] = None
    Currency__c: Optional[str] = None
    Status__c: Optional[
        Literal[
            "requires_payment_method",
            "requires_confirmation",
            "requires_action",
            "processing",
            "requires_capture",
            "canceled",
            "succeeded",
            "failed",
        ]
    ] = None
    Payment_Method_Type__c: Optional[str] = None
    Transaction_Date__c: Optional[datetime] = None
    Stripe_Subscription__c: Optional[str] = Field(
        None, description="Lookup to Stripe_Subscription__c"
    )
    Stripe_Invoice__c: Optional[str] = Field(
        None, description="Lookup to Stripe_Invoice__c"
    )
    Stripe_Invoice_ID__c: Optional[str] = Field(
        None, description="Stripe Invoice ID (for linking)"
    )
    Failure_Reason__c: Optional[str] = None
    Transaction_Type__c: Optional[
        Literal["initial_payment", "recurring_payment"]
    ] = None

    class Config:
        json_schema_extra = {
            "example": {
                "Stripe_Payment_Intent_ID__c": "pi_ABC123",
                "Amount__c": 29.99,
                "Currency__c": "USD",
                "Status__c": "succeeded",
                "Transaction_Date__c": "2024-10-18T12:00:00Z",
            }
        }


class SalesforceUpsertRequest(BaseModel):
    """Request model for Salesforce upsert operations"""

    sobject_type: str = Field(description="Salesforce object API name")
    external_id_field: str = Field(description="External ID field name")
    records: list[dict] = Field(description="Records to upsert")


class SalesforceUpsertResponse(BaseModel):
    """Response model from Salesforce upsert operations"""

    success: bool
    records_processed: int
    errors: list[dict] = Field(default_factory=list)
    details: dict = Field(default_factory=dict)


class SalesforceContact(BaseModel):
    """Salesforce Contact record with Stripe customer data"""

    Id: Optional[str] = None
    Stripe_Customer_ID__c: Optional[str] = Field(None, description="External ID - Stripe customer ID")
    Email: Optional[str] = None
    FirstName: Optional[str] = None
    LastName: Optional[str] = None
    Phone: Optional[str] = None
    Default_Payment_Method__c: Optional[str] = None
    Subscription_Status__c: Optional[
        Literal["None", "Active", "Past Due", "Canceled"]
    ] = "None"
    Health_Score__c: Optional[float] = None
    Churn_Risk__c: Optional[str] = None
    MRR__c: Optional[float] = None
    Total_Revenue__c: Optional[float] = None

    class Config:
        json_schema_extra = {
            "example": {
                "Stripe_Customer_ID__c": "cus_ABC123",
                "Email": "customer@example.com",
                "FirstName": "John",
                "LastName": "Doe",
                "Phone": "+1234567890",
            }
        }


class SalesforceError(BaseModel):
    """Salesforce API error response"""

    message: str
    errorCode: str
    fields: list[str] = Field(default_factory=list)


class SalesforcePricingPlan(BaseModel):
    """Salesforce Pricing_Plan__c record"""

    Stripe_Price_ID__c: str = Field(
        description="External ID - Stripe price ID"
    )
    ProductName__c: Optional[str] = Field(
        None, description="Name of the product from Stripe"
    )
    Amount__c: Optional[float] = Field(
        None, description="Price amount in the currency's standard unit"
    )
    Currency__c: Optional[str] = Field(
        None, description="Three-letter ISO currency code"
    )
    Recurrency_Type__c: Optional[
        Literal[
            "Daily",
            "Weekly",
            "Monthly",
            "Quarterly",
            "Yearly"
        ]
    ] = Field(None, description="Billing frequency")

    class Config:
        json_schema_extra = {
            "example": {
                "Stripe_Price_ID__c": "price_ABC123",
                "ProductName__c": "Premium Plan",
                "Amount__c": 29.99,
                "Currency__c": "USD",
                "Recurrency_Type__c": "Monthly"
            }
        }


class SalesforcePricingTier(BaseModel):
    """Salesforce Pricing_Tier__c record"""

    Pricing_Plan__c: str = Field(
        description="Master-Detail relationship to Pricing_Plan__c (Salesforce ID)"
    )
    Tier_Number__c: Optional[int] = Field(
        None, description="Tier sequence number"
    )
    From_Quantity__c: Optional[int] = Field(
        None, description="Starting quantity for this tier"
    )
    To_Quantity__c: Optional[int] = Field(
        None, description="Ending quantity for this tier (null means infinity)"
    )
    Unit_Price__c: Optional[float] = Field(
        None, description="Per-unit price in this tier"
    )
    Discount__c: Optional[float] = Field(
        None, description="Discount amount for this tier"
    )

    class Config:
        json_schema_extra = {
            "example": {
                "Pricing_Plan__c": "a0B1700000ABC123",
                "Tier_Number__c": 1,
                "From_Quantity__c": 0,
                "To_Quantity__c": 10,
                "Unit_Price__c": 10.00,
                "Discount__c": 0.00
            }
        }
