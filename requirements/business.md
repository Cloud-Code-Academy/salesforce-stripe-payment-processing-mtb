# Salesforce-Stripe Payment Processing - Business Requirements

This capstone project challenges you to build a production-ready payment processing solution that integrates Salesforce with Stripe. You'll solve real business problems while demonstrating mastery of integration patterns, authentication, asynchronous processing, error handling, and middleware architecture.

**Guiding Principle:** Build a solution that could be deployed in a real business environment for managing customer payments and subscriptions.

---

## Project Scope & Team Structure

- **Duration:** 4 weeks
- **Team Size:** 3 members maximum
- **Development Model:** Scratch org-based development with individual scratch orgs per team member
- **Demo Environment:** Trailhead Playground for final demonstration (Connected Apps do not work in scratch orgs)
- **Collaboration:** Required through Slack, virtual meetings, and code reviews
- **Repository:** All metadata must be stored and versioned in GitHub
- **Architecture:** Full-stack integration with Salesforce (backend), FastAPI middleware, and Stripe

---

## Technical Architecture Patterns

Your solution must demonstrate these real-world integration patterns:

- **Outbound Integrations:** Salesforce → Stripe (customer creation, subscription management)
- **Inbound Integrations:** Stripe → Salesforce (webhooks for payment events via middleware)
- **Middleware Layer:** FastAPI-based webhook handler with event queuing and processing
- **Authentication:** Multiple secure API communication patterns (API keys, OAuth 2.0)
- **Asynchronous Processing:** Queueable classes for bulk operations, SQS for event buffering
- **Error Handling:** Comprehensive logging and retry mechanisms with exponential backoff
- **Rate Limiting:** Sliding window algorithm for API rate limiting

---

## Weekly Planning Guide

### Week 1: Foundation & Discovery

**Goal:** Understand the business requirements and establish technical foundation

#### Business Research Tasks:
1. **User Story Analysis:**
   - Review all business user stories below
   - Map user stories to technical requirements
   - Identify critical vs. nice-to-have features
   - Create user journey maps for each persona

2. **Stripe API Research:**
   - Study Stripe's API documentation (Customers, Subscriptions, Checkout, Payment Intents)
   - Understand webhook event types and payloads
   - Explore Stripe's test mode and dashboard
   - Review Stripe's security best practices

3. **Data Flow Analysis:**
   - Map what data needs to flow between Salesforce and Stripe
   - Identify synchronous vs. asynchronous operations
   - Design data model to support business processes
   - Plan for data consistency and conflict resolution

#### Technical Setup Tasks:
1. **Version Control Setup:**
   - Create GitHub repository with proper branching strategy (main, develop, feature branches)
   - Configure .gitignore and .forceignore for Salesforce metadata
   - Create initial README with project overview

2. **Stripe Developer Environment:**
   - Create Stripe developer account
   - Generate test API keys
   - Set up webhook endpoints (placeholder URLs)

3. **Salesforce Scratch Org Setup:**
   - Create scratch org definition file (`config/stripe-scratch-def.json`)
   - Authenticate Dev Hub
   - Create scratch orgs for each team member
   - Install recommended packages (Nebula Logger)

4. **Data Model Design:**
   - Design custom objects based on business requirements
   - Define relationships between objects
   - Plan external ID fields for upsert operations
   - Document data model with ERD diagram

#### Week 1 Deliverables:
- ✅ Data model design that supports all business processes
- ✅ Custom objects created and deployed to scratch orgs
- ✅ Stripe API authentication working (test API key verified)
- ✅ Project plan for remaining weeks with task assignments
- ✅ Architecture diagram showing system components
- ✅ Sequential diagram for data flow
- ✅ GitHub repository with initial metadata

---

### Week 2: Core Integration Development

**Goal:** Build the essential data flow between systems and middleware foundation

#### Salesforce → Stripe Integration:
1. **Customer Synchronization:**
   - Implement Contact trigger for automatic customer creation
   - Build StripeCustomerService with API wrapper
   - Add Named Credentials for secure authentication
   - Implement error handling and logging (Nebula Logger)
   - Create comprehensive test coverage with mocks

2. **Subscription Management:**
   - Build service class for Stripe Checkout session creation
   - Implement subscription record creation in Salesforce
   - Support multiple pricing plans via Custom Metadata Types
   - Add Queueable class for bulk subscription operations
   - Generate and store checkout URLs

