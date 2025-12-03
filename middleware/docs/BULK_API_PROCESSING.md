# Bulk API Processing Architecture

## Overview

The middleware implements a **3-Lambda architecture** with priority-based event routing to optimize API usage and costs:

1. **Webhook Receiver Lambda** - Receives and validates Stripe webhooks
2. **SQS Worker Lambda** - Processes HIGH and MEDIUM priority events via REST API
3. **Bulk Processor Lambda** - Batch processes LOW priority events via Bulk API 2.0

This architecture ensures critical events are processed immediately while non-urgent events are batched for efficient bulk processing.

---

## Event Priority Classification

### HIGH Priority (Immediate REST API Processing)
**Response Time:** < 5 seconds
**Processing Method:** Real-time via Salesforce REST API

Events requiring immediate business action:
- `payment_intent.payment_failed` - Payment failures need immediate alerting
- `invoice.payment_failed` - Subscription payment failures
- `customer.subscription.deleted` - Subscription cancellations
- `checkout.session.expired` - Failed checkout sessions

**Flow:**
```
Stripe Webhook → API Gateway → Webhook Lambda → Main SQS Queue → SQS Worker Lambda → REST API → Salesforce
```

### MEDIUM Priority (Real-time REST API Processing)
**Response Time:** < 30 seconds
**Processing Method:** Real-time via Salesforce REST API

Standard business events:
- `payment_intent.succeeded` - Successful payments
- `invoice.payment_succeeded` - Successful subscription payments
- `customer.subscription.created` - New subscriptions
- `customer.subscription.updated` - Subscription changes
- `checkout.session.completed` - Successful checkouts

**Flow:**
```
Stripe Webhook → API Gateway → Webhook Lambda → Main SQS Queue → SQS Worker Lambda → REST API → Salesforce
```

### LOW Priority (Batch Bulk API Processing)
**Response Time:** < 60 seconds (batch accumulation)
**Processing Method:** Batched via Salesforce Bulk API 2.0

Non-urgent metadata updates:
- `customer.updated` - Customer profile changes (name, email, phone, metadata)

**Flow:**
```
Stripe Webhook → API Gateway → Webhook Lambda → Low-Priority SQS Queue → Bulk Processor Lambda → Bulk API 2.0 → Salesforce
```

---

## Architecture Components

### 1. Low-Priority SQS Queue

**Purpose:** Buffer low-priority events for batch processing

**Configuration:**
```yaml
QueueName: ${StackName}-low-priority-events
VisibilityTimeout: 300 seconds (5 minutes)
MessageRetentionPeriod: 4 days
MaxReceiveCount: 3 (before DLQ)
BatchSize: 10 messages
MaximumBatchingWindowInSeconds: 30 seconds
```

**Key Features:**
- Long polling enabled (20s)
- Dead Letter Queue integration
- Partial batch failure support

### 2. Bulk Processor Lambda

**Function:** `bulk_processor.lambda_handler`

**Configuration:**
```yaml
Timeout: 300 seconds (5 minutes)
MemorySize: 1024 MB
Concurrency: Recommended 2-5 (to control bulk job rate)
```

**Trigger:** SQS batch events (up to 10 messages)

**Responsibilities:**
- Receive SQS message batches
- Parse Stripe events
- Group events by type
- Transform to Salesforce records
- Submit to Bulk API 2.0
- Wait for job completion
- Report failures for retry

### 3. Salesforce Bulk API 2.0 Service

**Module:** `app/services/bulk_api_service.py`

**Key Methods:**
- `create_job()` - Initialize bulk ingest job
- `upload_job_data()` - Upload CSV data
- `close_job()` - Mark upload complete
- `wait_for_job_completion()` - Poll job status
- `get_job_results()` - Retrieve success/failure results
- `upsert_records()` - High-level convenience method

**Workflow:**
```python
# 1. Create Job
job = await bulk_service.create_job(
    object_name="Stripe_Customer__c",
    operation=BulkJobOperation.UPSERT,
    external_id_field="Stripe_Customer_ID__c"
)

# 2. Upload CSV Data
csv_data = convert_records_to_csv(records)
await bulk_service.upload_job_data(job["id"], csv_data)

# 3. Close Job (begin processing)
await bulk_service.close_job(job["id"])

# 4. Wait for Completion
status = await bulk_service.wait_for_job_completion(job["id"])

# 5. Retrieve Results
results = await bulk_service.get_job_results(job["id"])
```

---

## Benefits of Bulk API Processing

### 1. Reduced API Consumption
- **REST API:** 1 API call per record
- **Bulk API:** 1 API call per job (up to 10,000 records)

