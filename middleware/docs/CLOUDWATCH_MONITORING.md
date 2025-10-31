# CloudWatch Monitoring & Alerting

## Overview

Comprehensive monitoring and alerting for the 3-Lambda Stripe-Salesforce middleware architecture using CloudWatch Dashboards, Alarms, and Logs.

---

## Quick Deploy

### 1. Deploy Stack (includes 13 CloudWatch Alarms)

```bash
cd middleware
sam deploy --guided
```

**Alarms Deployed Automatically:**
- ✅ Lambda errors (all 3 functions)
- ✅ Lambda duration approaching timeout
- ✅ Lambda throttles
- ✅ Queue depths (main + low-priority)
- ✅ Dead Letter Queue messages
- ✅ Old messages in queue
- ✅ API Gateway 4XX/5XX errors

### 2. Deploy Dashboard

```bash
./scripts/deploy-dashboard.sh salesforce-stripe-middleware-dev us-east-1
```

**Output:**
```
📊 Dashboard Name: salesforce-stripe-middleware-dev-middleware-dashboard
🔗 Dashboard URL: https://us-east-1.console.aws.amazon.com/cloudwatch/...
```

---

## CloudWatch Dashboard

### What's Included

The dashboard provides a comprehensive view of the entire system:

| Widget | Metrics | Purpose |
|--------|---------|---------|
| **Lambda Invocations** | All 3 functions | Track webhook processing load |
| **Lambda Errors** | Errors by function | Identify failing components |
| **Lambda Duration** | Average execution time | Monitor performance |
| **Lambda Concurrent Executions** | Active instances | Track scaling |
| **Lambda Throttles** | Throttled invocations | Identify capacity issues |
| **Main Queue Depth** | Messages in main queue | Monitor HIGH/MEDIUM priority backlog |
| **Low-Priority Queue Depth** | Messages for Bulk API | Monitor batch accumulation |
| **Dead Letter Queue** | Failed messages | Track permanent failures |
| **Message Age** | Oldest message age | Detect processing delays |
| **API Gateway Metrics** | Requests, errors, latency | Monitor webhook endpoint |
| **DynamoDB Capacity** | Consumed capacity units | Track database usage |
| **Recent Errors** | Log query for errors | Quick error diagnosis |

### Screenshot

The dashboard layout:

```
┌─────────────────────────────────────────────────────────┐
│ Stripe-Salesforce Middleware - 3-Lambda Architecture   │
├─────────────────────────────┬───────────────────────────┤
│ Lambda Invocations          │ Lambda Errors            │
│ (all 3 functions)           │ (color-coded)            │
├─────────────────────────────┴───────────────────────────┤
│ Duration │ Concurrent Exec │ Throttles                 │
├──────────┴──────────────────┴───────────────────────────┤
│ Main Queue │ Low-Pri Queue │ DLQ                       │
├────────────┴───────────────┴───────────────────────────┤
│ Message Age                 │ API Gateway Metrics      │
├─────────────────────────────┴───────────────────────────┤
│ DynamoDB Capacity (cache + batch accumulator)          │
├─────────────────────────────────────────────────────────┤
│ Recent Lambda Errors (log query)                       │
└─────────────────────────────────────────────────────────┘
```

---

## CloudWatch Alarms (13 Total)

All alarms are deployed automatically via the SAM template.

### Lambda Alarms

#### 1. Webhook Receiver Errors
- **Alarm:** `${StackName}-webhook-errors`
- **Threshold:** > 10 errors in 5 minutes
- **Action:** Indicates webhook processing failures
- **Response:** Check webhook logs, verify Stripe signature

#### 2. SQS Worker Errors
- **Alarm:** `${StackName}-sqs-worker-errors`
- **Threshold:** > 10 errors in 5 minutes
- **Action:** Indicates REST API processing failures
- **Response:** Check Salesforce connectivity, rate limits

#### 3. Bulk Processor Errors
- **Alarm:** `${StackName}-bulk-processor-errors`
- **Threshold:** > 5 errors in 5 minutes
- **Action:** Indicates Bulk API processing failures
- **Response:** Check batch accumulator, Bulk API job status

#### 4. Webhook Duration
- **Alarm:** `${StackName}-webhook-duration`
- **Threshold:** > 8 seconds average (timeout: 10s)
- **Action:** Webhook approaching timeout
- **Response:** Optimize signature verification, check SQS latency

#### 5. SQS Worker Duration
- **Alarm:** `${StackName}-sqs-worker-duration`
- **Threshold:** > 75 seconds average (timeout: 90s)
- **Action:** REST API calls taking too long
- **Response:** Check Salesforce API latency, optimize queries

#### 6. Bulk Processor Duration
- **Alarm:** `${StackName}-bulk-processor-duration`
- **Threshold:** > 240 seconds average (timeout: 300s)
- **Action:** Bulk API jobs taking too long
- **Response:** Reduce batch size or increase timeout