#### Middleware Infrastructure:
1. **FastAPI Framework Setup:**
   - Initialize FastAPI project structure
   - Create webhook endpoint (`POST /webhook/stripe`)
   - Implement Stripe webhook signature verification (HMAC-SHA256)
   - Add health check endpoint (`GET /health`)
   - Set up structured logging with correlation IDs

2. **AWS Infrastructure Configuration:**
   - Create SQS queue for event buffering
   - Set up DynamoDB for token caching and temporary storage
   - Configure AWS Secrets Manager for credential storage
   - Configure Lambda deployment
   - Set up IAM roles with least privilege access

3. **Salesforce Connected App & OAuth:**
   - Create Connected App in Salesforce (or use Trailhead Playground for demo as Connected Apps do not work in scratch orgs)
   - Configure OAuth 2.0 client credentials flow
   - Generate client ID and client secret
   - Store credentials in AWS Secrets Manager
   - Test OAuth token acquisition from middleware

4. **Middleware-to-Salesforce Integration:**
   - Implement OAuth token management (acquire, refresh, cache in DynamoDB)
   - Create Salesforce REST API client wrapper
   - Test basic CRUD operations (create, update records)
   - Implement environment variable configuration
   - Add error handling and retry logic

#### Technical Guidance:
- Use Named Credentials for secure API authentication (Salesforce → Stripe)
- Implement wrapper classes for Stripe API requests/responses
- Create custom exceptions for integration-specific errors
- Use Queueable classes for any asynchronous operations in Salesforce
- Store all secrets in AWS Secrets Manager (never hardcode)
- Implement idempotency for all API operations

#### Week 2 Deliverables:
- ✅ Working customer sync from Salesforce to Stripe
- ✅ Subscription creation and Stripe Checkout integration
- ✅ FastAPI middleware deployed and accessible
- ✅ OAuth authentication between middleware and Salesforce working
- ✅ SQS queue receiving and processing events
- ✅ Basic test coverage (50%+) for core functionality
- ✅ Error handling framework in place with logging

---

### Week 3: Webhook Processing & Advanced Features

**Goal:** Handle real-time updates from Stripe and build advanced capabilities

#### Webhook Event Processing:
1. **Critical Event Handlers:**
   Implement handlers for these high-priority events:
   - `checkout.session.completed` - Update subscription status to active
   - `customer.subscription.created` - Create new subscription records in Salesforce
   - `payment_intent.succeeded` - Create payment transaction record
   - `payment_intent.payment_failed` - Log failure and trigger alerts
   - `customer.subscription.deleted` - Handle cancellations
   - `customer.subscription.updated` - Sync subscription changes
   - `invoice.payment_succeeded` - Record recurring payment success
   - `invoice.payment_failed` - Trigger dunning process

2. **Low-Priority Event Handlers:**
   - `customer.updated` - Sync customer data changes (batched)
   - Non-critical metadata updates (batched via Bulk API)

3. **Event Processing Architecture:**
   - Build event router based on Stripe event type
   - Implement strategy pattern for different event types
   - Add idempotency checks using Stripe event IDs
   - Implement event ordering and duplicate detection
   - Create priority queue (high-priority = real-time, low-priority = batched)

#### Advanced Processing Features:
1. **Priority-Based Processing:**
   - **High-Priority Events:** Process immediately via Salesforce REST API
   - **Low-Priority Events:** Batch in DynamoDB → Salesforce Bulk API
   - Implement decision logic to route events appropriately

2. **Sliding Window Rate Limiting:**
   - Implement DynamoDB-based sliding window algorithm
   - Track API calls per minute/hour window
   - Dynamically throttle based on remaining Salesforce API quota
   - Prevent exceeding governor limits

3. **Retry Mechanisms:**
   - Exponential backoff with jitter
   - Max 5 retry attempts for both inbound and outbound calls
   - Dead letter queue for permanent failures
   - Comprehensive logging of retry attempts

4. **Data Synchronization:**
   - Timestamp-based conflict resolution (last-write-wins)
   - Pagination handling for large datasets
   - Audit trail for all sync activities
   - Idempotency keys for safe retries

#### Bulk Operation Support:
- Implement Queueable chaining for complex workflows
- Build SQS consumer for asynchronous event processing
- Test bulk operations with 200+ records

