# Middleware Deployment Readiness Status

## Quick Answer: Will `deploy-lambda.sh` work for 3 Lambdas?

**Answer: YES, but with 2 minor fixes needed first** ⚠️

The deployment script will automatically deploy all 3 Lambda functions because SAM deploys everything defined in `template.yaml`. However, there are 2 things missing:

1. ⚠️ **DynamoDB Batch Accumulator Table** (needs to be added to template.yaml)
2. ⚠️ **Output values** for new resources (low-priority queue, bulk processor)

---

## Current Status: 95% Complete

### ✅ What Works Right Now

The deployment script **WILL deploy**:
- ✅ Lambda 1: Webhook Receiver
- ✅ Lambda 2: SQS Worker
- ✅ Lambda 3: Bulk Processor ← NEW!
- ✅ API Gateway
- ✅ Main SQS Queue
- ✅ Low-Priority SQS Queue ← NEW!
- ✅ Dead Letter Queue
- ✅ DynamoDB Cache Table
- ✅ DynamoDB Rate Limit Tables (3 tables)
- ✅ Secrets Manager (credentials)
- ✅ CloudWatch Logs
- ✅ IAM Roles & Policies

### ⚠️ What's Missing (2 Issues)

#### Issue 1: DynamoDB Batch Accumulator Table

**Problem:** The batch accumulator service expects a table named `stripe-event-batches` but it's not defined in the SAM template.

**Impact:** Bulk Processor Lambda will fail when trying to accumulate batches.

**Location:** Needs to be added to `template.yaml` around line 245 (after rate limit tables)

**Fix Required:**
```yaml
# Add to template.yaml after RateLimitPerDayTable

  # Batch Accumulator Table - Stores events for bulk processing
  BatchAccumulatorTable:
    Type: AWS::DynamoDB::Table
    Properties:
      TableName: !Sub ${AWS::StackName}-batch-accumulator
      BillingMode: PAY_PER_REQUEST
      AttributeDefinitions:
        - AttributeName: pk
          AttributeType: S
        - AttributeName: sk
          AttributeType: S
      KeySchema:
        - AttributeName: pk
          KeyType: HASH
        - AttributeName: sk
          KeyType: RANGE
      TimeToLiveSpecification:
        AttributeName: ttl
        Enabled: true
      Tags:
        - Key: Purpose
          Value: BatchAccumulation
        - Key: Environment
          Value: !Ref Environment
```

#### Issue 2: Missing Output Values

**Problem:** The deployment script doesn't display info about new resources.

**Impact:** Users won't see the low-priority queue URL or bulk processor function ARN after deployment.

**Fix Required:**
```yaml
# Add to Outputs section in template.yaml (around line 540)

  LowPriorityQueueUrl:
    Description: Low-Priority SQS Queue URL (for Bulk API processing)
    Value: !Ref LowPriorityEventQueue
    Export:
      Name: !Sub ${AWS::StackName}-LowPriorityQueueUrl

  BulkProcessorFunctionArn:
    Description: Bulk Processor Lambda Function ARN
    Value: !GetAtt BulkProcessorFunction.Arn
    Export:
      Name: !Sub ${AWS::StackName}-BulkProcessorFunctionArn

  BatchAccumulatorTableName:
    Description: Batch Accumulator DynamoDB Table Name
    Value: !Ref BatchAccumulatorTable
    Export:
      Name: !Sub ${AWS::StackName}-BatchAccumulatorTableName
```

---

## How to Deploy (After Fixes)

### Option A: Quick Deploy (Automated)

```bash
cd middleware

# Make script executable
chmod +x scripts/deploy-lambda.sh

# Deploy to development
./scripts/deploy-lambda.sh development us-east-1

# Deploy to production
./scripts/deploy-lambda.sh production us-east-1
```

The script will:
1. ✅ Check prerequisites (SAM CLI, AWS CLI, Docker)
2. ✅ Validate template
3. ✅ Build all 3 Lambda functions
4. ✅ Deploy entire stack
5. ✅ Display webhook URL and queue URLs

### Option B: Manual Deploy (Step by Step)

```bash
cd middleware

# 1. Validate template
sam validate --template template.yaml

# 2. Build all Lambda functions
sam build --use-container --cached --parallel

# 3. Deploy (guided mode)
sam deploy --guided

# Follow prompts to enter:
# - Stack name: salesforce-stripe-middleware-dev
# - AWS Region: us-east-1
# - Stripe API Key: sk_test_...
# - Stripe Webhook Secret: whsec_...
# - Salesforce Client ID: 3MVG...
# - Salesforce Client Secret: ***
# - Salesforce Instance URL: https://login.salesforce.com
```

