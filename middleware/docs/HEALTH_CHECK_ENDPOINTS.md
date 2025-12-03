# Health Check Endpoints

## Overview

The middleware provides comprehensive health check and monitoring endpoints that verify all services including the new Bulk API and batch accumulator components.

## Endpoints

### 1. Basic Health Check

**Endpoint:** `GET /health`

**Purpose:** Quick check that the application is running

**Response (200 OK):**
```json
{
  "status": "healthy",
  "timestamp": "2024-11-15T10:30:00.000Z",
  "version": "1.0.0"
}
```

**Use Case:** Load balancer health checks, uptime monitoring

---

### 2. Readiness Check (Comprehensive)

**Endpoint:** `GET /health/ready`

**Purpose:** Verify all dependencies are available and healthy

**Checks Performed:**
- ✅ DynamoDB Cache (OAuth tokens, idempotency)
- ✅ Batch Accumulator (DynamoDB table for batching)
- ✅ Main SQS Queue (HIGH/MEDIUM priority events)
- ✅ Low-Priority SQS Queue (LOW priority events for Bulk API)
- ✅ Salesforce OAuth (authentication status)
- ✅ Rate Limiter (DynamoDB connectivity)

**Response (200 OK - All Healthy):**
```json
{
  "status": "ready",
  "timestamp": "2024-11-15T10:30:00.000Z",
  "dependencies": {
    "dynamodb_cache": {
      "status": "healthy",
      "connected": true,
      "table_name": "salesforce-stripe-cache"
    },
    "batch_accumulator": {
      "status": "healthy",
      "table_name": "stripe-event-batches",
      "active_batches": 1,
      "stats": {
        "batches": {
          "customer_update": {
            "window_id": "2024-11-15T10:30:00Z",
            "record_count": 145,
            "window_age_seconds": 12.5,
            "ready": false
          }
        }
      }
    },
    "sqs_main_queue": {
      "status": "healthy",
      "queue_url": "https://sqs.us-east-1.amazonaws.com/.../stripe-events",
      "approximate_messages": "5",
      "type": "main (HIGH/MEDIUM priority)"
    },
    "sqs_low_priority_queue": {
      "status": "healthy",
      "queue_url": "https://sqs.us-east-1.amazonaws.com/.../low-priority-events",
      "approximate_messages": "12",
      "type": "low-priority (Bulk API)"
    },
    "salesforce_oauth": {
      "status": "healthy",
      "authenticated": true,
      "instance_url": "https://your-instance.salesforce.com"
    },
    "rate_limiter": {
      "status": "healthy",
      "service": "initialized",
      "tiers": ["per-second", "per-minute", "per-day"]
    }
  },
  "summary": {
    "total_checks": 6,
    "healthy": 6,
    "unhealthy": 0
  }
}
```

**Response (503 Service Unavailable - Some Unhealthy):**
```json
{
  "status": "not_ready",
  "timestamp": "2024-11-15T10:30:00.000Z",
  "dependencies": {
    "dynamodb_cache": {
      "status": "healthy",
      "connected": true,
      "table_name": "salesforce-stripe-cache"
    },
    "batch_accumulator": {
      "status": "unhealthy",
      "error": "Table not found: stripe-event-batches"
    },
    "sqs_main_queue": {
      "status": "healthy",
      "queue_url": "https://sqs.us-east-1.amazonaws.com/.../stripe-events",
      "approximate_messages": "5",
      "type": "main (HIGH/MEDIUM priority)"
    },
    "sqs_low_priority_queue": {
      "status": "unhealthy",
      "error": "Queue does not exist"
    },
    "salesforce_oauth": {
      "status": "unhealthy",
      "authenticated": false,
      "error": "Invalid client credentials"
    },
    "rate_limiter": {
      "status": "healthy",
      "service": "initialized",
      "tiers": ["per-second", "per-minute", "per-day"]
    }
  },
  "summary": {
    "total_checks": 6,
    "healthy": 3,
    "unhealthy": 3
  }
}
```