#### Comprehensive Logging System:
- **Salesforce:** Nebula Logger for all integration events
- **Middleware:** Structured JSON logs with correlation IDs
- **Monitoring:** CloudWatch integration for centralized observability
- Error categorization (network, business logic, data)

#### Technical Options:
Your team is implementing the **Middleware Architecture** approach:
- External FastAPI service handles webhook processing
- SQS buffers events to handle traffic spikes
- DynamoDB provides storage and token caching
- OAuth 2.0 for middleware-to-Salesforce authentication
- Docker for containerization (not using Terraform)

#### Week 3 Deliverables:
- ✅ Functional webhook processing for all critical events (including `customer.subscription.created`)
- ✅ Real-time data synchronization working
- ✅ Priority-based processing (high-priority real-time, low-priority batched)
- ✅ Sliding window rate limiting implemented
- ✅ Bulk operation capabilities tested
- ✅ Comprehensive logging system in place with CloudWatch
- ✅ 70%+ code coverage achieved
- ✅ Retry logic with exponential backoff functional

---

### Week 4: Polish & Production Readiness

**Goal:** Ensure production-quality code, security, and user experience

#### Testing & Quality Assurance:
1. **Achieve 75%+ Test Coverage:**
   - Unit tests for all Apex classes
   - Integration tests for complete workflows
   - Middleware test suite with pytest
   - Test data factory for consistent setup
   - HttpCalloutMockFactory for API mocking

2. **Test Scenarios:**
   - Positive scenarios (happy path)
   - Negative scenarios (error handling)
   - Edge cases (null values, missing data)
   - Concurrent operations
   - Rate limiting behavior
   - Token expiration and refresh
   - Network failures and retries

3. **Performance Testing:**
   - Load test webhook endpoint (100+ events/minute)
   - Test bulk operations (200+ records)
   - Verify governor limit optimization
   - Measure p95 response times

#### Security Hardening:
1. **Secret Management Audit:**
   - Verify no hardcoded credentials
   - Confirm secret rotation policies (90 days)
   - Review IAM policies for least privilege
   - Enable audit logging for secret access

2. **Input Validation:**
   - Sanitize all incoming webhook data
   - Validate data types and required fields
   - Prevent SOQL/SOSL injection
   - Implement webhook signature verification

3. **Access Control:**
   - Review Salesforce permission sets
   - Validate minimal OAuth scopes
   - Ensure integration user has appropriate permissions
   - Configure network security groups (AWS)

#### Performance Optimization:
- SOQL query optimization and bulkification
- Minimize API calls (batch operations)
- Redis caching strategy refinement
- Connection pooling (middleware)
- Async request handling (FastAPI async/await)

#### Documentation & User Experience:
1. **User Documentation:**
   - Setup guide for administrators
   - User guide for sales representatives
   - User guide for customer service
   - Troubleshooting guide for common issues

2. **Technical Documentation:**
   - README with setup instructions
   - Architecture diagrams (data flow, component diagram, sequence diagrams)
   - API documentation
   - Deployment guide (scratch org, middleware, AWS)

#### Presentation Preparation:
1. **Demo Script:**
   - Create demo script with user stories
   - Prepare test data for live demonstration
   - Practice end-to-end flows

2. **Presentation Materials:**
   - Architecture overview slides
   - Technical decisions and tradeoffs
   - Business value demonstration
   - Q&A preparation

#### Week 4 Deliverables:
- ✅ Complete test suite with 75%+ coverage
- ✅ All tests passing (Salesforce and middleware)
- ✅ Production-ready error handling and monitoring
- ✅ Security audit completed
- ✅ User documentation and setup guide
- ✅ Technical documentation package
- ✅ Final presentation and demonstration materials
- ✅ Monitoring dashboards configured in CloudWatch
- ✅ Trailhead Playground prepared for demo environment

---

## Business Requirements

### Customer Management User Stories

#### Sales Representative Needs:

**As a Sales Representative, I need to:**

1. **Seamless Customer Creation:**
   - Create customer records in Salesforce that automatically appear in Stripe
   - **Acceptance Criteria:**
     - When I create a Contact in Salesforce, a Stripe customer is created within 30 seconds
     - Contact's email, name, and phone sync to Stripe automatically
     - I see confirmation that the sync was successful
     - Any errors are clearly displayed with actionable messages

