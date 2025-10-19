# Salesforce-Stripe Payment Processing

This capstone project is a comprehensive payment processing solution that integrates Salesforce with Stripe to manage the complete customer payment lifecycle. Students will build a robust integration platform that demonstrates proficiency in REST APIs, authentication, asynchronous processing, error handling, and middleware development. The system will handle customer onboarding, subscription management, payment processing, and financial reporting - all synchronized between Salesforce and Stripe through a FastAPI middleware layer.

**Guiding Principle:** Build a production-ready integration that could be deployed in a real business environment for managing customer payments and subscriptions.

## Project Scope & Team Structure

- **Duration:** 4 weeks
- **Team Size:** 3 members maximum
- **Development Model:** Scratch org-based development with individual scratch orgs per team member
- **Collaboration:** Required through Slack, virtual meetings, and code reviews
- **Repository:** All metadata must be stored and versioned in GitHub
- **Scratch Org Management:** Each team member creates and manages their own scratch orgs from shared source

## Technical Architecture Focus

This project emphasizes real-world integration patterns including:

- **Outbound Integrations:** Salesforce → Stripe (customer creation, subscription management)
- **Inbound Integrations:** Stripe → Salesforce (webhooks for payment events via middleware)
- **Middleware Architecture:** FastAPI-based webhook handler with event queuing and processing
- **Authentication:** Multiple auth patterns (API keys for Stripe, OAuth 2.0 for Salesforce)
- **Asynchronous Processing:** Queueable classes for bulk operations, SQS for event queuing
- **Error Handling:** Comprehensive logging and retry mechanisms with exponential backoff
- **Rate Limiting:** Sliding window algorithm for Salesforce API rate limiting
- **Cloud Infrastructure:** AWS services (Lambda/ECS, SQS, Redis) for middleware deployment

---

## Weekly Planning Guide

### Week 1: Foundation & Setup

**Scratch Org Configuration:**
- GitHub repository configuration and scratch org definition file (`config/stripe-scratch-def.json`)
- Create and configure scratch orgs for each team member
- Core object design and field definitions
- Permission sets and security model setup
- Named Credentials configuration for Stripe API

**Stripe Setup:**
- Stripe developer account creation
- API key generation (test mode)
- Product and price configuration in Stripe dashboard
- Webhook endpoint exploration and documentation review

**Initial Outbound Integration:**
- Apex class for Stripe customer creation
- Contact trigger for automatic customer sync
- Basic error handling and logging framework
- Unit tests for customer synchronization

**Deliverables:**
- Scratch org definition file with all configurations
- Working scratch orgs with custom objects deployed
- Stripe developer account configured
- Contact → Stripe Customer sync functional
- GitHub repository with initial code and metadata

---

### Week 2: Core Integration & Middleware Setup

**Subscription Management (Salesforce → Stripe):**
- Apex methods to create Stripe Checkout sessions
- Subscription record creation with checkout tracking
- Support for multiple subscription plans using Pricing Plans custom object
- Queueable implementation for bulk subscription operations
- Test coverage for subscription flows

**Middleware Infrastructure Setup:**
- **FastAPI Framework Setup:**
  - Initialize FastAPI project structure
  - Create webhook endpoint (`/webhook/stripe`)
  - Implement Stripe webhook signature verification (HMAC-SHA256)
  - Basic health check and monitoring endpoints

- **AWS Infrastructure Configuration:**
  - SQS queue creation for event buffering
  - Redis setup for temporary storage and token caching
  - Lambda deployment OR ECS container deployment
  - IAM roles and security policies

- **Salesforce Connected App & OAuth:**
  - Create Connected App in Salesforce for middleware authentication
  - Configure OAuth 2.0 client credentials flow
  - Generate client ID and client secret
  - Test OAuth token acquisition from middleware

- **Middleware-to-Salesforce Integration:**
  - Implement OAuth token management (acquisition, refresh, caching)
  - Create Salesforce REST API client wrapper
  - Test basic CRUD operations from middleware to Salesforce
  - Environment variable configuration for secrets

**Secret Management:**
- AWS Secrets Manager setup for storing:
  - Stripe API keys
  - Stripe webhook signing secret
  - Salesforce OAuth credentials (client ID, client secret)
- Secure secret injection into middleware runtime

**Error Logging Framework:**
- Nebula Logger setup in Salesforce
- Middleware logging configuration (structured logging)
- Error categorization (network, business logic, data)
- Initial monitoring dashboard setup