**Use Case:** Kubernetes readiness probes, deployment validation

---

### 3. Liveness Check

**Endpoint:** `GET /health/live`

**Purpose:** Verify application process is alive (doesn't check dependencies)

**Response (200 OK):**
```json
{
  "status": "alive",
  "timestamp": "2024-11-15T10:30:00.000Z"
}
```

**Use Case:** Kubernetes liveness probes, auto-restart triggers

---

### 4. Metrics Endpoint

**Endpoint:** `GET /metrics`

**Purpose:** Detailed operational metrics for monitoring and alerting

**Metrics Provided:**
- Application info (name, version, environment)
- Main queue statistics (messages, in-flight, delayed)
- Low-priority queue statistics
- Batch accumulator status (active batches, thresholds)
- Rate limiter configuration

**Response (200 OK):**
```json
{
  "timestamp": "2024-11-15T10:30:00.000Z",
  "application": {
    "name": "Salesforce-Stripe Middleware",
    "version": "1.0.0",
    "environment": "production"
  },
  "queues": {
    "main_queue": {
      "url": "https://sqs.us-east-1.amazonaws.com/.../stripe-events",
      "type": "HIGH/MEDIUM priority (REST API)",
      "approximate_messages": 5,
      "approximate_messages_not_visible": 2,
      "approximate_messages_delayed": 0
    },
    "low_priority_queue": {
      "url": "https://sqs.us-east-1.amazonaws.com/.../low-priority-events",
      "type": "LOW priority (Bulk API)",
      "approximate_messages": 145,
      "approximate_messages_not_visible": 10,
      "approximate_messages_delayed": 0
    }
  },
  "batch_accumulator": {
    "table_name": "stripe-event-batches",
    "size_threshold": 200,
    "time_threshold_seconds": 30,
    "active_batches": 1,
    "batches": {
      "customer_update": {
        "window_id": "2024-11-15T10:30:00Z",
        "record_count": 145,
        "window_age_seconds": 12.5,
        "ready": false
      }
    }
  },
  "rate_limiter": {
    "status": "enabled",
    "limits": {
      "per_second": 10,
      "per_minute": 250,
      "per_day": 15000
    }
  }
}
```

**Use Case:** CloudWatch dashboards, Grafana, Prometheus scraping

---

## Kubernetes/Container Configuration

### Liveness Probe

```yaml
livenessProbe:
  httpGet:
    path: /health/live
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

**Purpose:** Restart container if unresponsive

### Readiness Probe

```yaml
readinessProbe:
  httpGet:
    path: /health/ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 5
  failureThreshold: 2
```

**Purpose:** Remove from load balancer if dependencies unavailable

---

## CloudWatch Alarms

### Health Check Alarm

Monitor the `/health/ready` endpoint and alert if unhealthy:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name middleware-unhealthy \
  --alarm-description "Middleware readiness check failing" \
  --metric-name HealthCheckStatus \
  --namespace Custom/Middleware \
  --statistic Average \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 1 \
  --comparison-operator LessThanThreshold
```

### Queue Depth Alarms

**Main Queue:**
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name main-queue-depth-high \
  --metric-name ApproximateNumberOfMessagesVisible \
  --namespace AWS/SQS \
  --dimensions Name=QueueName,Value=stripe-events \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold
```

**Low-Priority Queue:**
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name low-priority-queue-depth-high \
  --metric-name ApproximateNumberOfMessagesVisible \
  --namespace AWS/SQS \
  --dimensions Name=QueueName,Value=low-priority-events \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 500 \
  --comparison-operator GreaterThanThreshold
```

---

## Testing Health Checks

### Local Testing

```bash
# Basic health
curl http://localhost:8000/health

# Readiness check
curl http://localhost:8000/health/ready

# Liveness check
curl http://localhost:8000/health/live

# Metrics
curl http://localhost:8000/metrics | jq .
```

### Production Testing

```bash
# Get webhook URL from deployment
WEBHOOK_URL=$(aws cloudformation describe-stacks \
  --stack-name salesforce-stripe-middleware-production \
  --query "Stacks[0].Outputs[?OutputKey=='WebhookUrl'].OutputValue" \
  --output text)

# Extract base URL
BASE_URL=$(echo $WEBHOOK_URL | sed 's|/webhook/stripe||')

# Test health check
curl $BASE_URL/health

# Test readiness (should return 200 if all services healthy)
curl -v $BASE_URL/health/ready

# Test metrics
curl $BASE_URL/metrics | jq .
```

---

## Monitoring Dashboard Setup

### CloudWatch Dashboard (JSON)

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Lambda", "Invocations", {"stat": "Sum"}],
          [".", "Errors", {"stat": "Sum"}],
          [".", "Duration", {"stat": "Average"}]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "us-east-1",
        "title": "Lambda Metrics (All 3 Functions)"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/SQS", "ApproximateNumberOfMessagesVisible",
           {"dimensions": {"QueueName": "stripe-events"}, "label": "Main Queue"}],
          ["...",
           {"dimensions": {"QueueName": "low-priority-events"}, "label": "Low-Priority Queue"}],
          ["...",
           {"dimensions": {"QueueName": "stripe-events-dlq"}, "label": "DLQ"}]
        ],
        "period": 60,
        "stat": "Average",
        "region": "us-east-1",
        "title": "Queue Depths"
      }
    }
  ]
}
```

### Grafana Dashboard

Example Prometheus query for Grafana:

```promql
# Queue depth
sqs_approximate_number_of_messages_visible{queue_name="stripe-events"}