2. **Subscription Setup:**
   - Set up new subscriptions with different pricing plans
   - **Acceptance Criteria:**
     - I can select from available pricing plans (stored in Custom Metadata)
     - System generates a secure Stripe Checkout URL
     - Checkout URL is stored in the Subscription record
     - I can send the checkout link to the customer
     - Subscription status updates automatically after customer completes payment

3. **Customer Information Updates:**
   - Update customer information and see changes reflected in both systems
   - **Acceptance Criteria:**
     - When I update a Contact in Salesforce, changes sync to Stripe
     - When customer updates info in Stripe, changes sync back to Salesforce
     - Conflicts are resolved automatically (last-write-wins)
     - I'm notified if sync fails

4. **Payment History Visibility:**
   - View complete customer payment history from Salesforce
   - **Acceptance Criteria:**
     - I can see all Payment Transaction records related to a customer
     - Transaction records show status, amount, date, and payment method
     - I can filter transactions by status (succeeded, failed, etc.)
     - Historical data is accurate and up-to-date

---

#### Customer Service Representative Needs:

**As a Customer Service Representative, I need to:**

1. **Real-Time Payment Information:**
   - Access real-time customer payment and subscription information
   - **Acceptance Criteria:**
     - Subscription status is updated within 1 minute of changes in Stripe
     - Payment transaction records are created within 1 minute of Stripe events
     - I can see current subscription status (active, past_due, canceled, etc.)
     - I can see when the next billing date is

2. **Automatic Data Synchronization:**
   - See when customer data changes in Stripe and have Salesforce updated automatically
   - **Acceptance Criteria:**
     - Customer updates (email, name, phone) sync from Stripe to Salesforce automatically
     - Subscription changes (upgrades, cancellations) are reflected in real-time
     - Payment failures trigger immediate updates
     - I'm notified of high-priority changes (payment failures, cancellations)

3. **Billing Support:**
   - Help customers with billing questions using complete transaction history
   - **Acceptance Criteria:**
     - I can view all transactions for a customer in chronological order
     - Failed payments are clearly marked with error reasons
     - I can see payment method types used
     - I can view subscription billing cycles and renewal dates

---

#### Finance Team Needs:

**As a Finance Team Member, I need to:**

1. **Revenue Monitoring:**
   - Monitor subscription revenue and billing cycles
   - **Acceptance Criteria:**
     - I can generate reports on active subscriptions
     - I can see MRR (Monthly Recurring Revenue) by subscription plan
     - I can track subscription churn rate
     - Reports are accurate and reflect current data

2. **Payment Tracking:**
   - Track payment successes and failures
   - **Acceptance Criteria:**
     - All payment transactions are recorded in Salesforce
     - Failed payments are flagged for follow-up
     - I can generate reports on payment failure rates
     - I can identify customers with recurring payment issues

3. **Event Notifications:**
   - Receive notifications for important payment events
   - **Acceptance Criteria:**
     - Critical failures trigger immediate alerts
     - High error rates (>5%) trigger warnings
     - API limit approaching (>80%) triggers notifications
     - Sync lag exceeding threshold triggers alerts

4. **Financial Reporting:**
   - Generate reports on customer payment patterns
   - **Acceptance Criteria:**
     - I can create custom reports using Payment Transaction data
     - I can create dashboards showing payment trends
     - Data is consistent between Salesforce and Stripe
     - Reports can be exported for external analysis

---

## Required Business Processes

### Process 1: New Customer Onboarding

**Business Flow:**

1. **Step 1: Contact Creation**
   - Sales rep creates Contact in Salesforce with customer details (name, email, phone)
   - **Technical Implementation:** Contact trigger fires → Queueable job → Stripe API call

2. **Step 2: Automatic Stripe Sync**
   - Customer information automatically syncs to Stripe
   - Stripe Customer ID is stored in Salesforce (external ID field)
   - **Technical Implementation:** StripeCustomerService creates customer via API, stores customer ID

3. **Step 3: Subscription Setup**
   - Sales rep creates Subscription record and selects pricing plan
   - System creates Stripe Checkout session
   - **Technical Implementation:** StripeSubscriptionService calls Stripe Checkout API, stores session ID and URL

4. **Step 4: Customer Payment**
   - Customer receives secure payment link (Checkout URL)
   - Customer completes signup in Stripe's secure checkout
   - **Technical Implementation:** Stripe hosts checkout, securely processes payment

