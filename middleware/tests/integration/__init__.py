"""
Integration tests for Salesforce-Stripe Payment Processing Middleware.

These tests validate the complete system including:
- Webhook receipt and signature verification
- Event priority routing
- SQS message processing
- Salesforce API integration
- Bulk API batch accumulation
- Error handling and retry logic
"""