# Lambda errors
aws_lambda_errors_sum{function_name=~".*webhook.*|.*sqs-worker.*|.*bulk-processor.*"}

# Health check status
up{job="middleware-health-check"}
```

---

## Troubleshooting

### All Dependencies Showing Unhealthy

**Possible Causes:**
- AWS credentials not configured
- Wrong region
- Network connectivity issues
- Services not deployed yet

**Solution:**
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify region
echo $AWS_REGION

# Test connectivity
aws sqs list-queues
aws dynamodb list-tables
```

### Batch Accumulator Unhealthy

**Error:** `Table not found: stripe-event-batches`

**Solution:**
```bash
# Deploy the stack (includes all tables)
sam deploy

# Verify table exists
aws dynamodb describe-table --table-name stripe-event-batches
```

### Low-Priority Queue Unhealthy

**Error:** `Queue does not exist`

**Solution:**
Check that the SAM template includes the `LowPriorityEventQueue` resource and redeploy.

### Salesforce OAuth Unhealthy

**Error:** `Invalid client credentials`

**Solution:**
```bash
# Verify Secrets Manager has correct values
aws secretsmanager get-secret-value \
  --secret-id salesforce-stripe-middleware-salesforce-client-secret \
  --query SecretString --output text | jq .

# Update if needed
aws secretsmanager update-secret \
  --secret-id salesforce-stripe-middleware-salesforce-client-secret \
  --secret-string '{"client_id":"3MVG...","client_secret":"ABC...","instance_url":"https://login.salesforce.com"}'
```

---

## Summary

The health check system now monitors **all 6 critical services**:

| Service | Endpoint | What It Checks |
|---------|----------|----------------|
| **DynamoDB Cache** | `/health/ready` | OAuth token storage, idempotency |
| **Batch Accumulator** | `/health/ready` | Event batching table, active batches |
| **Main SQS Queue** | `/health/ready` | HIGH/MEDIUM priority events |
| **Low-Priority Queue** | `/health/ready` | LOW priority events (Bulk API) |
| **Salesforce OAuth** | `/health/ready` | Authentication status |
| **Rate Limiter** | `/health/ready` | DynamoDB connectivity |

Use `/health/ready` for deployment validation and `/metrics` for operational monitoring!