**Deliverables:**
- Stripe Checkout session creation working
- FastAPI middleware deployed and accessible
- Webhook endpoint receiving and verifying Stripe events
- OAuth authentication between middleware and Salesforce functional
- SQS queue processing events
- Basic test coverage for new features

---

### Week 3: Advanced Features & Complete Event Processing

**Webhook Event Handling:**
- **Event Type Implementation:**
  - `customer.updated` - Sync customer data changes to Salesforce
  - `checkout.session.completed` - Update subscription status to active
  - `payment_intent.succeeded` - Create payment transaction records
  - `payment_intent.failed` - Log failed payments and trigger alerts
  - `customer.subscription.updated` - Sync subscription status changes
  - `customer.subscription.deleted` - Handle subscription cancellations

- **Event Processing Architecture:**
  - Event router based on Stripe event type
  - Strategy pattern for handling different event types
  - Idempotency keys to prevent duplicate processing
  - Event ordering and duplicate detection

**Asynchronous Processing:**
- **Salesforce Queueable Classes:**
  - Process webhook events asynchronously
  - Queueable chaining for complex workflows
  - Bulk API usage for large data synchronization

- **Middleware Processing:**
  - SQS queue consumer for event processing
  - Real-time vs. bulk processing decision logic
  - Batch aggregation for non-urgent events

**Data Synchronization & Conflict Resolution:**
- Timestamp-based conflict resolution
- Delta sync to minimize API calls for low-priority data
- Pagination handling for large datasets
- Audit trail for all synchronization activities

**Rate Limiting & Throttling:**
- **Sliding Window Rate Limiter:** Redis-based sliding window algorithm to track API calls per time window
- **Exponential Backoff:** For both inbound (Salesforce API) and outbound (Stripe API) retries
- **Request Throttling:** Queue-based throttling to stay within Salesforce governor limits
- **Priority-Based Processing:**
  - High-priority events: Processed in real-time via Salesforce REST API
  - Low-priority events: Batched in Redis and sent via Salesforce Bulk API
- Queue depth monitoring and alerting
- Circuit breaker pattern for failing endpoints

**Testing:**
- Integration tests with HTTP mock responses
- HttpCalloutMockFactory pattern implementation
- Middleware unit tests for event handlers
- End-to-end testing of complete flows

**Deliverables:**
- All critical webhook events processed successfully
- Complete bidirectional data synchronization
- Comprehensive error handling and retry logic
- Conflict resolution mechanisms working
- 50%+ code coverage achieved

---

### Week 4: Polish & Production Readiness

**Comprehensive Testing:**
- Achieve 75%+ code coverage in Salesforce
- Unit tests for all Apex classes
- Integration tests for complete workflows
- Middleware test suite with pytest
- Test data factory for consistent test setup
- Performance testing and optimization

**Security Hardening:**
- **Secret Management Audit:**
  - Verify no hardcoded credentials
  - Confirm secret rotation policies
  - Review IAM policies for least privilege
  - Enable audit logging for secret access

- **Input Validation:**
  - Sanitize all incoming webhook data
  - Validate data types and required fields
  - Prevent injection attacks

- **Access Control:**
  - Review Salesforce permission sets
  - Validate OAuth scopes are minimal
  - Ensure integration user has appropriate permissions

**Performance Optimization:**
- SOQL query optimization and bulkification
- Middleware response time optimization
- Redis caching strategy refinement
- Database query optimization
- Governor limit optimization review

**Monitoring & Observability:**

- **Middleware Monitoring:**
  - Coralogix metrics and alarms
  - Error rate tracking
  - Latency monitoring
  - Queue depth alerts
  - Sliding window rate limit tracking

**Documentation:**
- **Technical Documentation:**
  - README with setup instructions
  - Architecture diagrams (data flow, component diagram)
  - API documentation for custom endpoints

- **Developer Documentation:**
  - Code comments and inline documentation
  - Deployment procedures
  - Environment configuration guide
  - Testing procedures

**Final Review:**
- Code review and refactoring
- Security audit
- Performance profiling
- Documentation review
- Demo environment preparation

**Presentation Preparation:**
- Create demo script with user stories
- Prepare architecture slides
- Document technical decisions and tradeoffs
- Practice live demonstration
- Prepare Q&A responses

