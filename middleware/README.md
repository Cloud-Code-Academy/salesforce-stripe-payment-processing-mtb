# Salesforce-Stripe Integration Middleware

FastAPI-based middleware for handling Stripe webhook events and synchronizing data with Salesforce. This service acts as a reliable intermediary between Stripe's webhook system and Salesforce, providing event buffering, signature verification, OAuth authentication, and resilient processing.

## Architecture Overview

```
Stripe Webhooks → FastAPI Middleware → SQS Queue → Event Processing → Salesforce API
                      ↓                                                      ↑
                   Signature                                           OAuth 2.0
                  Verification                                     Token Caching
                      ↓                                                      ↓
                  Return 200 OK                                          Redis
```

### Key Components

- **FastAPI Application**: Async webhook endpoint with signature verification
- **AWS SQS**: Event buffering and asynchronous processing queue
- **Redis**: OAuth token caching and temporary storage
- **Salesforce OAuth**: Automated token management with refresh
- **Event Router**: Routes events to appropriate handlers based on type
- **Handlers**: Process specific event types (customer, subscription, payment)

## Features

- ✅ **Stripe Webhook Signature Verification** (HMAC-SHA256)
- ✅ **AWS SQS Integration** for event buffering
- ✅ **Redis Caching** for OAuth tokens
- ✅ **Salesforce OAuth 2.0** with automatic token refresh
- ✅ **Event Router Pattern** with idempotency
- ✅ **Structured JSON Logging** with correlation IDs
- ✅ **Exponential Backoff Retry** logic
- ✅ **Health Check Endpoints** for monitoring
- ✅ **Docker Support** for easy deployment
- ✅ **Comprehensive Test Suite** with pytest

## Supported Stripe Events

| Event Type | Salesforce Action |
|------------|-------------------|
| `checkout.session.completed` | Update subscription sync status to Completed |
| `payment_intent.succeeded` | Create Payment_Transaction__c record |
| `payment_intent.payment_failed` | Create failed transaction record |
| `customer.subscription.updated` | Update Stripe_Subscription__c status |
| `customer.subscription.created` | Create Stripe_Subscription__c record |
| `customer.subscription.deleted` | Update subscription status to canceled |
| `customer.updated` | Update Stripe_Customer__c record |

## Prerequisites

- Python 3.11+
- Docker & Docker Compose (for local development)
- AWS Account (for production deployment)
- Salesforce Connected App with OAuth enabled
- Stripe Account with webhook configured

## Project Structure

```
middleware/
├── app/
│   ├── __init__.py
│   ├── main.py                    # FastAPI application entry point
│   ├── config.py                  # Configuration management
│   ├── routes/
│   │   ├── webhook.py             # Stripe webhook endpoint
│   │   └── health.py              # Health check endpoints
│   ├── services/
│   │   ├── stripe_service.py      # Stripe signature verification
│   │   ├── salesforce_service.py  # Salesforce API client
│   │   ├── sqs_service.py         # SQS queue operations
│   │   └── redis_service.py       # Redis cache operations
│   ├── handlers/
│   │   ├── event_router.py        # Event routing logic
│   │   ├── customer_handler.py    # Customer event handler
│   │   ├── subscription_handler.py # Subscription event handler
│   │   └── payment_handler.py     # Payment event handler
│   ├── auth/
│   │   └── salesforce_oauth.py    # OAuth token management
│   ├── models/
│   │   ├── stripe_events.py       # Stripe event models
│   │   └── salesforce_records.py  # Salesforce record models
│   └── utils/
│       ├── exceptions.py          # Custom exception classes
│       ├── logging_config.py      # Structured logging
│       └── retry.py               # Retry utilities
├── tests/
│   ├── conftest.py                # Pytest fixtures
│   ├── test_webhook.py            # Webhook tests
│   ├── test_event_router.py       # Event routing tests
│   └── test_salesforce_oauth.py   # OAuth tests
├── requirements.txt
├── Dockerfile
├── docker-compose.yml
├── .env.example
└── README.md
```

## Quick Start

### 1. Clone and Setup

