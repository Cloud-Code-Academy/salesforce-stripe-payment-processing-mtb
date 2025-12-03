"""
Unit tests for payment_handler module.

Tests all payment-related webhook handlers including:
- payment_intent.succeeded
- payment_intent.payment_failed
- invoice.payment_succeeded (recurring payments)
- invoice.payment_failed (subscription payment failures)
"""
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from datetime import datetime
from app.handlers.payment_handler import PaymentHandler


@pytest.fixture
def mock_salesforce_service():
    """
    Mock Salesforce service with standard responses.
    
    Returns:
        AsyncMock configured with common Salesforce API responses
    """
    mock_service = AsyncMock()
    
    # Default responses
    mock_service.create_record = AsyncMock(return_value={"id": "a01xxx000000001"})
    mock_service.update_record = AsyncMock(return_value={"success": True})
    mock_service.query_records = AsyncMock(return_value={"records": []})
    
    return mock_service


@pytest.fixture
def sample_invoice_succeeded_event():
    """
    Sample invoice.payment_succeeded event from Stripe.
    
    Returns:
        Dictionary representing a successful invoice payment webhook
    """
    return {
        "id": "evt_test_invoice_succeeded",
        "type": "invoice.payment_succeeded",
        "data": {
            "object": {
                "id": "in_1Abc2Def3Ghi4Jkl",
                "subscription": "sub_1TestSubscription",
                "customer": "cus_TestCustomer123",
                "payment_intent": "pi_1TestPaymentIntent",
                "amount_paid": 2999,  # $29.99 in cents
                "currency": "usd",
                "period_start": 1698796800,  # Nov 1, 2023
                "period_end": 1701388800,    # Nov 30, 2023
                "status": "paid",
                "lines": {
                    "data": [
                        {
                            "description": "Premium Plan",
                            "amount": 2999
                        }
                    ]
                }
            }
        }
    }


@pytest.fixture
def sample_invoice_failed_event():
    """
    Sample invoice.payment_failed event from Stripe.
    
    Returns:
        Dictionary representing a failed invoice payment webhook
    """
    return {
        "id": "evt_test_invoice_failed",
        "type": "invoice.payment_failed",
        "data": {
            "object": {
                "id": "in_1Xyz2Uvw3Rst4Opq",
                "subscription": "sub_1TestSubscription",
                "customer": "cus_TestCustomer123",
                "payment_intent": "pi_1TestPaymentIntent",
                "amount_due": 2999,  # $29.99 in cents
                "currency": "usd",
                "status": "open",
                "attempt_count": 1,
                "last_payment_error": {
                    "code": "card_declined",
                    "message": "Your card was declined",
                    "decline_code": "insufficient_funds"
                }
            }
        }
    }