**Example:**
- 100 customer updates via REST = 100 API calls
- 100 customer updates via Bulk = 1 API call

### 2. Cost Optimization
- Fewer Lambda invocations (batching)
- Lower Salesforce API costs
- Better rate limit management

### 3. Improved Scalability
- Handle high-volume customer updates
- Process up to 150 million records per day
- Automatic retry and DLQ handling

### 4. Governor Limit Management
- Salesforce limit: 15,000 REST API calls/day (org-wide)
- Bulk API counted separately
- Critical events never blocked by customer updates

---

## Configuration

### Environment Variables

Add to `.env` or Lambda configuration:

```bash
# Main event queue (HIGH/MEDIUM priority)
SQS_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/.../stripe-events

# Low-priority event queue (LOW priority - Bulk API)
LOW_PRIORITY_QUEUE_URL=https://sqs.us-east-1.amazonaws.com/.../low-priority-events

# Salesforce API configuration
SALESFORCE_INSTANCE_URL=https://your-instance.salesforce.com
SALESFORCE_API_VERSION=63.0
```

### Deployment

Deploy the full stack with SAM:

```bash
cd middleware

# Build
sam build

# Deploy
sam deploy --guided \
  --parameter-overrides \
    Environment=production \
    StripeApiKey=sk_live_... \
    StripeWebhookSecretValue=whsec_... \
    SalesforceClientId=3MVG... \
    SalesforceClientSecretValue=ABC123... \
    SalesforceInstanceUrl=https://your-instance.salesforce.com
```

This will create:
- Webhook Receiver Lambda + API Gateway
- Main SQS Queue + DLQ
- **Low-Priority SQS Queue** (new)
- SQS Worker Lambda
- **Bulk Processor Lambda** (new)
- DynamoDB tables for caching
- CloudWatch log groups

---

## Monitoring

### CloudWatch Metrics

**Low-Priority Queue Depth:**
```
Namespace: AWS/SQS
Metric: ApproximateNumberOfMessagesVisible
Dimension: QueueName=low-priority-events
Alarm: > 100 messages (investigate batch processing)
```

**Bulk Processor Lambda Errors:**
```
Namespace: AWS/Lambda
Metric: Errors
Dimension: FunctionName=bulk-processor
Alarm: > 5 errors in 5 minutes
```

**Bulk Processor Duration:**
```
Namespace: AWS/Lambda
Metric: Duration
Dimension: FunctionName=bulk-processor
Alarm: > 240 seconds (approaching timeout)
```

### CloudWatch Logs

**Search for bulk job details:**
```
fields @timestamp, @message
| filter @message like /Bulk API job/
| sort @timestamp desc
| limit 20
```

**Search for bulk failures:**
```
fields @timestamp, @message, job_id, records_failed
| filter records_failed > 0
| sort @timestamp desc
```

---

## Troubleshooting

### Issue: Messages piling up in low-priority queue

**Symptoms:**
- Queue depth continuously increasing
- No bulk jobs being created

**Resolution:**
1. Check Bulk Processor Lambda logs for errors
2. Verify Salesforce OAuth credentials are valid
3. Check Bulk Processor Lambda concurrency limit
4. Increase Lambda timeout if jobs are timing out

### Issue: Bulk jobs failing

**Symptoms:**
- `numberRecordsFailed` > 0 in logs
- SQS messages retrying repeatedly

**Resolution:**
1. Check Bulk API job results for specific errors:
   ```python
   results = await bulk_service.get_job_results(job_id)
   failed = [r for r in results if not r["success"]]
   ```
2. Common errors:
   - Invalid field values (check data transformation)
   - External ID not found (ensure customer exists)
   - Required fields missing
   - Field length exceeded

### Issue: Low-priority events processed via REST API

**Symptoms:**
- `customer.updated` events in main queue logs
- Not seeing bulk job creation

**Resolution:**
1. Verify event router configuration:
   ```python
   LOW_PRIORITY_EVENTS = {"customer.updated"}
   ```
2. Check event routing logs
3. Ensure `LOW_PRIORITY_QUEUE_URL` is configured

---

## Performance Tuning

### Batch Size Tuning

**Conservative (safe):**
```yaml
BatchSize: 5
MaximumBatchingWindowInSeconds: 15
```

**Balanced (recommended):**
```yaml
BatchSize: 10
MaximumBatchingWindowInSeconds: 30
```

**Aggressive (high volume):**
```yaml
BatchSize: 10
MaximumBatchingWindowInSeconds: 60
```