5. **Step 5: Subscription Activation**
   - Stripe sends `checkout.session.completed` webhook to middleware
   - Middleware updates Subscription record status to "Active"
   - Payment Transaction record is created
   - **Technical Implementation:** FastAPI webhook → SQS → Event handler → Salesforce REST API

6. **Step 6: Real-Time Status Updates**
   - All status changes are reflected in both systems in real-time
   - Sales rep and customer see consistent information
   - **Technical Implementation:** Bidirectional sync via webhooks and API calls

---

### Process 2: Ongoing Payment Management

**Business Flow:**

1. **Automatic Subscription Renewals:**
   - Stripe processes subscription renewals automatically
   - `invoice.payment_succeeded` webhook sent to middleware
   - Payment Transaction record created in Salesforce
   - Subscription period dates updated
   - **Technical Implementation:** Webhook event → Middleware → Salesforce upsert via REST API

2. **Payment Success Tracking:**
   - All successful payments captured in Salesforce
   - Finance team can track revenue
   - **Technical Implementation:** `payment_intent.succeeded` webhook → Create Payment_Transaction__c

3. **Payment Failure Handling:**
   - Failed payments trigger immediate alerts
   - `payment_intent.payment_failed` or `invoice.payment_failed` webhook received
   - Payment Transaction record created with failed status
   - Subscription status updated to "Past Due"
   - Finance and customer service teams notified
   - **Technical Implementation:** High-priority webhook event → Real-time processing → Alert system

4. **Customer Data Synchronization:**
   - Customer updates email in Stripe dashboard
   - `customer.updated` webhook sent to middleware
   - Stripe Customer record updated in Salesforce
   - Contact record updated (if linked)
   - **Technical Implementation:** Low-priority webhook event → Batched in DynamoDB → Bulk API processing

5. **Subscription Modifications:**
   - Customer upgrades/downgrades subscription in Stripe
   - `customer.subscription.updated` webhook sent
   - Subscription record updated in Salesforce with new amount and plan
   - **Technical Implementation:** Webhook event → Middleware → Salesforce update

6. **Subscription Cancellations:**
   - Customer cancels subscription in Stripe
   - `customer.subscription.deleted` webhook sent
   - Subscription status updated to "Canceled" in Salesforce
   - Sales and customer service notified
   - **Technical Implementation:** High-priority webhook event → Real-time processing → Status update

7. **Failed Sync Recovery:**
   - If webhook processing fails, retry with exponential backoff
   - After 5 attempts, move to dead letter queue
   - Admin receives alert for manual intervention
   - **Technical Implementation:** Retry mechanism (2s, 4s, 8s, 16s, 32s) → DLQ → Alert

---

### Process 3: Data Synchronization Requirements

**Consistency Rules:**

1. **Customer Information:**
   - Must remain consistent between Salesforce and Stripe
   - Conflicts resolved using timestamp-based last-write-wins
   - Updates in either system trigger sync to the other

2. **Subscription Status:**
   - Must be reflected in real-time (within 1 minute)
   - High-priority updates processed immediately via REST API
   - Status changes tracked with field history

3. **Payment Transactions:**
   - Must be tracked for financial reporting
   - All payment events (success, failure) create records
   - Transaction dates and amounts must be accurate

4. **Sync Failure Handling:**
   - Failed sync operations must be logged with Nebula Logger
   - Automatic retry with exponential backoff
   - Dead letter queue for permanent failures
   - Admin alerts for critical failures

---

## Technical Decision Points

As you build the integration, you'll need to make these key technical decisions based on the business requirements:

### 1. Data Model Design

**Questions to Answer:**
- How will you structure Salesforce objects to track customers, subscriptions, and payments?
  - **Answer:** 6 custom objects (see technical.md data model)
  - Stripe_Customer__c, Stripe_Subscription__c, Payment_Transaction__c
  - Pricing_Plan__c, Pricing_Tier__c for flexible pricing
  - Contact with Stripe_Customer_ID__c external ID

- What relationships between objects best support the business processes?
  - **Answer:** Lookups for flexibility, Master-Detail for Pricing Tiers
  - Contact → Stripe_Customer__c (1:M)
  - Stripe_Customer__c → Stripe_Subscription__c (1:M)
  - Stripe_Subscription__c → Payment_Transaction__c (1:M)