@pytest.mark.asyncio
class TestInvoicePaymentSucceeded:
    """Test suite for invoice.payment_succeeded handler"""
    
    async def test_invoice_succeeded_creates_transaction(
        self,
        sample_invoice_succeeded_event,
        mock_salesforce_service
    ):
        """
        Test that successful invoice payment creates Payment_Transaction__c record.
        
        Verifies:
        1. Transaction record created with correct fields
        2. Amount converted from cents to dollars
        3. Transaction type set to 'recurring_payment'
        4. Status set to 'succeeded'
        """
        with patch('app.handlers.payment_handler.sf_service', mock_salesforce_service):
            # Mock subscription query to return Salesforce ID
            mock_salesforce_service.query_records = AsyncMock(return_value={
                "records": [
                    {
                        "Id": "a00xxx000000001",
                        "Contact__c": "a02xxx000000001"
                    }
                ]
            })
            
            result = await PaymentHandler.handle_invoice_payment_succeeded(
                sample_invoice_succeeded_event
            )
            
            # Verify transaction created
            assert result["transaction_id"] == "a01xxx000000001"
            assert result["invoice_id"] == "in_1Abc2Def3Ghi4Jkl"
            assert abs(result["amount"] - 29.99) < 0.01
            
            # Verify create_record was called with correct data
            mock_salesforce_service.create_record.assert_called_once()
            call_args = mock_salesforce_service.create_record.call_args
            
            assert call_args.kwargs["sobject"] == "Payment_Transaction__c"
            
            transaction_data = call_args.kwargs["data"]
            assert transaction_data["Stripe_Invoice_ID__c"] == "in_1Abc2Def3Ghi4Jkl"
            assert abs(transaction_data["Amount__c"] - 29.99) < 0.01
            assert transaction_data["Currency__c"] == "USD"
            assert transaction_data["Status__c"] == "succeeded"
            assert transaction_data["Transaction_Type__c"] == "recurring_payment"
            assert transaction_data["Stripe_Subscription__c"] == "a00xxx000000001"
    
    async def test_invoice_succeeded_updates_subscription_period(
        self,
        sample_invoice_succeeded_event,
        mock_salesforce_service
    ):
        """
        Test that subscription billing period dates are updated after successful payment.
        
        Verifies:
        1. Subscription queried by Stripe ID
        2. Period start/end dates updated
        3. Status set to 'active'
        4. Sync status set to 'Completed'
        """
        with patch('app.handlers.payment_handler.sf_service', mock_salesforce_service):
            mock_salesforce_service.query_records = AsyncMock(return_value={
                "records": [{"Id": "a00xxx000000001", "Contact__c": "a02xxx"}]
            })
            
            await PaymentHandler.handle_invoice_payment_succeeded(
                sample_invoice_succeeded_event
            )
            
            # Verify subscription updated
            mock_salesforce_service.update_record.assert_called_once()
            call_args = mock_salesforce_service.update_record.call_args
            
            assert call_args.kwargs["sobject"] == "Stripe_Subscription__c"
            assert call_args.kwargs["external_id_field"] == "Stripe_Subscription_ID__c"
            assert call_args.kwargs["external_id"] == "sub_1TestSubscription"
            
            update_data = call_args.kwargs["data"]
            assert update_data["Status__c"] == "active"
            assert update_data["Sync_Status__c"] == "Completed"
            assert "Current_Period_Start__c" in update_data
            assert "Current_Period_End__c" in update_data
            assert update_data["Error_Message__c"] is None
    
    async def test_invoice_succeeded_without_subscription(
        self,
        sample_invoice_succeeded_event,
        mock_salesforce_service
    ):
        """
        Test invoice processing when subscription is not found in Salesforce.
        
        Should still create transaction record but skip period update.
        """
        # Remove subscription from event
        event_copy = sample_invoice_succeeded_event.copy()
        event_copy["data"]["object"]["subscription"] = None
        
        with patch('app.handlers.payment_handler.sf_service', mock_salesforce_service):
            mock_salesforce_service.query_records = AsyncMock(return_value={
                "records": []
            })
            
            result = await PaymentHandler.handle_invoice_payment_succeeded(event_copy)
            
            # Transaction should still be created
            assert result["transaction_id"] == "a01xxx000000001"
            
            # Subscription should not be updated
            mock_salesforce_service.update_record.assert_not_called()


