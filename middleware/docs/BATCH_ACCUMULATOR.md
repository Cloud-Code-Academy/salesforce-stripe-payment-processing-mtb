# Batch Accumulator - Sliding Window Implementation

## Overview

The **Batch Accumulator** is a DynamoDB-based service that implements a **sliding window algorithm** for efficient batch processing of low-priority events. It ensures that events are batched together for optimal Salesforce Bulk API usage while maintaining low latency.

## Location

**Service Implementation:** [app/services/batch_accumulator.py](../app/services/batch_accumulator.py)

**Usage in Bulk Processor:** [bulk_processor.py](../bulk_processor.py)

## How It Works

### Sliding Window Strategy

The batch accumulator uses a **time and size-based sliding window** approach:

```
┌─────────────────────────────────────────────────────────┐
│ Batch Accumulation Window (DynamoDB)                     │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  Event 1 arrives → Add to window (count: 1)             │
│  Event 2 arrives → Add to window (count: 2)             │
│  Event 3 arrives → Add to window (count: 3)             │
│                                                           │
│  ... continues until ...                                 │
│                                                           │
│  ⚙️ THRESHOLD HIT:                                       │
│     • Size reaches 200 records → SUBMIT BATCH           │
│     • Time reaches 30 seconds → SUBMIT BATCH            │
│                                                           │
│  📤 Batch submitted to Bulk API → ✅                     │
│  🔄 New window created for next batch                   │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

### Thresholds

The batch accumulator has two thresholds that trigger submission:

| Threshold | Value | Reason |
|-----------|-------|--------|
| **Size Threshold** | 200 records | Optimizes Salesforce Bulk API payload size |
| **Time Threshold** | 30 seconds | Prevents events from waiting too long |

**Submission Logic:** `batch_ready = (record_count >= 200) OR (window_age >= 30 seconds)`

## Architecture

### DynamoDB Table Structure

**Table Name:** `stripe-event-batches`

**Primary Key (PK):** `batch_type` (e.g., "customer_update")
**Sort Key (SK):** `window_id` (ISO timestamp when window created)

**Attributes:**

```python
{
    "pk": "customer_update",                    # Batch type
    "sk": "2024-11-15T10:30:00Z",              # Window ID (creation timestamp)
    "created_at": "2024-11-15T10:30:00Z",      # When window was created
    "window_start": "2024-11-15T10:30:00Z",    # Window start time (for age calculation)
    "events": [                                  # List of accumulated events
        {
            "id": "evt_123",
            "type": "customer.updated",
            "data": {...},
            ...
        },
        {
            "id": "evt_124",
            "type": "customer.updated",
            "data": {...},
            ...
        }
    ],
    "record_count": 145,                        # Number of events in batch
    "ttl": 1731696600                          # Unix timestamp (24-hour expiration)
}
```

### API Methods

#### `add_event(batch_type, event)`

Adds a single event to the accumulator.

**Returns:**
```python
{
    "added": True,
    "batch_ready": False,           # Ready for submission?
    "batch_id": "2024-11-15T10:30:00Z",
    "record_count": 145,
    "window_age_seconds": 12.5
}
```

**Example:**
```python
accumulator = get_batch_accumulator()

result = await accumulator.add_event(
    batch_type=BatchType.CUSTOMER_UPDATE,
    event=stripe_event.dict()
)

if result["batch_ready"]:
    print(f"Batch ready! {result['record_count']} records to process")
```

#### `get_batch(batch_type)`

Retrieves accumulated batch if ready for submission.

**Returns:**
```python
{
    "batch_id": "2024-11-15T10:30:00Z",
    "batch_type": "customer_update",
    "events": [...],                # All accumulated events
    "record_count": 200,
    "window_age_seconds": 31
}
```

Or `None` if batch not ready yet.

#### `submit_batch(batch_type)`

Marks batch as submitted and clears for next cycle.

**Returns:** `True` on success, `False` on failure

#### `get_batch_stats()`

Returns statistics about all batches.

**Returns:**
```python
{
    "batches": {
        "customer_update": {
            "window_id": "2024-11-15T10:30:00Z",
            "record_count": 145,
            "window_age_seconds": 12.5,
            "ready": False
        }
    }
}
```

## Integration with Bulk Processor

The bulk processor uses the batch accumulator as follows:

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ SQS Message arrives (customer.updated event)                 │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────────┐
        │ Parse Stripe Event         │
        └────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────────────────────┐
        │ Add to Batch Accumulator (DynamoDB)    │
        │                                         │
        │ • Store event in window                │
        │ • Increment record count               │
        │ • Calculate window age                 │
        └────────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────────────────┐
        │ Check if Batch Ready?              │
        │ (size >= 200 OR time >= 30 sec)    │
        └────┬───────────────────────────┬───┘
             │                           │
           YES                          NO
             │                           │
             ▼                           ▼
    ┌──────────────────┐     ┌───────────────────┐
    │ Retrieve Batch   │     │ Continue waiting  │
    │ (200+ records)   │     │ for more events   │
    └──────────┬───────┘     └───────────────────┘
               │
               ▼
    ┌──────────────────────────┐
    │ Transform to Salesforce  │
    │ records (CSV format)     │
    └──────────┬───────────────┘
               │
               ▼
    ┌──────────────────────────┐
    │ Submit to Bulk API 2.0   │
    │ (single job for 200+     │
    │  records vs 200 REST     │
    │  API calls)              │
    └──────────┬───────────────┘
               │
               ▼
    ┌──────────────────────────┐
    │ Clear batch accumulator  │
    │ Start new window         │
    └──────────────────────────┘
```