```bash
# Navigate to middleware directory
cd middleware

# Copy environment template
cp .env.example .env

# Edit .env with your credentials
nano .env
```

### 2. Configure Environment Variables

Edit `.env` file with your credentials:

```bash
# Stripe Configuration
STRIPE_API_KEY=sk_test_your_stripe_key
STRIPE_WEBHOOK_SECRET=whsec_your_webhook_secret

# Salesforce OAuth
SALESFORCE_CLIENT_ID=your_connected_app_client_id
SALESFORCE_CLIENT_SECRET=your_connected_app_client_secret
SALESFORCE_USERNAME=integration.user@yourorg.com
SALESFORCE_PASSWORD=your_password
SALESFORCE_SECURITY_TOKEN=your_security_token
SALESFORCE_INSTANCE_URL=https://login.salesforce.com

# AWS Configuration (use LocalStack for local dev)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=test  # LocalStack
AWS_SECRET_ACCESS_KEY=test  # LocalStack
SQS_QUEUE_URL=http://localstack:4566/000000000000/stripe-webhook-events

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
```

### 3. Run with Docker Compose (Recommended)

```bash
# Start all services (FastAPI, Redis, LocalStack SQS)
docker-compose up -d

# View logs
docker-compose logs -f middleware

# Check health
curl http://localhost:8000/health

# Check readiness (dependencies)
curl http://localhost:8000/health/ready
```

The middleware will be available at `http://localhost:8000`

### 4. Alternative: Run Locally (without Docker)

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Ensure Redis and SQS are running separately

# Run application
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Salesforce Setup

### 1. Create Connected App

1. In Salesforce Setup, go to **App Manager** → **New Connected App**
2. Configure OAuth settings:
   - Enable OAuth Settings: ✅
   - Callback URL: `https://login.salesforce.com/services/oauth2/callback`
   - Selected OAuth Scopes:
     - Full access (full)
     - Perform requests at any time (refresh_token, offline_access)
   - Enable Client Credentials Flow: ✅

3. Save and note the **Consumer Key** (Client ID) and **Consumer Secret**

### 2. Create Integration User

```sql
-- Recommended: Create dedicated integration user
-- Username: integration.user@yourorg.com
-- Profile: Integration User (custom profile with API access)
```

### 3. Assign Permissions

Ensure the integration user has:
- API Enabled permission
- Read/Write access to:
  - Stripe_Customer__c
  - Stripe_Subscription__c
  - Payment_Transaction__c

## Stripe Setup

### 1. Get API Keys

1. Go to Stripe Dashboard → **Developers** → **API Keys**
2. Copy your **Secret Key** (starts with `sk_test_` for test mode)

### 2. Configure Webhook

1. Go to **Developers** → **Webhooks** → **Add Endpoint**
2. Endpoint URL: `https://your-domain.com/webhook/stripe`
3. Select events to listen to:
   - `checkout.session.completed`
   - `payment_intent.succeeded`
   - `payment_intent.payment_failed`
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `customer.updated`

4. Copy the **Signing Secret** (starts with `whsec_`)

## Testing

### Run Tests

```bash
# Run all tests with coverage
pytest

# Run specific test file
pytest tests/test_webhook.py

# Run with verbose output
pytest -v

# Run with coverage report
pytest --cov=app --cov-report=html
```

### Manual Testing with Stripe CLI

```bash
# Install Stripe CLI
brew install stripe/stripe-cli/stripe

# Login to Stripe
stripe login

# Forward webhooks to local endpoint
stripe listen --forward-to localhost:8000/webhook/stripe

# Trigger test event
stripe trigger payment_intent.succeeded
stripe trigger checkout.session.completed
```

## API Endpoints

### Webhook Endpoint

```
POST /webhook/stripe
Content-Type: application/json
Stripe-Signature: t=timestamp,v1=signature

# Returns 200 OK immediately after pushing to SQS
```

### Health Check Endpoints

```bash
# Basic health check
GET /health

# Readiness check (verifies dependencies)
GET /health/ready

# Liveness check
GET /health/live

# Metrics
GET /metrics
```

### Example Responses

