# Salesforce-Stripe Payment Processing Integration

A production-ready integration platform connecting Salesforce with Stripe for seamless customer subscription and payment management. This capstone project demonstrates advanced integration patterns, real-time data synchronization, and enterprise-grade error handling.

**Repository**: [Cloud-Code-Academy/salesforce-stripe-payment-processing-mtb](https://github.com/Cloud-Code-Academy/salesforce-stripe-payment-processing-mtb)

---

## 📋 Table of Contents

- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Project Structure](#project-structure)
- [Features](#features)
- [Technical Stack](#technical-stack)
- [Development Workflow](#development-workflow)
- [Testing](#testing)
- [Security](#security)
- [Deployment](#deployment)
- [Monitoring & Observability](#monitoring--observability)
- [Troubleshooting](#troubleshooting)
- [Team Collaboration](#team-collaboration)

---

## 🎯 Project Overview

This capstone project challenges you to build a **production-ready payment processing solution** that integrates Salesforce with Stripe. The system manages the complete customer payment lifecycle—from contact creation through subscription management to payment tracking—synchronizing data bidirectionally between Salesforce and Stripe while handling real-world complexity like network failures, rate limiting, and concurrent updates.

### Business Value

**Sales Representatives** can:
- Create customer records that automatically sync to Stripe
- Set up subscriptions with multiple pricing plans
- Generate secure checkout links for customers
- Track subscription status and billing periods

**Customer Service Teams** can:
- View real-time payment and subscription information
- Access complete transaction history
- Identify customers with payment issues
- Help customers with billing questions

**Finance Teams** can:
- Monitor subscription revenue and churn
- Track payment successes and failures
- Generate revenue reports and dashboards
- Identify customers requiring intervention

---

## 🏗️ Architecture

### High-Level System Design

```
┌─────────────────────────────────────────────────────────────────┐
│                     SALESFORCE ECOSYSTEM                         │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Contact Trigger → ContactTriggerHandler/Helper          │   │
│  │  ↓                                                        │   │
│  │  StripeCustomerService (Customer Sync)                   │   │
│  │  StripeSubscriptionService (Subscription Mgmt)           │   │
│  │  ↓                                                        │   │
│  │  Named Credentials (Stripe API Authentication)           │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           ↓                                       │
└──────────────────────────┼────────────────────────────────────────┘
                           │ (Sync)
                    STRIPE API (REST)
                           │ (Webhooks)
┌──────────────────────────┼────────────────────────────────────────┐
│                MIDDLEWARE ARCHITECTURE (FastAPI)                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  POST /webhook/stripe - Webhook Receiver                 │   │
│  │  ├─ Verify Stripe Signature (HMAC-SHA256)                │   │
│  │  ├─ Parse Event Payload                                  │   │
│  │  └─ Push to SQS Queue (return 200 immediately)           │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           ↓                                       │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  SQS Queue → Event Consumer (Asynchronous Processing)    │   │
│  │  ├─ Event Router (Strategy Pattern)                      │   │
│  │  ├─ Priority-Based Processing (High/Low)                 │   │
│  │  ├─ Sliding Window Rate Limiter (DynamoDB)               │   │
│  │  └─ Idempotency Checks                                   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           ↓                                       │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Event Handlers (Customer, Subscription, Payment)        │   │
│  │  ├─ OAuth Token Management (DynamoDB Cache)              │   │
│  │  ├─ Salesforce REST API Client                           │   │
│  │  ├─ Retry Logic (Exponential Backoff)                    │   │
│  │  └─ Structured Logging (CloudWatch)                      │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           ↓                                       │
│  AWS Services:                                                   │
│  ├─ SQS: Event buffering & async processing                     │
│  ├─ DynamoDB: Token caching, rate limiting, temp storage        │
│  ├─ Secrets Manager: Credentials storage                        │
│  ├─ Lambda: Serverless deployment                               │
│  └─ CloudWatch: Logging & monitoring                            │
└──────────────────────────┼────────────────────────────────────────┘
                           │ (Update)
         SALESFORCE REST API (OAuth 2.0)
                           │
┌──────────────────────────┴────────────────────────────────────────┐
│            SALESFORCE DATA LAYER (Custom Objects)                │
│  ├─ Stripe_Customer__c                                           │
│  ├─ Stripe_Subscription__c                                       │
│  ├─ Stripe_Invoice__c                                            │
│  ├─ Payment_Transaction__c                                       │
│  ├─ Pricing_Plan__c & Pricing_Tier__c                            │
│  └─ Contact (extended with Stripe fields)                        │
└─────────────────────────────────────────────────────────────────┘
```

### Data Model Overview

**Custom Objects**:
- **Stripe_Customer__c** - Maps Contact to Stripe customer with sync status
- **Stripe_Subscription__c** - Tracks subscriptions with billing periods and checkout sessions
- **Stripe_Invoice__c** - Records recurring billing cycles and payment status
- **Payment_Transaction__c** - Tracks individual payment attempts (success/failure)
- **Pricing_Plan__c** - Manages subscription pricing plans (Custom Metadata)
- **Pricing_Tier__c** - Supports tiered/volume pricing (Master-Detail to Pricing_Plan)

**Relationships**: Contact (1) → Stripe_Customer (M) → Stripe_Subscription (M) → Payment_Transaction (M)

See [requirements/technical.md](requirements/technical.md#customer--payment-data-model) for complete data model specification.

---

## 🚀 Quick Start

### Prerequisites

- **Salesforce CLI** (v2+): [Installation Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.html)
- **Node.js** 16+ (for Salesforce CLI)
- **Python** 3.9+ (for middleware development)
- **Git** for version control
- **AWS Account** (for middleware deployment) with credentials configured
- **Stripe Account** (test mode)
- **Dev Hub Org** (or scratch org enabled production org)

### Initial Setup (< 15 minutes)

```bash
# 1. Clone repository
git clone https://github.com/Cloud-Code-Academy/salesforce-stripe-payment-processing-mtb.git
cd salesforce-stripe-payment-processing-mtb

# 2. Authenticate with Dev Hub
sf org login web --set-default-dev-hub

# 3. Create scratch org
sf org create scratch --definition-file config/stripe-scratch-def.json --alias stripe-dev

# 4. Deploy metadata
sf project deploy start --target-org stripe-dev

# 5. Assign permission sets
sf org assign permset --name Stripe_Integration_User --target-org stripe-dev

# 6. Create Stripe Named Credential (manual via UI)
# Navigate to Setup → Named Credentials → New
# - Label: Stripe_API_Credentials
# - URL: https://api.stripe.com/v1
# - Authentication: Header auth with Stripe API key
# - External Principal: Stripe

# 7. Open org
sf org open --target-org stripe-dev
```

### Run Tests

```bash
# Apex tests
sf apex run test --target-org stripe-dev --result-format human

# Middleware tests (from middleware/ directory)
pytest -v --cov=app
```

---

## 🔧 Detailed Setup

### Salesforce Setup

#### 1. Scratch Org Creation & Configuration

The project uses a **scratch org definition file** (`config/stripe-scratch-def.json`) with Enterprise Edition features:

```bash
# Create scratch org with 7-day lifespan
sf org create scratch \
  --definition-file config/stripe-scratch-def.json \
  --alias stripe-dev \
  --no-prompt

# Verify org creation
sf org list

# Set as default for commands
sf config set target-org=stripe-dev
```

**Scratch Org Features Enabled**:
- `EnableSetPasswordInApi` - For integration user management
- `API` - For Bulk API support
- `Einstein1AIPlatform` - For future AI capabilities

#### 2. Deploy Metadata

```bash
# Deploy all custom objects, triggers, and Apex classes
sf project deploy start

# Deploy specific component type
sf project deploy start --metadata-dir force-app/main/default/classes

# Deploy with validation only (no activation)
sf project deploy start --dry-run

# Check deployment status
sf project deploy report
```

#### 3. Install Required Packages

**Nebula Logger** (recommended for comprehensive logging):

```bash
# Install via SFDX
sf package install --package 04t1D000000IZ3S --installation-type AllOrgsAllUsers --wait 10

# Then assign Nebula Logger permission set
sf org assign permset --name Nebula_Logger_Admin
```

#### 4. Configure Named Credentials

**Via CLI** (recommended):
```bash
# Create Named Credential for Stripe API
sf org execute -f scripts/apex/setup-named-credential.apex
```

**Via Salesforce UI** (if CLI script not available):
1. Open Setup → Named Credentials → New
2. Set these values:
   - **Label**: `Stripe_API_Credentials`
   - **URL**: `https://api.stripe.com/v1`
   - **Authentication**: Header Authentication
   - **Header Name**: `Authorization`
   - **Header Value**: `Bearer sk_test_XXXXXXXXXXXXXXXX` (your Stripe test API key)
   - **Scope**: Leave empty
   - **External Principal**: `Stripe`

#### 5. Create Integration User (for OAuth)

For middleware OAuth 2.0 authentication:

```bash
# Via Setup UI:
# 1. Setup → Users → New
# 2. Create user: "Stripe Middleware Integration"
# 3. Email: stripe-integration@company.sandbox
# 4. Assign "Stripe Integration User" permission set
```

#### 6. Create Connected App (for OAuth)

**In Sandbox/Scratch Org**:
1. Setup → Apps → App Manager
2. Click "New Connected App"
3. Configure:
   - **Connected App Name**: Stripe Middleware
   - **Callback URL**: `http://localhost:8000/auth/callback` (dev) or your Lambda URL (prod)
   - **OAuth Scopes**: Select `api` and `refresh_token`
4. Save and wait for activation
5. Click "Manage" and note the Consumer Key and Consumer Secret
6. Store credentials in AWS Secrets Manager (see Middleware Setup)

**Note**: Connected Apps don't work in scratch orgs by default. Use a **Trailhead Playground** or **Sandbox** for full OAuth testing.

### Stripe Setup

#### 1. Create Stripe Developer Account

- Go to [stripe.com](https://stripe.com)
- Sign up for developer account
- Access Stripe Dashboard in **Test Mode** (toggle in top-right)

#### 2. Generate API Keys

1. Navigate to Developers → API Keys
2. Copy **Publishable Key** (test mode): `pk_test_...`
3. Copy **Secret Key** (test mode): `sk_test_...`
4. Store Secret Key securely (AWS Secrets Manager recommended)

#### 3. Create Products & Prices

In Stripe Dashboard:

1. Products section → New Product:
   - **Product Name**: "Basic Plan"
   - **Description**: "Monthly subscription"

2. Add Price:
   - **Amount**: $29.99
   - **Billing Period**: Monthly
   - **Recurring**: Yes

3. Repeat for additional plans (Pro, Enterprise, etc.)

4. Note the **Price IDs** (price_xxxx) - these map to Pricing_Plan__c records

#### 4. Configure Webhook Endpoint

1. Developers → Webhooks
2. Click "+ Add Endpoint"
3. **Endpoint URL**: Your middleware URL
   - Development: `http://localhost:8000/webhook/stripe`
   - AWS Lambda: `https://your-api-id.lambda-url.region.on.aws/webhook/stripe`
4. **Events to send**:
   - `checkout.session.completed`
   - `customer.created`
   - `customer.updated`
   - `customer.deleted`
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `payment_intent.succeeded`
   - `payment_intent.payment_failed`
   - `invoice.created`
   - `invoice.payment_succeeded`
   - `invoice.payment_failed`
5. Copy **Webhook Signing Secret** (whsec_xxx)
6. Store in AWS Secrets Manager

### Middleware Setup

#### 1. Environment Configuration

Create `.env` file in `middleware/` directory:

```bash
cd middleware

# Copy example env file
cp .env.example .env

# Edit with your values
nano .env
```

**Required environment variables**:
```env
# Stripe Configuration
STRIPE_API_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...

# Salesforce Configuration
SALESFORCE_INSTANCE_URL=https://your-instance.salesforce.com
SALESFORCE_OAUTH_CLIENT_ID=your_connected_app_client_id
SALESFORCE_OAUTH_CLIENT_SECRET=your_connected_app_client_secret
SALESFORCE_OAUTH_USERNAME=stripe-integration@company.sandbox
SALESFORCE_OAUTH_PASSWORD=your_password
SALESFORCE_OAUTH_SECURITY_TOKEN=your_security_token

# AWS Configuration
AWS_REGION=us-east-1
AWS_SQS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/account-id/queue-name
DYNAMODB_TABLE_NAME=stripe-events

# Application Configuration
ENVIRONMENT=development
LOG_LEVEL=INFO
```

#### 2. Local Development (Docker)

```bash
cd middleware

# Build and run with Docker Compose
docker-compose up

# In another terminal, test the webhook endpoint
curl -X POST http://localhost:8000/webhook/stripe \
  -H "Content-Type: application/json" \
  -d '{"type": "customer.created", "id": "evt_test_123"}'

# Check health
curl http://localhost:8000/health
```

#### 3. AWS Deployment (SAM)

```bash
cd middleware

# Build SAM project
sam build

# Deploy (guided, first time)
sam deploy --guided

# Deploy (subsequent)
sam deploy

# View Lambda function logs
sam logs -n StripeWebhookFunction --stack-name stripe-middleware --tail
```

See [middleware/README.md](middleware/README.md) and [middleware/DEPLOYMENT_READY_STATUS.md](middleware/DEPLOYMENT_READY_STATUS.md) for detailed deployment instructions.

---

## 📁 Project Structure

```
salesforce-stripe-payment-processing-mtb/
├── README.md                              # This file
├── sfdx-project.json                      # SFDX project configuration
├── .forceignore                           # Files to exclude from deployments
│
├── config/
│   └── stripe-scratch-def.json           # Scratch org definition with features
│
├── force-app/
│   └── main/default/
│       ├── classes/                      # Apex classes (33 total)
│       │   ├── StripeAPIService.cls      # Main Stripe API wrapper
│       │   ├── StripeCustomerService.cls # Customer sync service
│       │   ├── StripeSubscriptionService.cls
│       │   ├── ContactTriggerHandler.cls
│       │   ├── ContactTriggerHelper.cls
│       │   ├── StripeInvoiceTriggerHandler.cls
│       │   ├── StripeInvoiceTriggerHelper.cls
│       │   ├── CustomerHealthScoreBatch.cls
│       │   ├── InvoiceCollectionBatch.cls
│       │   ├── RevenueRollupBatch.cls
│       │   ├── StripeAPIException.cls
│       │   ├── StripeAuthenticationException.cls
│       │   └── ... (and 20+ more)
│       │
│       ├── objects/                     # Custom objects
│       │   ├── Stripe_Customer__c/
│       │   ├── Stripe_Subscription__c/
│       │   ├── Stripe_Invoice__c/
│       │   ├── Payment_Transaction__c/
│       │   ├── Pricing_Plan__c/
│       │   ├── Pricing_Tier__c/
│       │   ├── Stripe_Price__mdt/      # Custom metadata type
│       │   └── Contact/               # Extended with Stripe fields
│       │
│       ├── triggers/                   # Apex triggers
│       │   ├── ContactTrigger.trigger
│       │   ├── StripeInvoiceTrigger.trigger
│       │   └── PricingPlanTrigger.trigger
│       │
│       ├── permissionsets/             # Permission sets
│       │   └── Stripe_Integration_User.permissionset-meta.xml
│       │
│       └── ... (other metadata)
│
├── middleware/                          # FastAPI middleware service
│   ├── README.md
│   ├── DEPLOYMENT_READY_STATUS.md
│   ├── IMPLEMENTATION_SUMMARY.md
│   ├── QUICKSTART.md
│   ├── requirements.txt                # Python dependencies
│   ├── Dockerfile                      # Docker containerization
│   ├── docker-compose.yml
│   ├── .env.example                    # Environment template
│   ├── samconfig.toml                  # SAM configuration
│   ├── template.yaml                   # SAM template (Lambda, API Gateway)
│   │
│   ├── app/
│   │   ├── main.py                    # FastAPI application entry point
│   │   ├── config.py                  # Configuration management
│   │   │
│   │   ├── routes/
│   │   │   ├── webhook.py             # POST /webhook/stripe endpoint
│   │   │   └── health.py              # GET /health endpoint
│   │   │
│   │   ├── services/
│   │   │   ├── stripe_service.py      # Stripe signature verification
│   │   │   ├── salesforce_service.py  # Salesforce REST API client
│   │   │   ├── salesforce_oauth.py    # OAuth token management
│   │   │   ├── sqs_service.py         # SQS queue operations
│   │   │   ├── dynamodb_service.py    # DynamoDB operations
│   │   │   └── rate_limiter.py        # Sliding window rate limiting
│   │   │
│   │   ├── handlers/
│   │   │   ├── event_router.py        # Route events to handlers
│   │   │   ├── customer_handler.py    # Handle customer events
│   │   │   ├── subscription_handler.py
│   │   │   └── payment_handler.py
│   │   │
│   │   ├── models/
│   │   │   ├── stripe_events.py       # Pydantic models
│   │   │   └── salesforce_records.py
│   │   │
│   │   └── utils/
│   │       ├── logging_config.py
│   │       └── exceptions.py
│   │
│   ├── tests/
│   │   ├── test_webhook.py
│   │   ├── test_handlers.py
│   │   └── test_salesforce_auth.py
│   │
│   ├── bulk_processor.py               # Bulk API processing for low-priority events
│   └── cloudwatch-dashboard.json       # CloudWatch monitoring dashboard
│
├── diagrams/                            # Architecture diagrams (PlantUML)
│   ├── dataModel.puml                 # Entity-relationship diagram
│   ├── middleware-architecture-final.puml
│   ├── onboarding.puml                # Customer onboarding flow
│   ├── ongoingPaymentManagement.puml  # Payment lifecycle flow
│   ├── stripeSalesforceSeq.puml       # Sequence diagrams
│   ├── webhook-flow.puml              # Webhook processing flow
│   └── images/                        # PNG exports of diagrams
│
├── requirements/                        # Project specification documents
│   ├── business.md                    # Business requirements & user stories
│   └── technical.md                   # Technical specification & data model
│
├── scripts/
│   ├── apex/
│   │   └── setup.apex                 # Apex setup scripts
│   └── data/
│       └── Contacts.json              # Sample test data
│
└── .github/
    └── workflows/                      # GitHub Actions CI/CD
```

---

## ✨ Features

### Salesforce → Stripe (Outbound Integration)

- **Customer Synchronization**: Contact creation automatically creates Stripe customer via trigger
- **Subscription Management**: Create Checkout sessions and store secure payment links
- **Multiple Pricing Plans**: Support for different subscription tiers via Custom Metadata
- **Error Handling**: Named Credentials with fallback authentication
- **Logging**: Nebula Logger integration for audit trails

### Stripe → Salesforce (Inbound Integration via Middleware)

**Webhook Event Processing** (9 critical events):
1. `checkout.session.completed` - Activate subscription after payment
2. `customer.subscription.created` - Create subscription record
3. `customer.subscription.updated` - Sync subscription changes
4. `customer.subscription.deleted` - Mark subscription as canceled
5. `payment_intent.succeeded` - Create successful transaction record
6. `payment_intent.payment_failed` - Log payment failure
7. `invoice.payment_succeeded` - Record recurring payment
8. `invoice.payment_failed` - Handle failed billing
9. `customer.updated` - Sync customer metadata (batched)

### Advanced Processing Capabilities

- **Priority-Based Processing**:
  - High-priority (real-time): Payment failures, subscription cancellations, checkout completions
  - Low-priority (batched): Customer metadata updates, sent via Bulk API

- **Rate Limiting**:
  - Sliding window algorithm (DynamoDB-based)
  - Respects Salesforce API governor limits
  - Dynamic throttling based on remaining quota

- **Retry Mechanisms**:
  - Exponential backoff: 2s, 4s, 8s, 16s, 32s
  - Max 5 retry attempts
  - Dead letter queue for permanent failures

- **Data Synchronization**:
  - Idempotency keys prevent duplicate processing
  - Timestamp-based conflict resolution (last-write-wins)
  - Event ordering and duplicate detection

### Revenue & Finance Features

- **Invoice Automation**: Trigger-based automation on invoice creation/updates
- **Revenue Rollups**: Aggregate invoice amounts to customer and subscription records
- **Health Scoring**: Calculate customer payment health (0-100 scale)
- **Churn Detection**: Flag customers with high payment failure rates
- **Dunning Escalation**: Progress payment retry status with escalation
- **Batch Jobs**: Daily overdue invoice identification, weekly health recalculation

---

## 💻 Technical Stack

### Salesforce (Force.com)

| Component | Technology | Version |
|-----------|-----------|---------|
| **Language** | Apex | Latest |
| **API Version** | Salesforce REST API | v63.0 |
| **Custom Objects** | 6 objects + 2 metadata types | - |
| **Logging** | Nebula Logger | Latest |
| **Authentication** | Named Credentials, OAuth 2.0 | - |
| **Triggers** | Bulk-safe trigger framework | - |
| **Async Processing** | Queueable classes, Batch Apex | - |

### Middleware (FastAPI)

| Component | Technology | Version |
|-----------|-----------|---------|
| **Framework** | FastAPI | 0.104+ |
| **Language** | Python | 3.9+ |
| **Server** | Uvicorn | 0.24+ |
| **HTTP Client** | httpx | 0.25+ |
| **Data Validation** | Pydantic | 2.0+ |
| **Testing** | pytest | 7.4+ |
| **Async** | asyncio | Built-in |

### AWS Services

| Service | Purpose |
|---------|---------|
| **Lambda** | Serverless webhook handler |
| **API Gateway** | HTTP endpoint for webhooks |
| **SQS** | Event buffering & async processing |
| **DynamoDB** | Token caching, rate limiting, temp storage |
| **Secrets Manager** | Credential storage & rotation |
| **CloudWatch** | Logging, metrics, monitoring, alarms |

### External Services

| Service | Purpose |
|---------|---------|
| **Stripe API** | Payment processing & subscriptions |
| **GitHub** | Version control & CI/CD |

---

## 🔄 Development Workflow

### Feature Development

#### 1. Create Feature Branch

```bash
# Create feature branch from develop
git checkout develop
git pull origin develop
git checkout -b feature/your-feature-name

# Example: Adding invoice automation
git checkout -b feature/invoice-automation
```

#### 2. Make Changes

**Salesforce Changes**:
```bash
# Create new Apex class/trigger
touch force-app/main/default/classes/YourNewClass.cls

# Deploy to scratch org
sf project deploy start

# Run tests
sf apex run test --target-org stripe-dev
```

**Middleware Changes**:
```bash
# Create new Python module
touch middleware/app/handlers/your_handler.py

# Run local tests
pytest middleware/tests/ -v

# Run locally to test
docker-compose up
```

#### 3. Code Quality & Testing

```bash
# Salesforce: Verify code coverage >= 75%
sf apex run test --code-coverage

# Middleware: Run tests with coverage
pytest --cov=app middleware/tests/

# Check code style
black middleware/app --check
flake8 middleware/app
```

#### 4. Commit & Push

```bash
# Stage and commit with descriptive message
git add .
git commit -m "feat: implement invoice automation with health scoring"

# Push to remote
git push origin feature/your-feature-name
```

#### 5. Create Pull Request

- Push branch to GitHub
- Open Pull Request to `develop` branch
- Request code reviews from team members
- Address feedback and iterate
- Squash commits if needed: `git rebase -i`
- Merge when approved

#### 6. Deploy to Integration Org

```bash
# After merge to develop, deploy to integration sandbox
sf org create scratch --alias stripe-integration
sf project deploy start --target-org stripe-integration

# Run full test suite
sf apex run test --target-org stripe-integration
```

### Branching Strategy

```
main (production-ready)
  ↑
  ├─ develop (integration branch)
  │   ├─ feature/customer-sync
  │   ├─ feature/invoice-automation
  │   ├─ feature/rate-limiting
  │   └─ bugfix/webhook-retry-logic
  │
  └─ hotfix/critical-fix (if needed)
```

---

## 🧪 Testing

### Salesforce (Apex)

#### Run All Tests
```bash
# Run all tests with code coverage
sf apex run test --target-org stripe-dev \
  --code-coverage \
  --result-format human

# Run specific test class
sf apex run test --class-names StripeAPIServiceTest --target-org stripe-dev

# Run tests matching pattern
sf apex run test --test-level RunLocalTests
```

#### Test Coverage Requirements
- **Minimum**: 75% coverage for all Apex classes
- **Target**: 90%+ for critical paths (API services, triggers)
- **Tools**: Salesforce CLI provides coverage metrics

#### Key Test Scenarios
- ✅ Happy path (successful operations)
- ✅ Error scenarios (network failures, invalid data)
- ✅ Edge cases (null values, empty collections)
- ✅ Concurrency (bulk operations, 200+ records)
- ✅ Rate limiting (throttling behavior)
- ✅ Idempotency (duplicate event processing)

### Middleware (Python)

#### Run Tests
```bash
cd middleware

# Run all tests
pytest -v

# Run with coverage report
pytest --cov=app --cov-report=html

# Run specific test file
pytest tests/test_webhook.py -v

# Run with markers
pytest -m "integration" -v

# Run in watch mode (requires pytest-watch)
ptw -- -v
```

#### Test Coverage
- **Target**: 80%+ code coverage
- **Generate HTML report**: `pytest --cov=app --cov-report=html`
- **View report**: Open `htmlcov/index.html`

#### Test Organization
```
middleware/tests/
├── __init__.py
├── conftest.py              # Pytest fixtures
├── test_webhook.py          # Webhook endpoint tests
├── test_handlers.py         # Event handler tests
├── test_salesforce_auth.py  # OAuth flow tests
├── test_rate_limiter.py     # Rate limiting tests
└── test_sqs_service.py      # SQS integration tests
```

### Integration Testing

#### End-to-End Test Flow
```bash
# 1. Start local middleware
cd middleware && docker-compose up &

# 2. Deploy Salesforce metadata
sf project deploy start --target-org stripe-dev

# 3. Create test contact (triggers customer sync)
# Via UI or SFDX: Create Contact → Verify Stripe_Customer record created

# 4. Send test webhook event
curl -X POST http://localhost:8000/webhook/stripe \
  -H "Content-Type: application/json" \
  -H "Stripe-Signature: t=..." \
  -d '{"type": "customer.subscription.created", "id": "evt_test_..."}'

# 5. Verify Stripe_Subscription record created in Salesforce

# 6. Check logs for successful processing
docker logs stripe-middleware
sf apex tail --target-org stripe-dev
```

---

## 🔒 Security

### Authentication & Authorization

#### Stripe API (Outbound)
- **Method**: Bearer token via Named Credentials
- **Storage**: Never hardcode API keys
- **Rotation**: Implement key rotation policy (90 days recommended)
- **Validation**: Verify token format before API calls

#### Webhook Verification
- **Method**: HMAC-SHA256 signature validation
- **Secret Storage**: AWS Secrets Manager (never in code)
- **Timestamp Validation**: Prevent replay attacks (5-minute window)
- **Verification**: Middleware validates every webhook

#### Salesforce OAuth 2.0 (Middleware)
- **Flow**: Client credentials (OAuth 2.0)
- **Token Cache**: DynamoDB with TTL
- **Scope**: Minimal required permissions (api, refresh_token)
- **Rotation**: Automatic refresh on expiration

### Secrets Management

#### AWS Secrets Manager
```bash
# Create secret
aws secretsmanager create-secret \
  --name stripe/api-key \
  --secret-string sk_test_...

# Update secret
aws secretsmanager update-secret \
  --secret-id stripe/api-key \
  --secret-string sk_test_...

# Rotate secret (implement automatic rotation)
aws secretsmanager rotate-secret \
  --secret-id stripe/api-key \
  --rotation-rules AutomaticallyAfterDays=90
```

#### Environment Variables (Development Only)
- Use `.env` file locally (never commit)
- Use `.env.example` template for documentation
- Use environment variables in CI/CD pipelines
- Never log or expose secrets

### Input Validation

#### Webhook Data Validation
- Validate Stripe event structure
- Check required fields exist
- Validate field types and formats
- Prevent null/empty critical data
- Sanitize before storing in Salesforce

#### API Request Validation
- Validate data types (Pydantic models)
- Check boundary conditions
- Prevent SOQL/SOSL injection
- Validate email, phone formats
- Limit request payload size

### Access Control

#### Salesforce Permission Sets
- Create "Stripe Integration User" permission set
- Grant minimum required permissions:
  - Create/Read/Update Stripe_* objects
  - Read Contact
  - Create Payment_Transaction records
  - Execute Queueable jobs
- Restrict direct Stripe API access (via Named Credentials only)

#### AWS IAM Policies
- Lambda execution role has minimal permissions
- SQS: Send/receive message only
- DynamoDB: Get/put items only
- Secrets Manager: GetSecretValue only
- CloudWatch: PutMetricData only
- S3: None (if not needed)

#### Network Security
- API Gateway: Enable API key validation
- VPC: Deploy Lambda in VPC (if needed for database access)
- Security Groups: Restrict to required ports/IPs
- HTTPS: Enforce for all endpoints

### Error Handling & Logging

#### Secure Error Messages
- **Never expose internal details** in error responses
- **Log full errors internally** for debugging
- **Return generic messages to clients**: "Payment processing failed"
- **Sanitize logs**: Remove credit card data, secrets, PII

#### Logging Standards
- **Salesforce**: Use Nebula Logger (structured logging)
- **Middleware**: JSON-formatted logs with correlation IDs
- **CloudWatch**: Set log retention (e.g., 30 days)
- **Log Levels**: DEBUG, INFO, WARNING, ERROR, CRITICAL

### Compliance & Audit

#### PCI Compliance
- ✅ No credit card data stored in Salesforce
- ✅ No credit card data in middleware
- ✅ All payment processing via Stripe Checkout
- ✅ HTTPS for all communications
- ✅ Secure credential storage

#### Audit Trails
- Track field history on key objects (Status, Amount, Subscription Status)
- Log all webhook processing (event ID, timestamp, result)
- Log all API errors with correlation IDs
- Monitor secret access patterns

---

## 🚀 Deployment

### Scratch Org Deployment

```bash
# Create new scratch org (if current one expired)
sf org create scratch --alias stripe-prod --set-default

# Deploy metadata
sf project deploy start

# Verify deployment
sf project deploy report

# Run validation-only deploy
sf project deploy start --dry-run
```

### Middleware Deployment (AWS Lambda + SAM)

#### Prerequisites
```bash
# Install AWS SAM CLI
brew install aws-sam-cli

# Configure AWS credentials
aws configure
```

#### Deployment Steps
```bash
cd middleware

# 1. Build SAM project
sam build

# 2. Deploy (first time - guided)
sam deploy --guided

# 3. Deploy (subsequent - automatic)
sam deploy

# 4. Retrieve output values
aws cloudformation describe-stacks \
  --stack-name stripe-middleware \
  --query 'Stacks[0].Outputs'

# 5. Store outputs (API endpoint, etc.)
# Update Stripe webhook endpoint URL with new API Gateway URL
# Update Salesforce Connected App callback URL

# 6. Verify deployment
curl https://your-lambda-url/health

# 7. Monitor logs
sam logs -n StripeWebhookFunction --tail
```

#### Post-Deployment

```bash
# Update Stripe Webhook Endpoint
# 1. Stripe Dashboard → Developers → Webhooks
# 2. Edit webhook endpoint
# 3. Set URL to: https://your-api-id.lambda-url.region.on.aws/webhook/stripe
# 4. Save

# Create DynamoDB Table (if not auto-created)
aws dynamodb create-table \
  --table-name stripe-events \
  --attribute-definitions AttributeName=event_id,AttributeType=S \
  --key-schema AttributeName=event_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# Create SQS Queue (if not auto-created)
aws sqs create-queue --queue-name stripe-webhook-events
```

### Monitoring Deployment

```bash
# Check Lambda invocations
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 3600 \
  --statistics Sum

# Check error rate
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --statistics Sum

# View recent logs
sam logs -n StripeWebhookFunction --tail
```

---

## 📊 Monitoring & Observability

### CloudWatch Dashboards

#### Create Custom Dashboard
```bash
# Deploy dashboard from template
aws cloudwatch put-dashboard \
  --dashboard-name stripe-integration \
  --dashboard-body file://middleware/cloudwatch-dashboard.json
```

#### Key Metrics to Monitor

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| **Webhook Success Rate** | > 99% | < 95% |
| **API Response Time (p95)** | < 5 seconds | > 10 seconds |
| **Error Rate** | < 1% | > 5% |
| **Queue Depth** | < 100 messages | > 1000 messages |
| **Token Refresh Rate** | < 10/hour | > 50/hour |
| **DynamoDB Throttling** | 0 events | > 0 events |

#### Health Checks

```bash
# Test middleware health endpoint
curl https://your-lambda-url/health

# Expected response
{
  "status": "healthy",
  "timestamp": "2024-01-01T12:00:00Z",
  "environment": "production"
}
```

### Salesforce Monitoring

#### Nebula Logger Setup
```apex
// View logs via Nebula Logger
LoggerSObjectHandler.publishLogs();

// Query recent errors
SELECT CreatedDate, LogMessage__c, ExceptionMessage__c
FROM Log__c
WHERE Level__c = 'Error'
ORDER BY CreatedDate DESC
LIMIT 10
```

#### Apex Tests & Code Coverage
```bash
# Run full test suite with coverage
sf apex run test --target-org stripe-dev --code-coverage

# Generate coverage report
sf apex run test --result-format json > test-results.json
```

### Alerting

#### CloudWatch Alarms
```bash
# Create alarm for high error rate
aws cloudwatch put-metric-alarm \
  --alarm-name stripe-webhook-errors \
  --alarm-description "Alert on webhook processing errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:region:account:topic
```

#### Salesforce Email Alerts
- Configure email alerts for failed Stripe_Subscription records
- Alert customer service when Payment_Transaction status = Failed
- Daily digest of sync failures for admin review

### Log Aggregation

#### CloudWatch Log Groups
```bash
# Create log group
aws logs create-log-group --log-group-name /aws/lambda/stripe-webhook

# Set retention policy (e.g., 30 days)
aws logs put-retention-policy \
  --log-group-name /aws/lambda/stripe-webhook \
  --retention-in-days 30
```

#### Log Query Examples
```
# Find webhook processing errors
fields @timestamp, @message, error_type
| filter error_type = "webhook_processing_error"
| stats count() by error_type

# Track latency
fields @duration
| stats avg(@duration), max(@duration), pct(@duration, 95)

# Find authorization failures
fields @message
| filter @message like /unauthorized|forbidden|auth_failed/
| stats count() by @message
```

---

## 🐛 Troubleshooting

### Common Issues

#### 1. **Stripe Customer Not Created**

**Symptoms**: Contact created in Salesforce but no Stripe_Customer__c record

**Diagnosis**:
```bash
# Check trigger logs
sf apex tail --target-org stripe-dev

# Check Nebula Logger
# Setup → Nebula Logger → Recent Logs
# Filter by ContactTriggerHandler
```

**Solutions**:
1. Verify Named Credentials exist and are correct
2. Check Stripe API key is valid (test mode)
3. Verify contact has required fields (Email, Name)
4. Check trigger is active: Setup → Triggers → ContactTrigger (Active)

#### 2. **Webhook Events Not Processed**

**Symptoms**: Stripe events sent but Salesforce not updating

**Diagnosis**:
```bash
# Check SQS queue has messages
aws sqs get-queue-attributes \
  --queue-url $QUEUE_URL \
  --attribute-names ApproximateNumberOfMessages

# Check Lambda execution logs
sam logs -n StripeWebhookFunction --tail

# Check DynamoDB for failed events
aws dynamodb scan --table-name stripe-events
```

**Solutions**:
1. Verify webhook endpoint URL is correct in Stripe dashboard
2. Check Stripe webhook signing secret in AWS Secrets Manager
3. Verify Salesforce OAuth credentials are valid
4. Check SQS queue permissions (Lambda can send messages)
5. Review DLQ for permanently failed events

#### 3. **OAuth Token Expiration Errors**

**Symptoms**: Middleware returns "Invalid token" errors after ~1 hour

**Diagnosis**:
```python
# Check token cache in DynamoDB
aws dynamodb get-item \
  --table-name stripe-events \
  --key '{"event_id": {"S": "oauth_token"}}'
```

**Solutions**:
1. Verify token refresh logic in `salesforce_oauth.py`
2. Check Salesforce Connected App has refresh_token scope
3. Verify credentials in AWS Secrets Manager are not expired
4. Check DynamoDB has sufficient write capacity

#### 4. **Rate Limiting / Throttling**

**Symptoms**: Some webhook events delayed or lost

**Diagnosis**:
```bash
# Check sliding window rate limiter metrics
aws cloudwatch get-metric-statistics \
  --namespace stripe-integration \
  --metric-name rate_limit_exceeded \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 60 \
  --statistics Sum

# Check DynamoDB capacity
aws dynamodb describe-table --table-name stripe-events
```

**Solutions**:
1. Increase SQS visibility timeout (if processing takes > 30 seconds)
2. Increase DynamoDB write capacity or switch to on-demand
3. Implement priority-based processing (high-priority REST API, low-priority Bulk API)
4. Monitor queue depth and scale Lambda concurrency

#### 5. **Test Data / Sandbox Issues**

**Symptoms**: Scratch org expires, data lost, need to refresh

**Solutions**:
```bash
# Delete current scratch org
sf org delete scratch --alias stripe-dev --no-prompt

# Create new scratch org
sf org create scratch --alias stripe-dev

# Deploy metadata
sf project deploy start

# Load sample data
sf data import tree --plan scripts/data/plan.json

# Verify setup
sf org open --target-org stripe-dev
```

### Debug Commands

```bash
# Tail Apex debug logs
sf apex tail --target-org stripe-dev

# Query Stripe_Customer records
sf data query --query "SELECT Id, Name, Stripe_Customer_ID__c FROM Stripe_Customer__c" \
  --target-org stripe-dev

# Check trigger execution status
sf project list metadata --metadata-type ApexTrigger --target-org stripe-dev

# Verify Named Credentials
sf org open --target-org stripe-dev
# Setup → Named Credentials → Verify listed

# Test middleware locally
docker-compose logs -f stripe-middleware
```

### Support & Escalation

1. **Check logs first**: Nebula Logger (Salesforce), CloudWatch (Middleware)
2. **Review error messages**: Usually indicate root cause
3. **Verify configuration**: Check all setup steps completed
4. **Test in isolation**:
   - Test Stripe API key directly: `curl -H "Authorization: Bearer sk_test_..." https://api.stripe.com/v1/customers`
   - Test middleware locally: `docker-compose up && curl http://localhost:8000/health`
5. **Review documentation**: [Stripe Docs](https://stripe.com/docs), [Salesforce Docs](https://developer.salesforce.com/docs)

---

## 👥 Team Collaboration

### Code Review Process

1. **Push feature branch** to GitHub
2. **Create pull request** with:
   - Clear description of changes
   - Link to relevant issues/requirements
   - Test results showing code coverage
3. **Request reviewers** from team
4. **Address feedback** with new commits
5. **Merge** when approved (squash if needed)

### Commit Message Standards

Follow conventional commits:
```
feat: implement invoice automation trigger
^--^  ^---^
|     |
|     +-- Summary in present tense
+-------- Type: feat, fix, docs, test, refactor, etc.

Optional body with more details...
Fixes #123
```

### Communication Channels

- **Slack**: Daily standups, quick questions
- **GitHub Issues**: Feature requests, bug tracking
- **Pull Requests**: Code review discussions
- **Meetings**: Weekly architecture review, bi-weekly demos

### Documentation Standards

- **Code Comments**: Explain "why", not "what"
- **Class Documentation**: JSDoc style for Apex, docstrings for Python
- **README**: Keep updated with setup changes
- **Architecture Docs**: PlantUML diagrams in `diagrams/` folder

### Key Team Roles

| Role | Responsibilities |
|------|-----------------|
| **Lead Developer** | Architecture decisions, code reviews, deployment |
| **Salesforce Dev** | Apex classes, triggers, data model |
| **Middleware Dev** | FastAPI services, AWS infrastructure |
| **QA Engineer** | Testing strategy, test cases, coverage |

---

## 📚 Additional Resources

### Documentation Files
- [Business Requirements](requirements/business.md) - User stories and business processes
- [Technical Specification](requirements/technical.md) - Complete technical requirements
- [Middleware README](middleware/README.md) - Detailed middleware setup
- [Deployment Guide](middleware/DEPLOYMENT_READY_STATUS.md) - Production deployment

### External Resources
- **Stripe Docs**: https://stripe.com/docs
- **Salesforce Developer Docs**: https://developer.salesforce.com/docs
- **AWS Documentation**: https://docs.aws.amazon.com
- **FastAPI Documentation**: https://fastapi.tiangolo.com
- **Salesforce Trailhead**: https://trailhead.salesforce.com

### Architecture Diagrams
All diagrams are in `diagrams/` folder:
- `dataModel.puml` - Custom object relationships
- `middleware-architecture-final.puml` - System architecture
- `onboarding.puml` - Customer onboarding flow
- `webhook-flow.puml` - Webhook processing flow

---

## 📝 License & Credits

This is an educational capstone project created for Cloud Code Academy.

**Team Members**: [Add your team members here]

**Project Duration**: 4 weeks (Week 1-4 completed)

**Last Updated**: November 2, 2024

---

## 🤝 Contributing

### Getting Help
- Check this README and linked documentation
- Review code comments and docstrings
- Ask team members in Slack
- Create GitHub issue for bugs or feature requests

### Making Improvements
1. Create issue describing improvement
2. Create feature branch
3. Make changes with tests
4. Open pull request
5. Request review from team
6. Merge when approved

---

## ✅ Quick Checklist for New Team Members

- [ ] Forked/cloned GitHub repository
- [ ] Installed Salesforce CLI (sf)
- [ ] Installed Python 3.9+ (for middleware)
- [ ] Authenticated with Dev Hub org
- [ ] Created scratch org (`sf org create scratch`)
- [ ] Deployed metadata (`sf project deploy start`)
- [ ] Installed Nebula Logger package
- [ ] Created Named Credential for Stripe
- [ ] Set up `.env` file for middleware (from `.env.example`)
- [ ] Ran Apex tests (`sf apex run test`)
- [ ] Ran middleware tests (`pytest`)
- [ ] Read business requirements document
- [ ] Read technical specification document
- [ ] Reviewed architecture diagrams in `diagrams/`
- [ ] Completed initial task assignment

---

**Ready to build? Start with the [Quick Start](#-quick-start) section above!**

Questions? Check [Troubleshooting](#-troubleshooting) or ask your team lead.