**Deliverables:**
- 75%+ code coverage with passing tests
- Complete documentation package
- Deployed and monitored production-ready integration
- Presentation materials
- Demo environment

---

## Core Requirements

### 1. Customer & Payment Data Model

**Custom Objects Implemented:**

#### Stripe Customer (`Stripe_Customer__c`)
- **Name:** Auto-Number (SC-{000000}) - Stripe Customer Number
- **Stripe Customer ID** (`Stripe_Customer_ID__c`) - Text (External ID, Unique) - Maps to Stripe customer ID
- **Customer Email** (`Customer_Email__c`) - Email
- **Customer Name** (`Customer_Name__c`) - Text
- **Customer Phone** (`Customer_Phone__c`) - Phone
- **Default Payment Method** (`Default_Payment_Method__c`) - Text
- **Subscription Status** (`Subscription_Status__c`) - Picklist (None, Active, Past Due, Canceled)
- **Contact** (`Contact__c`) - Lookup to Contact object
- **Object Settings:**
  - Track field history enabled
  - Reports and dashboards enabled
  - Sharing: ReadWrite

#### Stripe Subscription (`Stripe_Subscription__c`)
- **Name:** Auto-Number (SUB-{000000}) - Subscription Number
- **Stripe Subscription ID** (`Stripe_Subscription_ID__c`) - Text (External ID, Unique)
- **Stripe Customer** (`Stripe_Customer__c`) - Lookup to Stripe_Customer__c
- **Product/Plan Name** (`Product_Plan_Name__c`) - Text
- **Stripe Price ID** (`Stripe_Price_ID__c`) - Text (references Stripe Price API ID)
- **Status** (`Status__c`) - Picklist with field history tracking:
  - active
  - canceled
  - incomplete
  - incomplete_expired
  - past_due
  - trialing
  - unpaid
- **Current Period Start** (`Current_Period_Start__c`) - DateTime
- **Current Period End** (`Current_Period_End__c`) - DateTime
- **Amount** (`Amount__c`) - Currency
- **Currency** (`Currency__c`) - Text (3 characters, e.g., USD, EUR)
- **Stripe Checkout Session ID** (`Stripe_Checkout_Session_ID__c`) - Text
- **Checkout URL** (`Checkout_URL__c`) - URL
- **Sync Status** (`Sync_Status__c`) - Picklist (Pending, Checkout Created, Completed, Failed)
- **Error Message** (`Error_Message__c`) - Long Text Area
- **Object Settings:**
  - Track field history enabled
  - Reports and dashboards enabled
  - Sharing: ReadWrite

#### Payment Transaction (`Payment_Transaction__c`)
- **Name:** Auto-Number (PMT-{000000}) - Payment Transaction Number
- **Stripe Payment Intent ID** (`Stripe_Payment_Intent_ID__c`) - Text (External ID, Unique)
- **Stripe Customer** (`Stripe_Customer__c`) - Lookup to Stripe_Customer__c
- **Amount** (`Amount__c`) - Currency
- **Currency** (`Currency__c`) - Text (3 characters)
- **Status** (`Status__c`) - Picklist with field history tracking:
  - requires_payment_method
  - requires_confirmation
  - requires_action
  - processing
  - requires_capture
  - canceled
  - succeeded
- **Payment Method Type** (`Payment_Method_Type__c`) - Text
- **Transaction Date** (`Transaction_Date__c`) - DateTime
- **Stripe Subscription** (`Stripe_Subscription__c`) - Lookup to Stripe_Subscription__c
- **Object Settings:**
  - Track field history enabled
  - Reports and dashboards enabled
  - Sharing: ReadWrite

#### Pricing Plan (`Pricing_Plan__c`)
- **Name:** Text - Pricing Plans Name
- **Stripe Subscription** (`Stripe_Subscription__c`) - Lookup to Stripe_Subscription__c
- **Stripe Price ID** (`Stripe_Price_ID__c`) - Text (references Stripe Price API ID)
- **Amount** (`Amount__c`) - Currency
- **Currency** (`Currency__c`) - Text (3 characters)
- **Recurrency Type** (`Recurrency_Type__c`) - Picklist (uses global value set "Recurrency_Type")
  - Examples: Monthly, Yearly, One-time
- **Description:** Subscription pricing plan
- **Object Settings:**
  - Reports and search disabled
  - Sharing: ReadWrite