@pytest.mark.asyncio
class TestInvoicePaymentFailed:
    """Test suite for invoice.payment_failed handler"""
    
    async def test_invoice_failed_creates_failed_transaction(
        self,
        sample_invoice_failed_event,
        mock_salesforce_service
    ):
        """
        Test that failed invoice payment creates failed Payment_Transaction__c record.
        
        Verifies:
        1. Transaction created with status 'failed'
        2. Failure reason captured from Stripe error
        3. Decline code included if present
        """
        with patch('app.handlers.payment_handler.sf_service', mock_salesforce_service):
            mock_salesforce_service.query_records = AsyncMock(return_value={
                "records": [{"Id": "a00xxx000000001", "Contact__c": "a02xxx"}]
            })
            
            result = await PaymentHandler.handle_invoice_payment_failed(
                sample_invoice_failed_event
            )
            
            # Verify failed transaction created
            assert result["transaction_id"] == "a01xxx000000001"
            assert result["invoice_id"] == "in_1Xyz2Uvw3Rst4Opq"
            assert "card_declined" in result["failure_reason"]
            assert result["attempt_count"] == 1
            
            # Verify create_record called with failure data
            call_args = mock_salesforce_service.create_record.call_args
            transaction_data = call_args.kwargs["data"]
            
            assert transaction_data["Status__c"] == "failed"
            assert transaction_data["Transaction_Type__c"] == "recurring_payment"
            assert "card_declined" in transaction_data["Failure_Reason__c"]
            assert "insufficient_funds" in transaction_data["Failure_Reason__c"]
    
    async def test_invoice_failed_updates_subscription_to_past_due(
        self,
        sample_invoice_failed_event,
        mock_salesforce_service
    ):
        """
        Test that subscription status is updated to 'past_due' after payment failure.
        
        Verifies:
        1. Subscription status set to 'past_due'
        2. Sync status set to 'Failed'
        3. Error message stored with attempt count
        """
        with patch('app.handlers.payment_handler.sf_service', mock_salesforce_service):
            mock_salesforce_service.query_records = AsyncMock(return_value={
                "records": [{"Id": "a00xxx000000001", "Contact__c": "a02xxx"}]
            })
            
            await PaymentHandler.handle_invoice_payment_failed(
                sample_invoice_failed_event
            )
            
            # Verify subscription updated to past_due
            mock_salesforce_service.update_record.assert_called_once()
            call_args = mock_salesforce_service.update_record.call_args
            
            update_data = call_args.kwargs["data"]
            assert update_data["Status__c"] == "past_due"
            assert update_data["Sync_Status__c"] == "Failed"
            assert "card_declined" in update_data["Error_Message__c"]
            assert "(Attempt 1)" in update_data["Error_Message__c"]
    
    async def test_invoice_failed_handles_missing_error_details(
        self,
        sample_invoice_failed_event,
        mock_salesforce_service
    ):
        """
        Test graceful handling when invoice failure event lacks error details.
        
        Should use default error message: "Payment failed"
        """
        # Remove last_payment_error from event
        event_copy = sample_invoice_failed_event.copy()
        event_copy["data"]["object"]["last_payment_error"] = None
        
        with patch('app.handlers.payment_handler.sf_service', mock_salesforce_service):
            mock_salesforce_service.query_records = AsyncMock(return_value={
                "records": [{"Id": "a00xxx000000001", "Contact__c": "a02xxx"}]
            })
            
            result = await PaymentHandler.handle_invoice_payment_failed(event_copy)
            
            # Should use default failure message
            assert "Payment failed" in result["failure_reason"]
            
            call_args = mock_salesforce_service.create_record.call_args
            transaction_data = call_args.kwargs["data"]
            assert "Payment failed" in transaction_data["Failure_Reason__c"]


@pytest.mark.asyncio
class TestHelperFunctions:
    """Test suite for internal helper functions"""
    
    async def test_get_stripe_customer_id_found(self, mock_salesforce_service):
        """Test querying Stripe Customer when record exists"""
        with patch('app.handlers.payment_handler.sf_service', mock_salesforce_service):
            mock_salesforce_service.query_records = AsyncMock(return_value={
                "records": [{"Id": "a02xxx000000001"}]
            })
            
            result = await PaymentHandler._get_stripe_customer_id("cus_test123")
            
            assert result == "a02xxx000000001"
            mock_salesforce_service.query_records.assert_called_once()
    
    async def test_get_stripe_customer_id_not_found(self, mock_salesforce_service):
        """Test querying Stripe Customer when record doesn't exist"""
        with patch('app.handlers.payment_handler.sf_service', mock_salesforce_service):
            mock_salesforce_service.query_records = AsyncMock(return_value={
                "records": []
            })
            
            result = await PaymentHandler._get_stripe_customer_id("cus_test123")
            
            assert result is None
    
    async def test_update_subscription_period_converts_timestamps(
        self,
        mock_salesforce_service
    ):
        """Test that Unix timestamps are correctly converted to ISO format"""
        with patch('app.handlers.payment_handler.sf_service', mock_salesforce_service):
            await PaymentHandler._update_subscription_period(
                subscription_id="sub_test123",
                subscription_sf_id="a00xxx000000001",
                period_start=1698796800,  # Nov 1, 2023 00:00:00 UTC
                period_end=1701388800     # Nov 30, 2023 00:00:00 UTC
            )
            
            call_args = mock_salesforce_service.update_record.call_args
            update_data = call_args.kwargs["data"]
            
            # Verify datetime conversion
            assert "2023-11-01" in update_data["Current_Period_Start__c"]
            assert "2023-11-30" in update_data["Current_Period_End__c"]