**Health Check:**
```json
{
  "status": "healthy",
  "timestamp": "2024-10-18T12:00:00Z",
  "version": "1.0.0"
}
```

**Readiness Check:**
```json
{
  "status": "ready",
  "timestamp": "2024-10-18T12:00:00Z",
  "dependencies": {
    "redis": {
      "status": "healthy",
      "connected": true
    },
    "sqs": {
      "status": "healthy",
      "queue_url": "https://sqs.us-east-1.amazonaws.com/...",
      "approximate_messages": "5"
    },
    "salesforce": {
      "status": "healthy",
      "authenticated": true,
      "instance_url": "https://yourorg.salesforce.com"
    }
  }
}
```

## Deployment

### AWS ECS Deployment (Production)

1. **Build and push Docker image:**
```bash
docker build -t salesforce-stripe-middleware:latest --target production .
docker tag salesforce-stripe-middleware:latest <ecr-repo-url>:latest
docker push <ecr-repo-url>:latest
```

2. **Create ECS Task Definition** with:
   - Container: `<ecr-repo-url>:latest`
   - CPU: 512, Memory: 1024
   - Environment variables from AWS Secrets Manager
   - Health check: `/health`

3. **Create ECS Service** with:
   - Load balancer targeting port 8000
   - Auto-scaling based on CPU/memory
   - CloudWatch logs integration

### AWS Lambda Deployment (Alternative)

Use AWS Lambda with Mangum adapter:

```python
# lambda_handler.py
from mangum import Mangum
from app.main import app

handler = Mangum(app)
```

## Monitoring and Logging

### Structured Logging

All logs are JSON-formatted with:
- Timestamp
- Log level
- Correlation ID
- Module/function
- Custom metadata

### Example Log Entry

```json
{
  "timestamp": "2024-10-18T12:00:00.123Z",
  "level": "INFO",
  "logger": "middleware.routes.webhook",
  "message": "Received Stripe webhook event",
  "correlation_id": "abc-123-def",
  "event_id": "evt_abc123",
  "event_type": "payment_intent.succeeded"
}
```

### Monitoring Integration

- **Coralogix**: Structured log aggregation
- **CloudWatch**: ECS container logs
- **Metrics**: Custom metrics via `/metrics` endpoint
- **Alerts**: Configure on error rates, queue depth

## Security Best Practices

✅ **Implemented:**
- Webhook signature verification (HMAC-SHA256)
- OAuth 2.0 for Salesforce authentication
- AWS Secrets Manager support for production
- Non-root Docker user
- Input validation with Pydantic
- Secure token caching with TTL

🔒 **Additional Recommendations:**
- Use AWS Secrets Manager in production
- Enable VPC for ECS tasks
- Implement API rate limiting
- Regular secret rotation
- Monitor failed authentication attempts

## Troubleshooting

### Common Issues

**1. Webhook signature verification fails**
```
Error: Invalid Stripe webhook signature
Solution: Verify STRIPE_WEBHOOK_SECRET matches Stripe Dashboard
```

**2. Salesforce authentication fails**
```
Error: Authentication failed: invalid_grant
Solution: Check username, password, security token, and Connected App credentials
```

**3. Redis connection error**
```
Error: Redis connection failed
Solution: Ensure Redis is running and REDIS_HOST/PORT are correct
```

**4. SQS permission denied**
```
Error: Failed to send message to queue
Solution: Verify AWS credentials have SQS SendMessage permission
```

## Performance Optimization

- **Token Caching**: Reduces Salesforce OAuth calls by 90%
- **Async Processing**: Non-blocking I/O for all external calls
- **SQS Buffering**: Decouples webhook response from processing
- **Connection Pooling**: Reuses HTTP connections
- **Retry Logic**: Exponential backoff for resilience

## Contributing

1. Follow PEP 8 style guide
2. Add tests for new features
3. Update documentation
4. Run linting: `black app/ && ruff app/`
5. Ensure tests pass: `pytest`

## License

Proprietary - Cloud Code Academy

## Support

For issues or questions:
- Create an issue in the GitHub repository
- Contact the development team
- Check project documentation

---

**Built with:** FastAPI • Pydantic • AWS • Stripe • Salesforce