- How will you handle Stripe's data structure in Salesforce?
  - **Answer:** External ID fields for upsert operations
  - JSON deserialization with wrapper classes
  - Picklist values matching Stripe enums

### 2. API Integration Strategy

**Questions to Answer:**
- Which Stripe API endpoints will you need for each business process?
  - **Answer:**
    - POST `/v1/customers` - Create customer
    - POST `/v1/checkout/sessions` - Create checkout session
    - GET `/v1/customers/{id}` - Retrieve customer
    - GET `/v1/subscriptions/{id}` - Retrieve subscription

- How will you handle authentication and security for API calls?
  - **Answer:**
    - Salesforce → Stripe: Named Credentials with API key
    - Middleware → Salesforce: OAuth 2.0 client credentials flow
    - Webhook signature verification: HMAC-SHA256

- What error scenarios do you need to plan for?
  - **Answer:**
    - Network failures (timeout, connection refused)
    - Rate limiting (429 responses)
    - Invalid data (400 errors)
    - Authentication failures (401/403)
    - Stripe API errors (specific error codes)

### 3. Webhook Processing Approach

**Questions to Answer:**
- What Stripe events do you need to handle based on the business requirements?
  - **Answer:** 9 critical events (see technical.md webhook table)
  - High-priority: payment failures, subscription cancellations, checkout completions, new subscription creation (`customer.subscription.created`)
  - Low-priority: customer updates, metadata changes

- How will you ensure webhook data is processed reliably?
  - **Answer:**
    - SQS queue for buffering
    - Idempotency using Stripe event IDs
    - Retry mechanism with exponential backoff
    - Dead letter queue for permanent failures

- What happens when webhook processing fails?
  - **Answer:**
    - Retry up to 5 times with backoff
    - Log failure with correlation ID
    - Move to DLQ after max retries
    - Alert admin for manual intervention

### 4. User Experience Design

**Questions to Answer:**
- How will different business users interact with the system?
  - **Answer:**
    - Sales reps: Standard Salesforce UI (create Contacts, Subscriptions)
    - Customer service: Reports and dashboards
    - Finance: Custom reports on Payment Transactions
    - Admins: Integration health dashboard, error logs

- What information do they need to see and when?
  - **Answer:**
    - Sales: Checkout URLs, subscription status
    - Customer service: Payment history, subscription details
    - Finance: Transaction reports, failure rates
    - Admins: Sync status, error messages

- How will you handle error states and provide feedback?
  - **Answer:**
    - Error Message fields on records
    - Sync Status picklist (Pending, Completed, Failed)
    - Email alerts for critical failures
    - Integration health dashboard

---

## Technical Requirements & Standards

### Security & Authentication

- ✅ All payment processing must use Stripe's secure infrastructure (Stripe Checkout)
- ✅ No credit card data should be stored in Salesforce
- ✅ API communications must be authenticated and encrypted (HTTPS)
- ✅ Webhook signatures must be verified (HMAC-SHA256)
- ✅ Secrets stored in AWS Secrets Manager (never hardcoded)
- ✅ OAuth 2.0 for middleware-to-Salesforce authentication
- ✅ Named Credentials for Salesforce-to-Stripe authentication

### Performance & Reliability

- ✅ System must handle bulk operations efficiently (200+ records)
- ✅ Failed operations must be retried automatically (exponential backoff, max 5 attempts)
- ✅ All integration events must be logged for troubleshooting (Nebula Logger + CloudWatch)
- ✅ Performance must meet Salesforce governor limits (bulkification required)
- ✅ Webhook processing within 5 seconds (p95)
- ✅ Support 100+ webhook events per minute
- ✅ Maintain < 1% error rate

### Testing & Quality

- ✅ Minimum 75% code coverage for all Apex classes
- ✅ Test both positive and negative scenarios
- ✅ Use HTTP mocks for all external API testing (HttpCalloutMock)
- ✅ Document all setup and configuration steps
- ✅ Integration tests for end-to-end flows
- ✅ Load testing for webhook endpoint

### Recommended Tools

- **Nebula Logger:** For comprehensive logging throughout the integration
- **Named Credentials:** For secure external API authentication (Salesforce → Stripe)
- **Custom Metadata Types:** For configuration management (pricing plans)
- **Queueable Classes:** For asynchronous processing in Salesforce
- **FastAPI:** Modern Python web framework for middleware
- **AWS Services:** SQS, DynamoDB, Secrets Manager, Lambda
- **CloudWatch:** Centralized logging and monitoring
- **Docker:** For local development and testing