#### Pricing Tier (`Pricing_Tier__c`)
- **Name:** Text - Pricing Tier Name
- **Pricing Plan** (`Pricing_Plan__c`) - Master-Detail to Pricing_Plan__c
- **Tier Number** (`Tier_Number__c`) - Number (for ordering tiers)
- **From Quantity** (`From_Quantity__c`) - Number (lower bound of quantity range)
- **To Quantity** (`To_Quantity__c`) - Number (upper bound of quantity range)
- **Unit Price** (`Unit_Price__c`) - Currency (price per unit in this tier)
- **Discount** (`Discount__c`) - Percent or Currency (discount applied to this tier)
- **Object Settings:**
  - Reports and search disabled
  - Sharing: ControlledByParent (inherits from Pricing Plan)
  - Master-Detail relationship enables volume/tiered pricing

**Standard Object Extensions:**
- **Contact:**
  - **Stripe Customer ID** (`Stripe_Customer_ID__c`) - Text (External ID) - Links Contact to Stripe customer

**Data Model Relationships:**
```
Contact (1) ----< (M) Stripe_Customer__c
Stripe_Customer__c (1) ----< (M) Stripe_Subscription__c
Stripe_Customer__c (1) ----< (M) Payment_Transaction__c
Stripe_Subscription__c (1) ----< (M) Payment_Transaction__c
Stripe_Subscription__c (1) ----< (M) Pricing_Plan__c
Pricing_Plan__c (1) ----< (M) Pricing_Tier__c (Master-Detail)
```

**Key Design Patterns:**
- **External IDs:** All Stripe objects use External ID fields for upsert operations from middleware
- **Field History Tracking:** Critical status fields track changes for audit trails
- **Auto-Numbers:** Provide user-friendly record identifiers (SC-000001, SUB-000001, PMT-000001)
- **Master-Detail for Pricing Tiers:** Enables tiered/volume pricing models with roll-up summaries

---

### 2. Outbound Integration: Salesforce → Stripe

**Customer Synchronization:**
- Trigger-based automation to create Stripe customers when Contacts are created
- Named Credentials for secure API authentication to Stripe
- Wrapper classes for Stripe API requests/responses (JSON serialization/deserialization)
- Custom exceptions for Stripe API errors
- Comprehensive logging with Nebula Logger
- Idempotency key generation for safe retries

**Subscription Management:**
- Apex service class for subscription operations
- Create Stripe Checkout sessions for subscription signup
- Support for multiple subscription plans via Custom Metadata Types
- Prorated billing calculations (for upgrades/downgrades)
- Queueable implementation for bulk subscription operations
- Generate and store checkout URLs for customer payment completion

**Key Classes:**
- `StripeAPIService.cls` - Main service class for Stripe API calls
- `StripeCustomerService.cls` - Customer-specific operations
- `StripeSubscriptionService.cls` - Subscription management
- `StripeCalloutMock.cls` - Test mock for HTTP callouts
- `ContactTrigger.trigger` - Contact automation trigger
- `ContactTriggerHandler.cls` - Trigger handler with proper bulkification

---

### 3. Inbound Integration: Stripe → Salesforce (Middleware)

**Middleware Architecture (FastAPI + AWS):**

The middleware acts as an intermediary between Stripe webhooks and Salesforce, providing:
- Event buffering and rate limiting
- Signature verification and security
- Event transformation and routing
- Resilient error handling and retry logic

**Component Stack:**
- **Web Framework:** FastAPI (Python)
- **Event Queue:** AWS SQS for event buffering
- **Caching Layer:** Redis for token caching and temporary storage
- **Deployment:** AWS Lambda (serverless) OR AWS ECS (containerized)
- **Secrets Management:** AWS Secrets Manager
- **Monitoring:** Coralogix

**Webhook Endpoint Implementation:**

```
POST /webhook/stripe
- Verify Stripe signature using webhook signing secret
- Parse Stripe event payload
- Push event to SQS queue
- Return 200 OK immediately (within Stripe's timeout)
```

**Event Processing Flow:**

1. Stripe sends webhook → Middleware FastAPI endpoint
2. Middleware verifies signature (HMAC-SHA256)
3. Event pushed to SQS queue (return 200 to Stripe)
4. SQS consumer processes event asynchronously
5. Event router determines event type and handler
6. Middleware authenticates with Salesforce via OAuth
7. Middleware calls Salesforce REST API to update records
8. Success/failure logged and monitored

**Critical Stripe Events to Handle:**