### Code Example

```python
# In bulk_processor.py

batch_accumulator = get_batch_accumulator()

for stripe_event in stripe_events:
    if stripe_event.type == "customer.updated":

        # Step 1: Add event to accumulator
        result = await batch_accumulator.add_event(
            batch_type=BatchType.CUSTOMER_UPDATE,
            event=stripe_event.dict()
        )

        logger.info(
            f"Event added to batch",
            extra={
                "record_count": result["record_count"],
                "window_age": result["window_age_seconds"],
                "batch_ready": result["batch_ready"]
            }
        )

        # Step 2: If batch is ready, process it
        if result["batch_ready"]:
            batch = await batch_accumulator.get_batch(BatchType.CUSTOMER_UPDATE)

            # Process the accumulated events via Bulk API
            await process_customer_updates_bulk(batch["events"])

            # Clear for next batch
            await batch_accumulator.submit_batch(BatchType.CUSTOMER_UPDATE)

            logger.info(
                f"Batch processed and cleared",
                extra={"record_count": batch["record_count"]}
            )
```

## Cost & Performance Benefits

### REST API vs. Bulk API (with Batch Accumulator)

**Scenario:** 1000 customer updates over 5 minutes

#### Without Batch Accumulator (REST API Only)
```
1000 events = 1000 REST API calls
Cost: High API consumption, hits rate limits faster
Latency: Each event processed individually (slower for large batches)
```

#### With Batch Accumulator (Bulk API)
```
1000 events = 5 Bulk API jobs (200 events per job)
Cost: 5 API calls instead of 1000 = 99.5% reduction!
Latency: Events wait max 30 seconds (acceptable for non-urgent data)
```

**API Call Reduction:** From 1,000 to 5 = **99.5% reduction** 🎉

## Monitoring

### CloudWatch Metrics

```python
# Check batch stats
stats = await batch_accumulator.get_batch_stats()

# Example output
{
    "batches": {
        "customer_update": {
            "window_id": "2024-11-15T10:30:00Z",
            "record_count": 145,           # How full the batch is
            "window_age_seconds": 12.5,    # How long accumulating
            "ready": False                 # Ready for submission?
        }
    }
}
```

### Logging

Every operation is logged with context:

```
[INFO] Event added to batch accumulator
  event_id: evt_123
  batch_type: customer_update
  record_count: 145/200
  window_age_seconds: 12.5/30
  batch_ready: False

[INFO] Batch ready for submission - triggering Bulk API
  batch_type: customer_update
  record_count: 200

[INFO] Batch processed and cleared
  batch_type: customer_update
  record_count: 200
  bulk_api_job_id: 7504W00000D...
```

## Tuning Parameters

You can customize the thresholds in [batch_accumulator.py](../app/services/batch_accumulator.py):

```python
class BatchAccumulator:
    def __init__(self):
        self.size_threshold = 200      # Adjust based on volume
        self.time_threshold = 30       # Adjust based on latency requirements
```

### Tuning Guide

| Scenario | Size Threshold | Time Threshold | Rationale |
|----------|---|---|---|
| **High Volume** (>1000 events/day) | 300-500 | 60 seconds | Maximize batching |
| **Medium Volume** (100-1000 events/day) | 200 | 30 seconds | Balanced (default) |
| **Low Volume** (<100 events/day) | 50 | 5 seconds | Minimize latency |

## Edge Cases

### What if a batch is never submitted?

**Problem:** Events accumulate but never reach thresholds (e.g., only 50 customer updates total)

**Solution:** DynamoDB TTL of 24 hours automatically deletes expired batches. For critical applications, add a scheduled Lambda to check for stale batches.

### What if batch submission fails?

**Problem:** Bulk API job fails

**Solution:** The event is marked as failed in the accumulator and returned to SQS for retry. The batch will be reprocessed on next Lambda invocation.

### What about concurrent batches?

**Design:** Only one window per batch type at a time (PK is unique). If Bulk Processor Lambda is invoked while processing a batch, subsequent invocations will create a new window for new events.

## References

- [Batch Accumulator Source Code](../app/services/batch_accumulator.py)
- [Bulk Processor Implementation](../bulk_processor.py)
- [Salesforce Bulk API 2.0 Documentation](https://developer.salesforce.com/docs/atlas.en-us.api_asynch.meta/api_asynch/)
- [Technical Requirements - Batch Processing](../../requirements/technical.md#priority-based-processing-with-dynamodb--bulk-api)