#### 7. Lambda Throttles
- **Alarm:** `${StackName}-lambda-throttles`
- **Threshold:** > 5 throttles total (all functions) in 5 minutes
- **Action:** Functions hitting concurrency limits
- **Response:** Increase reserved concurrency or account limits

### Queue Alarms

#### 8. Main Queue Depth
- **Alarm:** `${StackName}-queue-depth`
- **Threshold:** > 100 messages for 10 minutes
- **Action:** Backlog building up for HIGH/MEDIUM priority
- **Response:** Check SQS Worker function, increase concurrency

#### 9. Low-Priority Queue Depth
- **Alarm:** `${StackName}-low-priority-queue-depth`
- **Threshold:** > 500 messages for 10 minutes
- **Action:** Backlog building up for Bulk API processing
- **Response:** Check Bulk Processor function, verify batch accumulator

#### 10. Dead Letter Queue
- **Alarm:** `${StackName}-dlq-messages`
- **Threshold:** ≥ 1 message
- **Action:** Events permanently failed after retries
- **Response:** Investigate DLQ messages, fix root cause

#### 11. Old Messages (Main Queue)
- **Alarm:** `${StackName}-old-messages`
- **Threshold:** Oldest message > 5 minutes for 10 minutes
- **Action:** Messages stuck in queue
- **Response:** Check SQS Worker errors, scaling issues

#### 12. Old Messages (Low-Priority Queue)
- **Alarm:** `${StackName}-low-priority-old-messages`
- **Threshold:** Oldest message > 60 seconds for 3 minutes
- **Action:** Batch not submitting (should be 30s window)
- **Response:** Check Bulk Processor logs, batch accumulator

### API Gateway Alarms

#### 13. API Gateway 5XX Errors
- **Alarm:** `${StackName}-api-gateway-5xx`
- **Threshold:** > 10 5XX errors in 5 minutes
- **Action:** Server-side errors at webhook endpoint
- **Response:** Check Lambda errors, API Gateway logs

#### 14. API Gateway 4XX Errors
- **Alarm:** `${StackName}-api-gateway-4xx`
- **Threshold:** > 50 4XX errors for 10 minutes
- **Action:** Client errors (auth, validation)
- **Response:** Check Stripe signature, webhook configuration

---

## Alarm Actions (SNS Integration)

### Add Email/SMS Notifications

Update alarms to send notifications:

```bash
# Create SNS topic
aws sns create-topic --name middleware-alerts --region us-east-1

# Subscribe email
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:123456789:middleware-alerts \
  --protocol email \
  --notification-endpoint your-email@example.com

# Update alarm with SNS action
aws cloudwatch put-metric-alarm \
  --alarm-name salesforce-stripe-middleware-dev-webhook-errors \
  --alarm-actions arn:aws:sns:us-east-1:123456789:middleware-alerts \
  ...
```

### Add Slack/PagerDuty Integration

Use AWS Chatbot or Lambda webhook:

```bash
# Via AWS Chatbot (Slack)
aws chatbot create-slack-channel-configuration \
  --configuration-name middleware-slack \
  --iam-role-arn arn:aws:iam::123456789:role/chatbot-role \
  --slack-team-id T123456 \
  --slack-channel-id C123456 \
  --sns-topic-arns arn:aws:sns:us-east-1:123456789:middleware-alerts
```

---

## CloudWatch Logs Insights

### Useful Queries

#### 1. Recent Errors (All 3 Lambdas)

```sql
fields @timestamp, @message, @logStream
| filter @message like /ERROR/
| sort @timestamp desc
| limit 50
```

#### 2. Batch Accumulator Stats

```sql
fields @timestamp, @message
| filter @message like /Batch accumulator stats/
| parse @message /record_count: (?<count>\d+)/
| parse @message /window_age_seconds: (?<age>[\d.]+)/
| stats max(count) as max_batch, avg(age) as avg_age
```

#### 3. Bulk API Job Status

```sql
fields @timestamp, @message
| filter @message like /Bulk API job/
| parse @message /job_id: (?<job_id>[^\s,]+)/
| parse @message /records_processed: (?<processed>\d+)/
| parse @message /records_failed: (?<failed>\d+)/
| stats count() by job_id, processed, failed
```

#### 4. SQS Processing Latency

```sql
fields @timestamp, @message
| filter @message like /Processing.*event/
| parse @message /Duration: (?<duration>\d+)/
| stats avg(duration), p50(duration), p99(duration)
```

#### 5. Rate Limit Events

```sql
fields @timestamp, @message
| filter @message like /rate limit/
| count() by bin(5m)
```

---

## Metric Filters & Custom Metrics

### Create Custom Metrics from Logs

#### 1. Track Bulk API Success Rate

```bash
aws logs put-metric-filter \
  --log-group-name /aws/lambda/bulk-processor \
  --filter-name BulkAPISuccessRate \
  --filter-pattern '[timestamp, request_id, level=INFO, msg="Bulk API job completed", ...]' \
  --metric-transformations \
    metricName=BulkAPIJobsCompleted,\
    metricNamespace=Custom/Middleware,\
    metricValue=1
```

