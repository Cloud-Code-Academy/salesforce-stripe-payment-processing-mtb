# Integration Testing Guide

## Overview

This guide covers the comprehensive integration test suite for the Salesforce-Stripe Payment Processing Middleware. The tests validate all three Lambda functions and their interactions with AWS services, Stripe webhooks, and Salesforce APIs.

## Test Structure

```
tests/integration/
├── __init__.py                 # Package initialization
├── conftest.py                 # Shared fixtures and configuration
├── test_webhook_receiver.py    # Webhook Lambda tests
├── test_sqs_worker.py         # SQS Worker Lambda tests
├── test_bulk_processor.py     # Bulk Processor Lambda tests
├── test_end_to_end.py         # End-to-end flow tests
├── test_utils.py              # Testing utilities
└── factories.py               # Test data factories
```

## Running Tests

### Prerequisites

```bash
# Install test dependencies
pip install -r requirements-test.txt

# Set test environment variables
export AWS_DEFAULT_REGION=us-east-1
export ENVIRONMENT=test
```

### Run All Tests

```bash
# Run all integration tests
pytest tests/integration/ -v

# Run with coverage
pytest tests/integration/ --cov=app --cov-report=html

# Run specific test file
pytest tests/integration/test_webhook_receiver.py -v

# Run specific test
pytest tests/integration/test_webhook_receiver.py::TestWebhookReceiver::test_valid_webhook_high_priority_event -v
```

### Run by Category

```bash
# Run only webhook tests
pytest tests/integration/ -k webhook -v

# Run only bulk processing tests
pytest tests/integration/ -k bulk -v

# Run only end-to-end tests
pytest tests/integration/test_end_to_end.py -v
```

## Test Categories

### 1. Webhook Receiver Tests

Tests the webhook entry point Lambda:

- **Signature Validation**: Valid and invalid signatures
- **Event Routing**: Priority-based queue routing
- **Rate Limiting**: Request throttling
- **Duplicate Detection**: Idempotency checks
- **Error Handling**: Malformed requests, missing headers
- **Health Checks**: Liveness and readiness endpoints

### 2. SQS Worker Tests

Tests the REST API processor Lambda:

- **Event Processing**: All HIGH/MEDIUM priority event types
- **Salesforce Integration**: Customer, subscription, payment updates
- **Batch Processing**: Multiple messages per invocation
- **Partial Failures**: Individual message retry logic
- **Error Recovery**: Retry with exponential backoff
- **Event Caching**: Successful processing cache

### 3. Bulk Processor Tests

Tests the Bulk API processor Lambda:

- **Batch Accumulation**: Sliding window algorithm
- **Size Threshold**: Processing at 200 records
- **Time Threshold**: Processing after 30 seconds
- **Bulk API Operations**: Job creation, data upload, status polling
- **Concurrent Processing**: Multiple batch types
- **Failure Handling**: API errors and partial failures

### 4. End-to-End Tests

Tests complete event flows:

- **High Priority Flow**: Webhook → SQS → REST API → Salesforce
- **Low Priority Flow**: Webhook → SQS → Accumulator → Bulk API → Salesforce
- **Mixed Priority**: Concurrent processing of different priorities
- **Failure Recovery**: Retry mechanisms across Lambdas
- **Duplicate Prevention**: Cross-Lambda idempotency

## Test Fixtures

### Core Fixtures (conftest.py)

```python
@pytest.fixture
def test_settings():
    """Test environment settings"""

@pytest.fixture
def dynamodb_service():
    """Mocked DynamoDB service"""

@pytest.fixture
def sqs_service():
    """Mocked SQS service"""

@pytest.fixture
def mock_salesforce_service():
    """Mocked Salesforce API"""

@pytest.fixture
def batch_accumulator():
    """Batch accumulator with test config"""

@pytest.fixture
def stripe_event_factory():
    """Factory for creating Stripe events"""

@pytest.fixture
def generate_stripe_signature():
    """Generate valid webhook signatures"""
```

## Test Data Factories

### Stripe Events

```python
from tests.integration.factories import StripeEventFactory

# Create test events
factory = StripeEventFactory()
event = factory.payment_intent_succeeded(
    customer_id="cus_test123",
    amount=5000
)
```

### Salesforce Data

```python
from tests.integration.factories import SalesforceDataFactory

# Create test data
factory = SalesforceDataFactory()
contact = factory.contact(
    email="test@example.com",
    stripe_customer_id="cus_test123"
)
```

### Bulk Data

```python
from tests.integration.factories import BulkDataFactory

# Create batch for testing
factory = BulkDataFactory()
events = factory.create_customer_batch(size=100)
```

## Test Utilities

### Performance Profiling

```python
from tests.integration.test_utils import PerformanceProfiler

profiler = PerformanceProfiler()
await profiler.measure("webhook_processing", webhook_handler, event)
report = profiler.get_report()
```

### Data Validation

```python
from tests.integration.test_utils import DataValidator

errors = DataValidator.validate_salesforce_customer(customer_data)
assert len(errors) == 0
```

### Test Metrics

```python
from tests.integration.test_utils import TestMetrics

metrics = TestMetrics()
metrics.record_event("payment_intent.succeeded", "HIGH")
metrics.record_api_call("salesforce")
summary = metrics.get_summary()
```

## CI/CD Integration

### GitHub Actions Workflow

Create `.github/workflows/test.yml`:

```yaml
name: Integration Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v3

    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.11'

    - name: Install dependencies
      run: |
        cd middleware
        pip install -r requirements.txt
        pip install -r requirements-test.txt

    - name: Run integration tests
      env:
        AWS_DEFAULT_REGION: us-east-1
        ENVIRONMENT: test
      run: |
        cd middleware
        pytest tests/integration/ -v --cov=app --cov-report=xml

    - name: Upload coverage
      uses: codecov/codecov-action@v3
      with:
        file: ./middleware/coverage.xml
        fail_ci_if_error: true
```

### Pre-deployment Testing

Add to `middleware/scripts/deploy-lambda.sh`:

```bash
# Run tests before deployment
print_info "Running integration tests..."
pytest tests/integration/ -v --tb=short

if [ $? -ne 0 ]; then
    print_error "Tests failed. Aborting deployment."
    exit 1
fi
```

## Performance Testing

### Load Testing

```python
# tests/integration/test_performance.py
import asyncio
from tests.integration.factories import BulkDataFactory

async def test_high_volume_processing():
    """Test system under load."""
    factory = BulkDataFactory()
    events = factory.create_stress_test_batch(1000)

    # Process events concurrently
    tasks = []
    for event in events:
        task = process_webhook(event)
        tasks.append(task)

    results = await asyncio.gather(*tasks)

    # Verify success rate
    successful = sum(1 for r in results if r["statusCode"] == 200)
    assert successful / len(results) > 0.99  # 99% success rate
```

### Benchmark Testing

```python
async def test_processing_benchmarks():
    """Test processing speed benchmarks."""
    profiler = PerformanceProfiler()

    # Webhook processing should be < 100ms
    await profiler.measure("webhook", process_webhook, event)

    # SQS batch processing should be < 500ms for 10 messages
    await profiler.measure("sqs_batch", process_sqs_batch, batch)

    report = profiler.get_report()
    assert report["p95_duration_ms"] < 500
```

## Test Coverage Requirements

### Minimum Coverage Targets

- Overall: 80%
- Webhook Receiver: 90%
- SQS Worker: 85%
- Bulk Processor: 85%
- Critical paths: 95%

### Check Coverage

```bash
# Generate coverage report
pytest tests/integration/ --cov=app --cov-report=term-missing

# Generate HTML report
pytest tests/integration/ --cov=app --cov-report=html
open htmlcov/index.html
```

## Debugging Tests

### Verbose Output

```bash
# Show all print statements
pytest tests/integration/ -v -s

# Show detailed failure info
pytest tests/integration/ -vv --tb=long
```

### Debug Individual Test

```python
import pytest
import pdb

@pytest.mark.debug
async def test_debug_example():
    pdb.set_trace()  # Debugger breakpoint
    result = await process_event(event)
```

Run with: `pytest -v -s -k debug`

## Mock Services

### Local Testing with LocalStack

```bash
# Start LocalStack
docker-compose up localstack

# Set endpoint URL
export AWS_ENDPOINT_URL=http://localhost:4566

# Run tests against LocalStack
pytest tests/integration/ --localstack
```

### Salesforce Sandbox Testing

```bash
# Use sandbox credentials
export SALESFORCE_DOMAIN=test.salesforce.com
export SALESFORCE_IS_SANDBOX=true

# Run with real Salesforce
pytest tests/integration/ --real-salesforce
```

## Best Practices

### 1. Test Isolation

- Each test should be independent
- Use fresh fixtures for each test
- Clean up resources after tests

### 2. Realistic Data

- Use factories for consistent test data
- Test edge cases and error conditions
- Include metadata and optional fields

### 3. Async Testing

- Use `pytest.mark.asyncio` for async tests
- Properly await all async operations
- Handle concurrent operations correctly

### 4. Error Testing

- Test all error paths
- Verify error messages and status codes
- Test retry and recovery mechanisms

### 5. Performance

- Keep tests fast (< 1 second each)
- Use mocks instead of real services
- Parallelize where possible

## Troubleshooting

### Common Issues

1. **Import Errors**
   ```bash
   # Add middleware to Python path
   export PYTHONPATH=$PYTHONPATH:$(pwd)/middleware
   ```

2. **AWS Credential Errors**
   ```bash
   # Use dummy credentials for mocked services
   export AWS_ACCESS_KEY_ID=testing
   export AWS_SECRET_ACCESS_KEY=testing
   ```

3. **Async Test Failures**
   ```python
   # Ensure proper event loop
   @pytest.fixture(scope="session")
   def event_loop():
       loop = asyncio.get_event_loop_policy().new_event_loop()
       yield loop
       loop.close()
   ```

## Continuous Improvement

### Adding New Tests

1. Create test in appropriate file
2. Use existing fixtures and factories
3. Follow naming convention: `test_<feature>_<scenario>`
4. Document complex test logic
5. Update coverage requirements if needed

### Maintaining Tests

- Review and update tests with code changes
- Remove obsolete tests
- Refactor duplicate test code
- Keep factories up-to-date with schema changes

## Summary

The integration test suite provides comprehensive coverage of the middleware system:

- ✅ All 3 Lambda functions tested
- ✅ Complete event flows validated
- ✅ Error handling and recovery tested
- ✅ Performance benchmarks verified
- ✅ CI/CD integration ready

Run tests regularly during development and before deployments to ensure system reliability and correctness.