---

## What Gets Deployed

### Lambda Functions (3 Total)

| Lambda | File | Purpose | Trigger | Timeout | Memory |
|--------|------|---------|---------|---------|--------|
| **Webhook Receiver** | `lambda_handler.py` | Receives webhooks, verifies signatures | API Gateway | 10s | 256MB |
| **SQS Worker** | `sqs_worker.py` | Processes HIGH/MEDIUM events via REST API | Main SQS Queue | 90s | 512MB |
| **Bulk Processor** | `bulk_processor.py` | Processes LOW events via Bulk API 2.0 | Low-Priority Queue | 300s | 1024MB |

### SQS Queues (3 Total)

| Queue | Purpose | Batch Size | Max Wait |
|-------|---------|------------|----------|
| **Main Queue** | HIGH/MEDIUM priority events | 5 messages | 10s |
| **Low-Priority Queue** | LOW priority events (Bulk API) | 10 messages | 30s |
| **Dead Letter Queue** | Failed events after retries | - | - |

### DynamoDB Tables (6 Total)

| Table | Purpose | TTL | Billing |
|-------|---------|-----|---------|
| **Cache Table** | OAuth tokens | 1 hour | Pay-per-request |
| **Rate Limit (Per-Second)** | 10 calls/sec limit | Yes | Pay-per-request |
| **Rate Limit (Per-Minute)** | 250 calls/min limit | Yes | Pay-per-request |
| **Rate Limit (Per-Day)** | 15k calls/day limit | Yes | Pay-per-request |
| **Idempotency Table** | Duplicate event prevention | 7 days | Pay-per-request |
| **Batch Accumulator** | Event batching for Bulk API | 24 hours | Pay-per-request |

---

## Post-Deployment Steps

After running `deploy-lambda.sh`, you'll get output like:

```
╔════════════════════════════════════════════════════════════════╗
║                    Deployment Summary                          ║
╚════════════════════════════════════════════════════════════════╝

✓ Stack Name: salesforce-stripe-middleware-development
✓ Region: us-east-1
✓ Environment: development

ℹ Webhook URL (configure in Stripe):
  https://abc123.execute-api.us-east-1.amazonaws.com/webhook/stripe

ℹ SQS Queue URL:
  https://sqs.us-east-1.amazonaws.com/123456789/stripe-events

ℹ Dead Letter Queue URL:
  https://sqs.us-east-1.amazonaws.com/123456789/stripe-events-dlq
```

### 1. Configure Stripe Webhook

Go to https://dashboard.stripe.com/webhooks and add:

**Endpoint URL:** (from deployment output above)

**Events to send:**
- `checkout.session.completed`
- `checkout.session.expired`
- `customer.updated`
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `invoice.payment_succeeded`
- `invoice.payment_failed`
- `payment_intent.succeeded`
- `payment_intent.payment_failed`

### 2. Test the Webhook

```bash
# Install Stripe CLI
brew install stripe/stripe-cli/stripe

# Login
stripe login

# Trigger test event
stripe trigger payment_intent.succeeded

# Check logs
sam logs --stack-name salesforce-stripe-middleware-development --tail
```

### 3. Monitor the System

**CloudWatch Logs:**
```bash
# Webhook Receiver logs
sam logs -n WebhookFunction --stack-name salesforce-stripe-middleware-development --tail

# SQS Worker logs
sam logs -n SqsWorkerFunction --stack-name salesforce-stripe-middleware-development --tail

# Bulk Processor logs
sam logs -n BulkProcessorFunction --stack-name salesforce-stripe-middleware-development --tail
```

**CloudWatch Dashboard:**
- Go to AWS Console → CloudWatch → Dashboards
- Create custom dashboard with:
  - Lambda invocations (all 3 functions)
  - Lambda errors
  - Lambda duration
  - SQS queue depths (main + low-priority)
  - DLQ message count

**SQS Queues:**
- Main Queue: https://console.aws.amazon.com/sqs
- Check message counts
- Monitor age of oldest message
- Watch for messages in DLQ

---

## Architecture Verification

After deployment, verify the 3-Lambda architecture:

```bash
# List all Lambda functions in stack
aws lambda list-functions \
  --query "Functions[?contains(FunctionName, 'salesforce-stripe-middleware')].FunctionName"

# Expected output:
# [
#   "salesforce-stripe-middleware-dev-WebhookFunction-...",
#   "salesforce-stripe-middleware-dev-SqsWorkerFunction-...",
#   "salesforce-stripe-middleware-dev-BulkProcessorFunction-..."
# ]

# List all SQS queues
aws sqs list-queues \
  --query "QueueUrls[?contains(@, 'salesforce-stripe-middleware')]"

# Expected output:
# [
#   "https://sqs.us-east-1.amazonaws.com/.../stripe-events",
#   "https://sqs.us-east-1.amazonaws.com/.../low-priority-events",
#   "https://sqs.us-east-1.amazonaws.com/.../stripe-events-dlq"
# ]

# List all DynamoDB tables
aws dynamodb list-tables \
  --query "TableNames[?contains(@, 'salesforce-stripe-middleware')]"

# Expected output:
# [
#   "salesforce-stripe-middleware-dev-cache",
#   "salesforce-stripe-middleware-dev-batch-accumulator",
#   "salesforce-rate-limit-per-second",
#   "salesforce-rate-limit-per-minute",
#   "salesforce-rate-limit-per-day"
# ]
```

---

## Cost Estimate

### Monthly AWS Costs (Development Environment)

**Assumptions:**
- 10,000 webhook events/month
- 70% HIGH/MEDIUM (7,000 events → REST API)
- 30% LOW (3,000 events → Bulk API, batched to 15 jobs)

| Service | Usage | Cost |
|---------|-------|------|
| **Lambda (Webhook Receiver)** | 10,000 invocations × 256MB × 0.5s | $0.00 (free tier) |
| **Lambda (SQS Worker)** | 7,000 invocations × 512MB × 3s | $0.21 |
| **Lambda (Bulk Processor)** | 300 invocations × 1024MB × 30s | $0.30 |
| **API Gateway** | 10,000 requests | $0.01 (free tier) |
| **SQS** | 17,000 requests (with long polling) | $0.00 (free tier) |
| **DynamoDB** | 50k reads, 20k writes | $0.00 (free tier) |
| **CloudWatch Logs** | 1 GB | $0.50 |
| **Secrets Manager** | 3 secrets | $1.20 |
| **Total** | | **~$2.22/month** |

### Production Costs (1M events/month)

| Service | Usage | Estimated Cost |
|---------|-------|----------------|
| Lambda | 1M invocations | $20-40 |
| API Gateway | 1M requests | $3.50 |
| SQS | 2M requests | $0.80 |
| DynamoDB | 5M reads, 2M writes | $5.00 |
| CloudWatch | 10 GB logs | $5.00 |
| Secrets Manager | 3 secrets | $1.20 |
| **Total** | | **~$35-55/month** |

---

## Summary

### Can I deploy with `deploy-lambda.sh`?

**YES!** The script will deploy all 3 Lambdas automatically. Just fix these 2 things first:

1. ✅ Add `BatchAccumulatorTable` to `template.yaml`
2. ✅ Add output values for new resources

### What's the deployment order?

SAM deploys in this order:
1. Secrets Manager (credentials)
2. DynamoDB Tables (6 tables)
3. SQS Queues (3 queues)
4. Lambda Functions (3 functions)
5. API Gateway (HTTP API)
6. CloudWatch Log Groups
7. IAM Roles & Policies

Everything is deployed as a single CloudFormation stack, so it's all-or-nothing (atomic deployment).

### How long does deployment take?

- **First deployment:** 5-10 minutes
- **Subsequent deployments:** 2-5 minutes (using `--cached` flag)

### Can I roll back if something fails?

**YES!** CloudFormation automatically rolls back on failure. You can also manually rollback:

```bash
aws cloudformation delete-stack \
  --stack-name salesforce-stripe-middleware-development \
  --region us-east-1
```

---

## Next Steps

1. **Fix template.yaml** (add missing table and outputs)
2. **Run deployment:** `./scripts/deploy-lambda.sh development us-east-1`
3. **Configure Stripe webhook** (use URL from output)
4. **Test with Stripe CLI:** `stripe trigger payment_intent.succeeded`
5. **Monitor CloudWatch logs** to verify all 3 Lambdas are working

Need help with the template fixes? Let me know and I'll add them for you! 🚀