| Event Type | Purpose | Salesforce Action |
|------------|---------|-------------------|
| `customer.updated` | Customer data changed in Stripe | Update Stripe_Customer__c record |
| `checkout.session.completed` | Customer completed payment | Update Subscription sync status to Completed |
| `customer.subscription.created` | New subscription created | Create/update Stripe_Subscription__c |
| `customer.subscription.updated` | Subscription modified | Update Stripe_Subscription__c status |
| `customer.subscription.deleted` | Subscription canceled | Update status to Canceled |
| `payment_intent.succeeded` | Payment successful | Create Payment_Transaction__c record |
| `payment_intent.payment_failed` | Payment failed | Create failed transaction record, log error |
| `invoice.payment_succeeded` | Recurring payment succeeded | Update subscription, create transaction |
| `invoice.payment_failed` | Recurring payment failed | Log failure, trigger dunning process |

**Salesforce Integration (from Middleware):**

- **OAuth 2.0 Authentication:**
  - Use Connected App with client credentials flow
  - Cache access tokens in Redis (respect expiration)
  - Automatic token refresh on expiration
  - Dedicated integration user in Salesforce

- **REST API Operations:**
  - Create/Update records using Salesforce REST API
  - Use external ID fields for upsert operations
  - Batch operations for efficiency
  - Error handling and retry logic

**Event Processing Patterns:**

- **Idempotency:** Use Stripe event ID to prevent duplicate processing
- **Ordering:** Handle events in chronological order when necessary
- **Conflict Resolution:** Timestamp-based last-write-wins strategy
- **Priority-Based Processing:**
  - **High-Priority:** Real-time critical events (payment failures, subscription cancellations) → Immediate REST API calls
  - **Low-Priority:** Non-urgent events (customer updates, metadata changes) → Batched in Redis → Bulk API
- **Retry Logic:** Exponential backoff (without jitter) with max retry attempts for both inbound and outbound calls
- **Sliding Window Rate Limiting:** Redis-based sliding window to track and limit Salesforce API calls within time windows

**Error Handling:**

- Log all errors with structured logging (JSON format)
- Dead letter queue for failed events after max retries
- Alert on critical failures (PagerDuty, SNS)
- Store error details in Salesforce for troubleshooting

---

### 4. Authentication & Security

**Multiple Auth Patterns:**

#### Stripe API Authentication
- API Key authentication (Bearer token)
- Separate keys for test and live modes
- Stored securely in AWS Secrets Manager
- Never logged or exposed in error messages

#### Webhook Signature Verification
- HMAC-SHA256 signature verification
- Webhook signing secret from Stripe dashboard
- Prevent unauthorized webhook submissions
- Timestamp validation to prevent replay attacks

#### Salesforce OAuth 2.0
- **Connected App Configuration:**
  - Create Connected App in Salesforce
  - Configure OAuth scopes (api, refresh_token)
  - Generate client ID and client secret
  - Enable OAuth settings

- **Client Credentials Flow:**
  - Middleware authenticates as integration user
  - Token endpoint: `https://[instance].salesforce.com/services/oauth2/token`
  - Store tokens securely in Redis with TTL
  - Automatic refresh on expiration

**Security Implementation:**

- **Secret Management:**
  - AWS Secrets Manager for all credentials
  - Environment variables for non-sensitive config
  - IAM policies for least privilege access
  - Secret rotation policies (90 days)
  - Audit logging for secret access

- **Input Validation:**
  - Sanitize all incoming webhook data
  - Validate required fields before processing
  - Type checking and boundary validation
  - Prevent SOQL/SOSL injection

- **Rate Limiting:**
  - Sliding window algorithm (Redis-based) to track API calls per time window
  - Respect Salesforce API limits (governor limits)
  - Exponential backoff (without jitter) for retries
  - Priority queue for high vs. low priority events
  - Queue depth monitoring
  - Circuit breaker for failing endpoints

- **Access Control:**
  - Salesforce permission sets for integration user
  - Minimal OAuth scopes
  - Network security groups (AWS)
  - API Gateway throttling (if applicable)

- **Secure Error Messaging:**
  - Never expose sensitive data in error messages
  - Sanitize stack traces
  - Separate internal vs. external error messages

**Custom Metadata Types:**
- `Stripe_Price__mdt` - Manage subscription plans and pricing
- `Integration_Config__mdt` - Store non-sensitive configuration