#### 2. Track Batch Sizes

```bash
aws logs put-metric-filter \
  --log-group-name /aws/lambda/bulk-processor \
  --filter-name BatchSize \
  --filter-pattern '[..., record_count_label="record_count:", record_count]' \
  --metric-transformations \
    metricName=BatchRecordCount,\
    metricNamespace=Custom/Middleware,\
    metricValue=$record_count
```

---

## Performance Tuning Based on Metrics

### High Queue Depth

**Symptom:** Main queue depth > 100 for extended periods

**Solutions:**
1. Increase SQS Worker concurrency:
   ```yaml
   ReservedConcurrentExecutions: 20  # Up from 10
   ```
2. Increase batch size:
   ```yaml
   BatchSize: 10  # Up from 5
   ```
3. Optimize Salesforce API calls (batch upserts)

### High Lambda Duration

**Symptom:** Functions approaching timeout

**Solutions:**
1. Increase memory (improves CPU):
   ```yaml
   MemorySize: 1024  # Up from 512
   ```
2. Optimize code (reduce API calls, cache more)
3. Increase timeout if justified

### Batch Not Submitting

**Symptom:** Low-priority queue depth growing, old messages alarm

**Solutions:**
1. Reduce batch accumulator thresholds:
   ```python
   self.size_threshold = 100  # Down from 200
   self.time_threshold = 15   # Down from 30
   ```
2. Check Bulk Processor logs for errors
3. Verify batch accumulator DynamoDB table exists

---

## Cost Optimization

### CloudWatch Costs

| Component | Free Tier | Cost After Free Tier |
|-----------|-----------|---------------------|
| **Alarms** | 10 alarms | $0.10/alarm/month |
| **Dashboard** | 3 dashboards | $3/dashboard/month |
| **Logs Ingestion** | 5 GB | $0.50/GB ingested |
| **Logs Storage** | - | $0.03/GB stored |
| **Insights Queries** | - | $0.005/GB scanned |

### Reduce Costs

1. **Set log retention:**
   ```yaml
   RetentionInDays: 7  # Default in template
   ```

2. **Use sampling for high-volume logs:**
   ```python
   if random.random() < 0.1:  # Sample 10%
       logger.debug(...)
   ```

3. **Archive old logs to S3:**
   ```bash
   aws logs create-export-task \
     --log-group-name /aws/lambda/webhook \
     --from-time 1234567890000 \
     --to-time 1234567899999 \
     --destination s3://my-log-archive
   ```

---

## Troubleshooting

### Dashboard Not Showing Data

**Issue:** Widgets show "No data available"

**Solutions:**
1. Wait 5-10 minutes for metrics to populate
2. Verify stack is deployed and running
3. Check metric dimensions match function names
4. Trigger test webhook to generate metrics

### Alarms in INSUFFICIENT_DATA State

**Issue:** Alarms show gray "INSUFFICIENT_DATA"

**Solutions:**
1. Wait for metrics to populate (5-15 minutes)
2. Trigger events to generate metrics
3. Check `TreatMissingData: notBreaching` setting

### High Alarm Noise

**Issue:** Too many false positive alarms

**Solutions:**
1. Increase thresholds:
   ```yaml
   Threshold: 20  # Up from 10
   ```
2. Increase evaluation periods:
   ```yaml
   EvaluationPeriods: 3  # Up from 1
   ```
3. Use composite alarms (AND/OR logic)

---

## Best Practices

1. **Review Alarms Weekly**
   - Check alarm history
   - Adjust thresholds based on actual load
   - Remove noisy alarms

2. **Set Up SNS Notifications**
   - Critical alarms → PagerDuty/SMS
   - Warning alarms → Email/Slack
   - Info alarms → Dashboard only

3. **Use Log Insights Regularly**
   - Save common queries
   - Schedule weekly error reviews
   - Track trends over time

4. **Monitor Costs**
   - Check CloudWatch billing dashboard
   - Set up billing alarms
   - Archive old logs

5. **Test Alarm Response**
   - Trigger test failures monthly
   - Verify notifications work
   - Document runbooks

---

## Summary

### Deployment Checklist

- ✅ Deploy stack with `sam deploy` (includes 13 alarms)
- ✅ Deploy dashboard with `./scripts/deploy-dashboard.sh`
- ✅ Configure SNS topic for notifications
- ✅ Add email/Slack subscriptions
- ✅ Test alarms with sample failures
- ✅ Bookmark dashboard URL
- ✅ Set up weekly alarm reviews

### Quick Links

**Dashboard:**
```
https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards:name=${STACK_NAME}-middleware-dashboard
```

**Alarms:**
```
https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#alarmsV2:?search=${STACK_NAME}
```

**Logs:**
```
https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#logsV2:log-groups
```

---

You now have comprehensive monitoring for all 3 Lambdas, 3 SQS queues, API Gateway, and DynamoDB! 🎉