---

## Success Criteria & Evaluation

### Technical Excellence (30%)

- ✅ Code follows Salesforce best practices and design patterns
- ✅ Integration handles errors gracefully with proper logging
- ✅ Security implementation protects sensitive data
- ✅ Performance meets enterprise standards
- ✅ 75%+ code coverage with quality tests
- ✅ Proper bulkification and governor limit optimization

### Business Value (30%)

- ✅ All user stories are successfully implemented
- ✅ Business processes work end-to-end without manual intervention
- ✅ System provides value to sales, service, and finance teams
- ✅ Integration could realistically be deployed in production
- ✅ Data remains consistent between Salesforce and Stripe
- ✅ Real-time updates meet business requirements (< 1 minute)

### Integration Completeness (25%)

- ✅ Full bidirectional data flow between systems
- ✅ All critical webhook events handled
- ✅ Successful authentication and API calls
- ✅ Priority-based processing (high-priority real-time, low-priority batched)
- ✅ Rate limiting and throttling implemented
- ✅ Retry mechanisms functional

### Security Implementation (10%)

- ✅ Proper authentication mechanisms (OAuth, API keys)
- ✅ Secret management best practices (AWS Secrets Manager)
- ✅ Input validation and sanitization
- ✅ Webhook signature verification
- ✅ Secure error messaging (no data exposure)

### Team Collaboration (5%)

- ✅ Effective use of Git (branching, commits, PRs)
- ✅ Code reviews demonstrate knowledge sharing
- ✅ Documentation enables others to understand and maintain the system
- ✅ Presentation clearly communicates business value and technical approach

---

## Getting Started Questions

Before you begin coding, discuss these questions with your team:

### 1. Business Understanding
- **Question:** Which business processes are most critical to implement first?
- **Answer:** Start with customer onboarding (Contact → Stripe Customer sync) as it's foundational for all other processes.

### 2. Technical Architecture
- **Question:** How will you structure the integration to be maintainable and scalable?
- **Answer:** Three-tier architecture:
  - Salesforce (trigger handlers, service classes)
  - Middleware (FastAPI with event queuing)
  - Stripe (external API)

### 3. Data Flow
- **Question:** What data needs to move between systems and when?
- **Answer:**
  - **Salesforce → Stripe:** Customer creation (synchronous), Subscription creation (synchronous)
  - **Stripe → Salesforce:** Webhook events (asynchronous via middleware)
  - **Priority:** Payment failures = real-time, Customer updates = batched

### 4. Error Handling
- **Question:** What could go wrong and how will you handle it?
- **Answer:**
  - Network failures → Retry with exponential backoff
  - Rate limiting → Sliding window rate limiter
  - Invalid data → Validation and sanitization
  - Duplicate events → Idempotency checks
  - Permanent failures → Dead letter queue + alerts

### 5. Security
- **Question:** How will you protect customer data throughout the integration?
- **Answer:**
  - No credit card data in Salesforce (use Stripe Checkout)
  - Secrets in AWS Secrets Manager
  - OAuth 2.0 for middleware authentication
  - Webhook signature verification
  - HTTPS for all communications

### 6. Testing Strategy
- **Question:** How will you verify that everything works correctly?
- **Answer:**
  - Unit tests with HttpCalloutMock for Apex
  - Integration tests with pytest for middleware
  - End-to-end tests for complete flows
  - Load testing for webhook endpoint
  - Test both positive and negative scenarios

---

## Key Success Factors

### For Sales Representatives:
- ✅ Customer creation is seamless and automatic
- ✅ Subscription setup is quick and generates checkout links
- ✅ Error messages are clear and actionable

### For Customer Service:
- ✅ Payment and subscription information is accurate and up-to-date
- ✅ Transaction history is complete and easy to access
- ✅ Real-time updates happen within 1 minute

### For Finance Team:
- ✅ All transactions are recorded accurately
- ✅ Reports provide actionable insights
- ✅ Failed payments are flagged for follow-up
- ✅ Revenue tracking is accurate

### For Development Team:
- ✅ Code is maintainable and well-documented
- ✅ Testing coverage is comprehensive
- ✅ Error handling is robust
- ✅ Security best practices are followed
