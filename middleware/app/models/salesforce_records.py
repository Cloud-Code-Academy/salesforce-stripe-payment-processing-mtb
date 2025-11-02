"""
Salesforce Record Models

Pydantic models for Salesforce API operations.
"""

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field


class SalesforceCustomer(BaseModel):
    """Salesforce Stripe_Customer__c record"""

    Stripe_Customer_ID__c: str = Field(description="External ID - Stripe customer ID")
    Customer_Email__c: Optional[str] = None
    Customer_Name__c: Optional[str] = None
    Customer_Phone__c: Optional[str] = None
    Default_Payment_Method__c: Optional[str] = None
    Subscription_Status__c: Optional[
        Literal["None", "Active", "Past Due", "Canceled"]
    ] = "None"
    Contact__c: Optional[str] = Field(None, description="Lookup to Contact")

    class Config:
        json_schema_extra = {
            "example": {
                "Stripe_Customer_ID__c": "cus_ABC123",
                "Customer_Email__c": "customer@example.com",
                "Customer_Name__c": "John Doe",
                "Subscription_Status__c": "Active",
            }
        }


class SalesforceSubscription(BaseModel):
    """Salesforce Stripe_Subscription__c record"""

    Stripe_Subscription_ID__c: str = Field(
        description="External ID - Stripe subscription ID"
    )
    Stripe_Customer__c: Optional[str] = Field(
        None, description="Lookup to Stripe_Customer__c (by External ID)"
    )
    Product_Plan_Name__c: Optional[str] = None
    Stripe_Price_ID__c: Optional[str] = None
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
                "Stripe_Customer__c": "cus_ABC123",
                "Status__c": "active",
                "Amount__c": 29.99,
                "Currency__c": "USD",
            }
        }


class SalesforcePaymentTransaction(BaseModel):
    """Salesforce Payment_Transaction__c record"""

    Stripe_Payment_Intent_ID__c: str = Field(
        description="External ID - Stripe payment intent ID"
    )
    Stripe_Customer__c: Optional[str] = Field(
        None, description="Lookup to Stripe_Customer__c"
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
        ]
    ] = None
    Payment_Method_Type__c: Optional[str] = None
    Transaction_Date__c: Optional[datetime] = None
    Stripe_Subscription__c: Optional[str] = Field(
        None, description="Lookup to Stripe_Subscription__c"
    )

    class Config:
        json_schema_extra = {
            "example": {
                "Stripe_Payment_Intent_ID__c": "pi_ABC123",
                "Stripe_Customer__c": "cus_ABC123",
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
    """Salesforce Contact record"""

    Stripe_Customer_ID__c: Optional[str] = Field(None, description="External ID - Stripe customer ID")
    Email: Optional[str] = None
    FirstName: Optional[str] = None
    LastName: Optional[str] = None
    Phone: Optional[str] = None

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