### Concurrency Control

**Low Volume (< 1000 events/day):**
```yaml
ReservedConcurrentExecutions: 1
```

**Medium Volume (1000-10,000 events/day):**
```yaml
ReservedConcurrentExecutions: 2-3
```

**High Volume (> 10,000 events/day):**
```yaml
ReservedConcurrentExecutions: 5-10
```

---

## API Reference

### Event Router

```python
from app.handlers.event_router import get_event_router

router = get_event_router()

# Route event
result = await router.route_event({
    "id": "evt_123",
    "type": "customer.updated",
    "data": {"object": {...}}
})

# Returns:
# {
#   "status": "queued",
#   "priority": "low",
#   "event_type": "customer.updated",
#   "sqs_message_id": "..."
# }
```

### Bulk API Service

```python
from app.services.bulk_api_service import get_bulk_api_service

bulk_service = get_bulk_api_service()

# Upsert records
result = await bulk_service.upsert_records(
    object_name="Contact",
    records=[
        {
            "Stripe_Customer_ID__c": "cus_123",
            "Email": "user@example.com",
            "FirstName": "John",
            "LastName": "Doe"
        }
    ],
    external_id_field="Stripe_Customer_ID__c",
    wait_for_completion=True
)

# Returns:
# {
#   "job_id": "7504W00000D...",
#   "status": {
#     "state": "JobComplete",
#     "numberRecordsProcessed": 1,
#     "numberRecordsFailed": 0
#   },
#   "results": [...]
# }
```

---

## Testing

### Local Testing

Test bulk processor with mock events:

```bash
cd middleware

# Run bulk processor locally
python bulk_processor.py
```

### Integration Testing

```python
import pytest
from bulk_processor import process_sqs_batch

@pytest.mark.asyncio
async def test_bulk_customer_processing():
    event = {
        "Records": [
            {
                "messageId": "test-1",
                "body": json.dumps({
                    "id": "evt_test_123",
                    "type": "customer.updated",
                    "data": {
                        "object": {
                            "id": "cus_test_123",
                            "email": "test@example.com"
                        }
                    }
                })
            }
        ]
    }

    failures = await process_sqs_batch(event, mock_context)
    assert len(failures) == 0
```

---

## Cost Analysis

### REST API vs. Bulk API Cost Comparison

**Scenario:** 10,000 customer updates per day

**REST API Approach:**
- Lambda invocations: 10,000
- Salesforce API calls: 10,000
- Cost: Higher Lambda execution time + API limit consumption

**Bulk API Approach:**
- Lambda invocations: ~1,000 (batch of 10)
- Bulk API jobs: ~1,000
- Salesforce API calls: ~1,000 (Bulk API)
- Cost: **90% reduction** in Lambda + API calls

**Winner:** Bulk API for high-volume non-urgent events

---

## Migration Guide

### Migrating Existing Events to Bulk Processing

1. **Identify Low-Priority Events:**
   - Review event types
   - Classify by urgency
   - Add to `LOW_PRIORITY_EVENTS` set

2. **Update Event Handlers:**
   - Ensure handlers work with batch data
   - Test transformation logic

3. **Deploy Infrastructure:**
   - Deploy SAM template with new queue
   - Verify queue creation

4. **Monitor Migration:**
   - Watch queue depths
   - Check bulk job success rates
   - Verify Salesforce data accuracy

5. **Rollback Plan:**
   - Remove event from `LOW_PRIORITY_EVENTS`
   - Events will route to REST API automatically

---

## Best Practices

1. **Event Classification:**
   - Be conservative with HIGH priority
   - Most events should be MEDIUM
   - Only use LOW for true metadata updates

2. **Batch Size:**
   - Start small (5-10 messages)
   - Increase based on volume
   - Monitor job completion times

3. **Error Handling:**
   - Always enable partial batch failures
   - Monitor DLQ regularly
   - Investigate recurring failures

4. **Monitoring:**
   - Set up CloudWatch alarms
   - Review logs daily
   - Track bulk job success rates

5. **Testing:**
   - Test with production-like volumes
   - Verify data transformations
   - Check edge cases (missing fields, etc.)

---

## References

- [Salesforce Bulk API 2.0 Documentation](https://developer.salesforce.com/docs/atlas.en-us.api_asynch.meta/api_asynch/)
- [AWS Lambda SQS Event Source](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html)
- [SQS Partial Batch Failures](https://docs.aws.amazon.com/lambda/latest/dg/with-sqs.html#services-sqs-batchfailurereporting)
- [Technical Requirements](../requirements/technical.md)