---

### 5. Advanced Features

**Priority-Based Processing with Redis + Bulk API:**
- **High-Priority Events:** Processed in real-time via Salesforce REST API
  - Payment failures (`payment_intent.payment_failed`)
  - Subscription cancellations (`customer.subscription.deleted`)
  - Checkout completions (`checkout.session.completed`)
- **Low-Priority Events:** Batched in Redis and sent via Salesforce Bulk API
  - Customer metadata updates (`customer.updated`)
  - Non-critical subscription updates
- **No Scheduled Reconciliation Needed:** Real-time + bulk processing ensures continuous data sync without daily batch jobs

**Retry Mechanisms (Exponential Backoff without Jitter):**
- **Outbound Retries (Salesforce → Stripe):**
  - Max 5 retry attempts
  - Exponential backoff: 2s, 4s, 8s, 16s, 32s
  - Log failures after exhaustion
- **Inbound Retries (Middleware → Salesforce):**
  - Max 5 retry attempts
  - Exponential backoff: 2s, 4s, 8s, 16s, 32s
  - Dead letter queue for permanent failures

**Sliding Window Rate Limiting:**
- Redis-based sliding window algorithm
- Track API calls per minute/hour window
- Prevent exceeding Salesforce API limits
- Dynamic throttling based on remaining quota
- Real-time monitoring of API usage

**Data Synchronization:**
- Conflict resolution for concurrent updates (timestamp-based last-write-wins)
- Pagination handling for large datasets (Stripe cursors, Salesforce offset)
- Audit trail for all synchronization activities
- Idempotency keys for safe retries

**Queueable Chaining:**
- Chain Queueable jobs for complex workflows
- Handle bulk webhook processing asynchronously
- Stay within governor limits with proper bulkification

---

### 6. Error Handling & Monitoring

**Comprehensive Logging:**

**Salesforce (Nebula Logger):**
- Log all integration events (info, warn, error)
- Capture request/response payloads (sanitized)
- Error categorization:
  - Network errors (timeout, connection failure)
  - Business logic errors (validation, data mismatch)
  - Data errors (missing required fields, type mismatch)
- Retry attempt tracking
- Performance metrics (execution time)

**Middleware (Structured Logging):**
- JSON-formatted logs for parsing
- Correlation IDs for request tracing
- Log levels (DEBUG, INFO, WARNING, ERROR, CRITICAL)
- Coralogix integration for centralized logging
- Log retention policies

**Monitoring Dashboard:**

**Salesforce Metrics:**
- Integration health status (green/yellow/red)
- API usage tracking (calls per hour/day)
- Failed transaction count and details
- Sync lag (time between Stripe event and Salesforce update)
- Error rate by category

**Middleware Metrics (Coralogix):**
- Request count and success rate
- Response time (p50, p95, p99)
- Error rate by endpoint and event type
- Queue depth and age
- OAuth token refresh rate
- Memory and CPU utilization
- Sliding window API call tracking

**Alerting:**
- Critical failures (page immediately)
- High error rate (> 5%)
- Queue depth warnings (> 1000 messages)
- API limit approaching (> 80%)
- Sync lag exceeding threshold (> 5 minutes)

---

## Project Structure

### SFDX Project Structure

```
sfdx-project.json               # SFDX project configuration
.forceignore                    # Files to ignore in deployments
config/
└── stripe-scratch-def.json    # Scratch org definition with features and settings
scripts/
├── apex/
│   └── setup.apex              # Apex scripts for org setup
└── data/
    ├── Contacts.json           # Sample contact data
    └── plan.json               # Data import/export plan
```

**Key Scratch Org Features to Enable:**
- `EnableSetPasswordInApi` - For user management
- `API` - For Bulk API support
- Custom settings for org shape and edition (Developer or Enterprise)

### Middleware Structure (FastAPI)

