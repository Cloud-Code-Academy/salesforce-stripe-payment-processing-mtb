# Salesforce-Stripe Integration Middleware

FastAPI-based middleware for handling Stripe webhook events and synchronizing data with Salesforce. This service acts as a reliable intermediary between Stripe's webhook system and Salesforce, providing event buffering, signature verification, OAuth authentication, and resilient processing.

## Key Architecture Decisions

This middleware implements the following technology stack:

- **Deployment:** AWS Lambda (serverless) - not using ECS
- **Storage:** DynamoDB for OAuth token caching and temporary storage - not using Redis
- **Monitoring:** CloudWatch for centralized logging and metrics - not using Coralogix
- **Event Handling:** Including `customer.subscription.created` webhook events
- **Development:** Docker for local development and testing - not using Terraform for IaC
- **Demo Environment:** Trailhead Playground for final presentation (Connected Apps don't work in scratch orgs)

## Architecture Overview

```
Stripe Webhooks → FastAPI Middleware → SQS Queue → Event Processing → Salesforce API
                      ↓                                                      ↑
                   Signature                                           OAuth 2.0
                  Verification                                     Token Caching
                      ↓                                                      ↓
                  Return 200 OK                                        DynamoDB
```

### Key Components

- **FastAPI Application**: Async webhook endpoint with signature verification
- **AWS SQS**: Event buffering and asynchronous processing queue
- **DynamoDB**: OAuth token caching and temporary storage
- **Salesforce OAuth**: Automated token management with refresh
- **Event Router**: Routes events to appropriate handlers based on type
- **Handlers**: Process specific event types (customer, subscription, payment)

## Features

- ✅ **Stripe Webhook Signature Verification** (HMAC-SHA256)
- ✅ **AWS SQS Integration** for event buffering
- ✅ **DynamoDB Storage** for OAuth tokens and temporary data
- ✅ **Salesforce OAuth 2.0** with automatic token refresh
- ✅ **Event Router Pattern** with idempotency
- ✅ **Structured JSON Logging** with correlation IDs
- ✅ **Exponential Backoff Retry** logic
- ✅ **Health Check Endpoints** for monitoring
- ✅ **Docker Support** for easy deployment
- ✅ **Comprehensive Test Suite** with pytest
- ✅ **CloudWatch Integration** for monitoring and logging

## Supported Stripe Events

All critical webhook events are supported:

| Event Type | Priority | Salesforce Action |
|------------|----------|-------------------|
| `checkout.session.completed` | High | Update subscription sync status to Completed |
| `customer.subscription.created` | High | Create Stripe_Subscription__c record (newly added) |
| `customer.subscription.deleted` | High | Update subscription status to canceled |
| `payment_intent.succeeded` | High | Create Payment_Transaction__c record |
| `payment_intent.payment_failed` | High | Create failed transaction record |
| `customer.subscription.updated` | Low | Update Stripe_Subscription__c status (batched) |
| `customer.updated` | Low | Update Stripe_Customer__c record (batched) |

## Prerequisites

- Python 3.11+
- Docker & Docker Compose (for local development)
- AWS Account with Lambda access (for production deployment)
- Salesforce Connected App with OAuth enabled (use Trailhead Playground)
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
│   │   └── dynamodb_service.py    # DynamoDB storage operations
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

```

### 3. Run with Docker Compose (Recommended)

```bash
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

# Ensure DynamoDB and SQS are running separately (or use LocalStack)

# Run application
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Salesforce Setup

### 1. Create Connected App

**Note:** Connected Apps do not work in scratch orgs. Use a Trailhead Playground for demo purposes.

1. In Salesforce Setup (Trailhead Playground), go to **App Manager** → **New Connected App**
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

### 2. Configure Webhook - IMPORTANT ⚡

Stripe requires **publicly accessible HTTPS endpoints** for webhooks. Since `localhost:8000` is not publicly accessible, you have **three options** depending on your development stage:

#### Option A: Stripe CLI (RECOMMENDED for Development)

**Best for:** Local development, testing, individual work

The Stripe CLI creates a secure tunnel from Stripe to your localhost - no public URL needed!

```bash
# 1. Install Stripe CLI
# macOS
brew install stripe/stripe-cli/stripe

# Windows (Scoop)
scoop bucket add stripe https://github.com/stripe/scoop-stripe-cli.git
scoop install stripe

# Linux
wget https://github.com/stripe/stripe-cli/releases/latest/download/stripe_linux_amd64.tar.gz
tar -xvf stripe_linux_amd64.tar.gz
sudo mv stripe /usr/local/bin/

# 2. Login to Stripe
stripe login

# 3. Start webhook forwarding (keep this running!)
stripe listen --forward-to localhost:8000/webhook/stripe

# 4. Copy the webhook signing secret shown
# Look for: "Your webhook signing secret is whsec_..."

# 5. Update your .env file
STRIPE_WEBHOOK_SECRET=whsec_abc123xyz...from_cli_output

# 6. Restart middleware
docker-compose restart middleware

# 7. Test with triggers (in another terminal)
stripe trigger payment_intent.succeeded
stripe trigger checkout.session.completed
stripe trigger customer.subscription.updated
```

**Benefits:**
- ✅ No public URL needed
- ✅ Real webhook signatures for testing
- ✅ Easy event triggering with `stripe trigger`
- ✅ Free and secure
- ✅ Perfect for local development

**When to use:** Week 2-3 development phase, individual testing

---

#### Option B: Ngrok (for Team Sharing/Demos)

**Best for:** Sharing your local instance with teammates, quick demos

```bash
# 1. Install ngrok
brew install ngrok  # macOS
# Or download from https://ngrok.com/download

# 2. Sign up and get auth token from https://ngrok.com
ngrok config add-authtoken YOUR_AUTH_TOKEN

# 3. Start your middleware
docker-compose up -d

# 4. Start ngrok tunnel
ngrok http 8000

# 5. Copy the public HTTPS URL shown
# Example: https://abc123-def.ngrok-free.app

# 6. Configure in Stripe Dashboard
# Go to: Developers → Webhooks → Add Endpoint
# URL: https://abc123-def.ngrok-free.app/webhook/stripe
# Events: (select all events listed below)

# 7. Copy webhook signing secret from Stripe Dashboard
# Update .env: STRIPE_WEBHOOK_SECRET=whsec_from_dashboard

# 8. Restart middleware
docker-compose restart middleware
```

**Benefits:**
- ✅ Real public HTTPS URL
- ✅ Works with Stripe Dashboard
- ✅ Team members can access your instance
- ✅ Free tier available

**Limitations:**
- ⚠️ URL changes on restart (unless paid plan)
- ⚠️ Computer must stay on
- ⚠️ Free tier: 60 requests/min limit

**When to use:** Team collaboration, sharing progress, quick demos

---

#### Option C: Cloud Deployment (for Production/Final Demo)

**Best for:** Final presentation, team collaboration, production

See [Deployment](#deployment) section below for detailed instructions.

**When to use:** Week 4 presentation, final deliverable

---

### Webhook Events to Configure

Regardless of which option you choose, configure these events in Stripe:

**High-Priority Events (Real-time Processing):**
- ✅ `checkout.session.completed`
- ✅ `customer.subscription.created` ⭐ (newly implemented)
- ✅ `customer.subscription.deleted`
- ✅ `payment_intent.succeeded`
- ✅ `payment_intent.payment_failed`

**Low-Priority Events (Batched Processing):**
- ✅ `customer.subscription.updated`
- ✅ `customer.updated`

### Get Your Webhook Signing Secret

The webhook signing secret location depends on your setup method:

- **Stripe CLI:** Shown in terminal when you run `stripe listen`
- **Ngrok/Cloud:** Stripe Dashboard → Developers → Webhooks → Click your endpoint → "Signing secret"

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

## Team Collaboration

This project supports **team-based development** with multiple collaboration models:

### Model 1: Individual Development (RECOMMENDED for Week 2-3)

Each team member runs their own middleware instance:

```
Team Member 1          Team Member 2          Team Member 3
     ↓                      ↓                      ↓
Own Middleware         Own Middleware         Own Middleware
     ↓                      ↓                      ↓
Own Scratch Org        Own Scratch Org        Own Scratch Org
     ↓                      ↓                      ↓
  Shared Stripe       Shared Stripe          Shared Stripe
  Test Account        Test Account           Test Account
```

**Setup for each team member:**

```bash
# 1. Clone repository
git clone <your-repo-url>
cd salesforce-stripe-payment-processing-mtb/middleware

# 2. Create personal .env
cp .env.example .env

# 3. Configure with:
# - SHARED: Same Stripe API keys for all team members
# - INDIVIDUAL: Own Salesforce scratch org credentials (or Trailhead Playground)
# - LOCAL: Own Docker containers (DynamoDB, LocalStack)

# 4. Start personal instance
docker-compose up -d

# 5. Use Stripe CLI for webhooks
stripe listen --forward-to localhost:8000/webhook/stripe
```

**Benefits:**
- ✅ No conflicts between team members
- ✅ Independent development and testing
- ✅ Works offline
- ✅ No network configuration needed

---

### Model 2: Shared Development Instance (for Team Testing)

One team member hosts the middleware, others access via Ngrok:

```bash
# Host (one team member):
docker-compose up -d
ngrok http 8000
# Share URL: https://abc123.ngrok-free.app

# Team members:
curl https://abc123.ngrok-free.app/health
open https://abc123.ngrok-free.app/docs
```

**When to use:** Integration testing, demos, showing progress

---

### Model 3: Cloud Deployment (for Final Demo)

Deploy one instance to AWS Lambda for final presentation:

```bash
# Deploy to AWS Lambda using SAM
sam build
sam deploy --guided

# Everyone uses: https://your-api-gateway-url.amazonaws.com

# Note: Use Trailhead Playground for Salesforce demo (Connected Apps don't work in scratch orgs)
```

**When to use:** Week 4 presentation, instructor evaluation

---

### Recommended Team Workflow

**Week 2-3 (Development):**
- Each member runs own middleware locally
- Use Stripe CLI for webhook testing
- Share code via Git, work independently

**Week 3 (Integration Testing):**
- One member runs Ngrok to share instance
- Team tests integration points together
- Optional: Deploy to AWS Lambda for team testing

**Week 4 (Demo/Presentation):**
- Deploy to AWS Lambda
- Set up Trailhead Playground for Salesforce demo (Connected Apps don't work in scratch orgs)
- Professional public endpoint via API Gateway
- Use for final demonstration

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


## Security Best Practices

✅ **Implemented:**
- Webhook signature verification (HMAC-SHA256)
- OAuth 2.0 for Salesforce authentication
- AWS Secrets Manager support for production
- Non-root Docker user
- Input validation with Pydantic
- Secure token caching with TTL in DynamoDB
- CloudWatch logging for audit trails

🔒 **Additional Recommendations:**
- Use AWS Secrets Manager in production (configured)
- Enable VPC for Lambda functions
- Implement API rate limiting with DynamoDB sliding window
- Regular secret rotation (90-day policy)
- Monitor failed authentication attempts via CloudWatch alarms

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

```

**4. SQS permission denied**
```
Error: Failed to send message to queue
Solution: Verify AWS credentials have SQS SendMessage permission
```

## Performance Optimization

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