```
middleware/
├── app/
│   ├── __init__.py
│   ├── main.py                    # FastAPI application entry point
│   ├── config.py                  # Configuration and environment variables
│   ├── routes/
│   │   ├── __init__.py
│   │   ├── webhook.py             # Stripe webhook endpoint
│   │   └── health.py              # Health check endpoints
│   ├── services/
│   │   ├── __init__.py
│   │   ├── stripe_service.py      # Stripe signature verification
│   │   ├── salesforce_service.py  # Salesforce API client
│   │   ├── sqs_service.py         # SQS queue operations
│   │   ├── redis_service.py       # Redis cache operations
│   │   └── rate_limiter.py        # Sliding window rate limiter
│   ├── handlers/
│   │   ├── __init__.py
│   │   ├── event_router.py        # Route events to handlers
│   │   ├── customer_handler.py    # Handle customer events
│   │   ├── subscription_handler.py # Handle subscription events
│   │   └── payment_handler.py     # Handle payment events
│   ├── auth/
│   │   ├── __init__.py
│   │   └── salesforce_oauth.py    # OAuth token management
│   ├── models/
│   │   ├── __init__.py
│   │   ├── stripe_events.py       # Pydantic models for Stripe events
│   │   └── salesforce_records.py  # Salesforce record models
│   └── utils/
│       ├── __init__.py
│       ├── logging_config.py      # Logging configuration
│       └── exceptions.py          # Custom exceptions
├── tests/
│   ├── __init__.py
│   ├── test_webhook.py
│   ├── test_handlers.py
│   └── test_salesforce_auth.py
├── requirements.txt
├── Dockerfile
├── docker-compose.yml
├── .env.example
└── README.md
```

---

## Technical Requirements

### Development Environment

**Scratch Org Development Model:**
- **Salesforce CLI:** Primary tool for scratch org creation and management (`sf` commands)
- **SFDX Project:** Source-driven development with `sfdx-project.json` configuration
- **Scratch Org Lifecycle:** 7-30 day lifespan, recreate as needed from source
- **Version Control:** All metadata in GitHub, scratch orgs created from source
- **Dev Hub:** Required for scratch org creation (enable in production or Developer Edition org)

### Recommended Tools

**Salesforce:**
- **Nebula Logger:** Use Nebula Logger for comprehensive logging throughout the integration. This provides superior debugging capabilities, log retention, and monitoring features compared to System.debug().

**Middleware:**
- **FastAPI:** Modern Python web framework with automatic API documentation
- **Pydantic:** Data validation using Python type hints
- **httpx:** Async HTTP client for API calls
- **boto3:** AWS SDK for Python (SQS, Secrets Manager)
- **redis-py:** Redis client for caching
- **pytest:** Testing framework

**Infrastructure:**
- **AWS Services:** Lambda/ECS, SQS, Redis (ElastiCache), Secrets Manager
- **Monitoring:** Coralogix for centralized logging and metrics
- **Docker:** Containerization for consistent deployment
- **Terraform (Optional):** Infrastructure as code

---

### Testing & Quality Assurance

**Salesforce Testing:**
- 75% code coverage minimum for all Apex classes
- Unit tests for positive and negative scenarios
- Integration tests with HTTP mock responses (HttpCalloutMock)
- Test data factory for consistent test setup
- **Recommended:** Use HttpCalloutMockFactory pattern for managing multiple API responses in tests
- Bulkified trigger testing (test with 200 records)
- Exception handling test scenarios

**Middleware Testing:**
- Unit tests for all service classes and handlers (pytest)
- Integration tests with mock Stripe webhooks
- Salesforce API mock responses
- OAuth flow testing
- End-to-end tests for critical flows
- Load testing for webhook endpoint
- 80%+ code coverage target

**Test Scenarios:**
- Successful webhook processing
- Invalid signature rejection
- Network failures and retries
- Token expiration and refresh
- Concurrent event processing
- Idempotency verification
- Rate limiting behavior

---

### Documentation

**Required Documentation:**

1. **README.md**
   - Project overview and objectives
   - Prerequisites and dependencies
   - Setup instructions:
     - Salesforce CLI installation and authentication
     - Scratch org creation and setup (`sf org create scratch`)
     - Metadata deployment (`sf project deploy start`)
     - Data import (`sf data import tree`)
     - Middleware deployment
   - Configuration guide
   - Running tests
   - Scratch org refresh/recreation instructions

2. **Architecture Documentation**
   - System architecture diagram (data flow)
   - Component diagram (Salesforce, middleware, Stripe)
   - Sequence diagrams for key flows
   - Technology stack and rationale

3. **API Documentation**
   - Stripe API endpoints used
   - Salesforce REST API operations
   - Middleware webhook endpoint specification
   - Authentication flows

4. **Deployment Guide**
   - Scratch org creation and configuration steps
   - Metadata deployment workflows
   - AWS infrastructure setup
   - Secrets configuration
   - Monitoring setup

5. **Troubleshooting Guide**
   - Common issues and solutions
   - Error codes and meanings
   - Debugging procedures
   - Support contacts

6. **Operations Runbook**
   - Monitoring checklist
   - Alert response procedures
   - Secret rotation procedures
   - Disaster recovery plan

---

### Performance & Scalability

**Salesforce Optimization:**
- Governor limit optimization
  - Bulkify all triggers and classes
  - Minimize SOQL queries (use maps and collections)
  - Use selective queries with indexed fields
  - Avoid DML inside loops
- Asynchronous processing for bulk operations (@future, Queueable, Batch)
- Efficient SOQL query patterns
- Caching strategies for frequently accessed data (Platform Cache)

**Middleware Optimization:**
- Async request handling (FastAPI async/await)
- Connection pooling for database and Redis
- Token caching to minimize OAuth calls
- Batch processing for non-urgent events
- Horizontal scaling (multiple Lambda instances or ECS tasks)
- SQS visibility timeout tuning

**Scalability Targets:**
- Handle 100+ webhook events per minute
- Process webhook within 5 seconds (p95)
- Support 1000+ active subscriptions
- Maintain < 1% error rate

---

## Deliverables

### Week 5 - Final Review

1. **GitHub Repository:**
   - Complete codebase with proper branching strategy (main, develop, feature branches)
   - Meaningful commit messages following conventional commits
   - Pull request history with code reviews
   - README with setup instructions

2. **Scratch Org Definition & Access:**
   - Scratch org definition file (`config/stripe-scratch-def.json`) with all configurations
   - Working demonstration environment (scratch org)
   - Test data loaded via data import scripts
   - Sample subscriptions and transactions
   - Permission sets assigned to users

3. **Middleware Deployment:**
   - Deployed and accessible middleware service
   - Webhook URL registered with Stripe
   - Monitoring dashboards configured in Coralogix
   - Logs accessible via Coralogix

4. **Documentation Package:**
   - Setup guide for developers
   - API documentation
   - Architecture diagrams
   - Troubleshooting guide
   - Operations runbook

5. **Presentation:**
   - 1-hour demo covering technical implementation and business value
   - Architecture overview
   - Live demonstration of key flows:
     - Contact creation → Stripe customer sync
     - Subscription creation with Checkout
     - Webhook event processing
     - Payment transaction tracking
   - Technical decisions and tradeoffs discussion
   - Q&A preparation

6. **Test Results:**
   - Evidence of 75%+ code coverage (Salesforce)
   - All tests passing (Salesforce and middleware)
   - Test execution reports
   - Code quality metrics

---

## Evaluation Criteria

1. **Technical Excellence (30%)**
   - Code quality and adherence to best practices
   - Proper error handling and logging
   - Test coverage and quality
   - Performance optimization
   - Security implementation

2. **Integration Completeness (25%)**
   - Full bidirectional data flow between systems
   - All critical webhook events handled
   - Successful authentication and API calls
   - Data consistency between Stripe and Salesforce

3. **Middleware Architecture (20%)**
   - Proper event queuing and processing
   - Scalable and resilient design
   - OAuth implementation
   - Rate limiting and throttling
   - Monitoring and observability

4. **Security Implementation (15%)**
   - Proper authentication mechanisms
   - Secret management best practices
   - Input validation and sanitization
   - Secure error messaging
   - Access control and permissions

5. **Team Collaboration (10%)**
   - Effective use of Git (branching, commits, PRs)
   - Code reviews and feedback
   - Documentation quality
   - Communication and coordination

---

## Success Metrics

**Functional Requirements:**
- ✅ Contact creation automatically creates Stripe customer
- ✅ Subscription can be created with Checkout session
- ✅ Webhook events are received and processed successfully
- ✅ Payment transactions are tracked in Salesforce
- ✅ Subscription status stays synchronized
- ✅ Failed payments are logged and visible

**Technical Requirements:**
- ✅ 75%+ code coverage in Salesforce
- ✅ All tests passing
- ✅ OAuth authentication working
- ✅ Webhook signature verification implemented
- ✅ Error handling and retry logic functional
- ✅ Logging capturing all events

**Non-Functional Requirements:**
- ✅ Webhook processed within 5 seconds (p95)
- ✅ < 1% error rate in production
- ✅ No hardcoded secrets or credentials
- ✅ Documentation complete and accurate
- ✅ Code follows Salesforce best practices
