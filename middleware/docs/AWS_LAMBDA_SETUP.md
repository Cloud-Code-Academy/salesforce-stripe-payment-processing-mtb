# AWS Lambda Deployment Guide

Complete step-by-step guide to deploy your Salesforce-Stripe middleware to AWS Lambda.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Cost Estimate](#cost-estimate)
- [Setup Steps](#setup-steps)
  - [1. Install AWS Tools](#1-install-aws-tools)
  - [2. Configure AWS Credentials](#2-configure-aws-credentials)
  - [3. Create ElastiCache Redis (Optional)](#3-create-elasticache-redis-optional)
  - [4. Deploy with AWS SAM](#4-deploy-with-aws-sam)
  - [5. Configure Stripe Webhook](#5-configure-stripe-webhook)
  - [6. Test the Deployment](#6-test-the-deployment)
- [Monitoring & Troubleshooting](#monitoring--troubleshooting)
- [Updating the Deployment](#updating-the-deployment)
- [Cleanup](#cleanup)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                         AWS LAMBDA ARCHITECTURE                   │
└──────────────────────────────────────────────────────────────────┘

Stripe Webhook
    │
    ▼
API Gateway (HTTPS endpoint)
    │
    ▼
Lambda: webhook-receiver
    │ (verifies signature)
    │ (returns 200 OK < 500ms)
    ▼
SQS Queue (event buffer)
    │
    │ (automatic trigger)
    ▼
Lambda: sqs-worker
    │ (processes events)
    │ (OAuth with Salesforce)
    ▼
Salesforce REST API

Supporting Services:
- ElastiCache Redis → OAuth token caching
- Secrets Manager → Credentials storage
- CloudWatch Logs → Monitoring
- Dead Letter Queue → Failed events
```

### Key Components

| Component | Purpose | Cost |
|-----------|---------|------|
| **Lambda: webhook-receiver** | Receives webhooks from Stripe | Free tier |
| **Lambda: sqs-worker** | Processes events, updates Salesforce | Free tier |
| **API Gateway** | HTTPS endpoint for webhooks | Free tier |
| **SQS Queue** | Event buffering | Free tier |
| **ElastiCache Redis** | Token caching | ~$15/month |
| **Secrets Manager** | Secure credentials | ~$0.40/month |
| **CloudWatch Logs** | Monitoring | ~$0-1/month |

**Total:** ~$15-20/month (mostly Redis)

---

## Prerequisites

### 1. AWS Account
- Sign up at https://aws.amazon.com
- Verify your email
- Add payment method (free tier available)

### 2. Local Development Tools

**Required:**
- Python 3.11+
- Docker Desktop
- Git
- AWS CLI
- AWS SAM CLI

**Optional:**
- Stripe CLI (for testing)

### 3. Salesforce Setup

You need:
- Salesforce Connected App with OAuth enabled
- Integration user credentials
- Client ID and Client Secret

See [Salesforce Setup](#salesforce-connected-app-setup) below.

### 4. Stripe Account

You need:
- Stripe test account
- API keys (secret key)
- Webhook signing secret (will get after deployment)

---

## Cost Estimate

### AWS Free Tier (First 12 Months)

**Included for FREE:**
- Lambda: 1 million requests/month
- API Gateway: 1 million requests/month
- SQS: 1 million requests/month
- CloudWatch Logs: 5 GB/month

### Paid Services

**ElastiCache Redis:**
- t3.micro instance: ~$15/month
- **Alternative:** Use DynamoDB instead (free tier available)

**Secrets Manager:**
- $0.40 per secret/month × 3 secrets = ~$1.20/month

**Estimated Total:**
- **With Redis:** ~$16-20/month
- **Without Redis (using DynamoDB):** ~$1-2/month

### For Your Capstone Project

Expected webhook volume: **< 1,000 webhooks/month**

**Your cost:** **~$15-20/month** or **$1-2/month** without Redis

**Tip:** You can use local Redis during development and only enable ElastiCache for final demo.

---

## Setup Steps

### 1. Install AWS Tools

#### Install AWS CLI

**macOS:**
```bash
brew install awscli
```

**Linux:**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**Windows:**
Download from: https://aws.amazon.com/cli/

**Verify installation:**
```bash
aws --version
# Expected: aws-cli/2.x.x
```

---

#### Install AWS SAM CLI

**macOS:**
```bash
brew install aws-sam-cli
```

**Linux:**
```bash
pip install aws-sam-cli
```

**Windows:**
```bash
choco install aws-sam-cli
```

**Verify installation:**
```bash
sam --version
# Expected: SAM CLI, version 1.x.x
```

---

#### Install Docker Desktop

Required for SAM to build Lambda packages.

**macOS/Windows:**
- Download from: https://www.docker.com/products/docker-desktop

**Linux:**
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

**Verify Docker is running:**
```bash
docker --version
docker ps
# Should not error
```

---

### 2. Configure AWS Credentials

#### Option A: AWS Configure (Recommended)

```bash
aws configure
```

You'll be prompted for:
```
AWS Access Key ID [None]: YOUR_ACCESS_KEY_ID
AWS Secret Access Key [None]: YOUR_SECRET_ACCESS_KEY
Default region name [None]: us-east-1
Default output format [None]: json
```

#### Option B: Environment Variables

```bash
export AWS_ACCESS_KEY_ID=your_access_key_id
export AWS_SECRET_ACCESS_KEY=your_secret_access_key
export AWS_DEFAULT_REGION=us-east-1
```

#### Getting AWS Credentials

1. Log into AWS Console: https://console.aws.amazon.com
2. Go to **IAM** → **Users** → **Create User**
3. User name: `lambda-deployer`
4. Attach policies:
   - `AWSLambda_FullAccess`
   - `IAMFullAccess`
   - `AmazonSQSFullAccess`
   - `SecretsManagerReadWrite`
   - `AmazonAPIGatewayAdministrator`
   - `CloudWatchLogsFullAccess`
5. Click **Create access key** → **Command Line Interface (CLI)**
6. Save the Access Key ID and Secret Access Key

**Verify credentials:**
```bash
aws sts get-caller-identity
```

Should return your AWS account info.

---

### 3. Create ElastiCache Redis (Optional)

You have **two options** for Redis:

#### Option A: Skip for Now (Use DynamoDB or local Redis)

You can skip this step initially and use:
- Local Redis for development
- DynamoDB for production (modify code to use DynamoDB instead)

#### Option B: Create ElastiCache Redis (~$15/month)

**Via AWS Console:**

1. Go to: https://console.aws.amazon.com/elasticache
2. Click **Create** → **Redis clusters**
3. Configuration:
   - **Cluster mode:** Disabled
   - **Name:** `salesforce-stripe-redis`
   - **Engine version:** 7.x
   - **Node type:** `cache.t3.micro` (cheapest)
   - **Number of replicas:** 0 (for cost savings)
4. **Subnet group:** Create new or use default
5. **Security group:** Create new with:
   - Inbound rule: Port 6379, Source: Your Lambda security group
6. Click **Create**

**Wait 5-10 minutes for creation.**

**Get Redis endpoint:**
```bash
aws elasticache describe-cache-clusters \
  --cache-cluster-id salesforce-stripe-redis \
  --show-cache-node-info \
  --query 'CacheClusters[0].CacheNodes[0].Endpoint' \
  --output table
```

**Note the endpoint** (e.g., `salesforce-stripe-redis.abc123.0001.use1.cache.amazonaws.com`)

You'll need this for the deployment.

---

### 4. Deploy with AWS SAM

Now for the fun part - automated deployment!

#### Navigate to Middleware Directory

```bash
cd middleware
```

#### Option A: Automated Deployment Script (Easiest)

We've provided a deployment script that handles everything:

```bash
./scripts/deploy-lambda.sh development us-east-1
```

**You'll be prompted for:**
- Stripe API Key (sk_test_...)
- Stripe Webhook Secret (whsec_...) - can be placeholder for now
- Salesforce Client ID
- Salesforce Client Secret
- Salesforce Instance URL
- Redis Host (leave as localhost if skipping Redis)
- Redis Port (6379)

**The script will:**
1. ✅ Validate prerequisites
2. ✅ Build Lambda package with Docker
3. ✅ Deploy to AWS
4. ✅ Create all resources (Lambda, API Gateway, SQS, Secrets Manager)
5. ✅ Display your webhook URL

---

#### Option B: Manual Deployment (Advanced)

If you prefer manual control:

**Step 1: Build Lambda package**

```bash
sam build --use-container
```

This builds your Python dependencies in a Docker container that matches the Lambda runtime.

**Step 2: Deploy to AWS**

```bash
sam deploy \
  --stack-name salesforce-stripe-middleware-dev \
  --region us-east-1 \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    Environment=development \
    LogLevel=INFO \
    RedisHost=localhost \
    RedisPort=6379 \
    StripeApiKey=sk_test_YOUR_KEY \
    StripeWebhookSecretValue=whsec_placeholder \
    SalesforceClientId=YOUR_CLIENT_ID \
    SalesforceClientSecretValue=YOUR_CLIENT_SECRET \
    SalesforceInstanceUrl=https://login.salesforce.com \
  --guided
```

**Follow the prompts:**
- Confirm changes before deploy: Y
- Allow SAM CLI IAM role creation: Y
- Save arguments to configuration file: Y

---

#### Deployment Output

After successful deployment, you'll see:

```
CloudFormation outputs from deployed stack
-----------------------------------------------------------------------------
Outputs
-----------------------------------------------------------------------------
Key                 WebhookUrl
Description         Stripe Webhook URL (configure this in Stripe Dashboard)
Value               https://abc123xyz.execute-api.us-east-1.amazonaws.com/development/webhook/stripe

Key                 QueueUrl
Description         SQS Queue URL
Value               https://sqs.us-east-1.amazonaws.com/123456789/salesforce-stripe-middleware-dev-stripe-events
-----------------------------------------------------------------------------

Successfully created/updated stack - salesforce-stripe-middleware-dev in us-east-1
```

**Save the WebhookUrl** - you'll need it for Stripe configuration!

---

### 5. Configure Stripe Webhook

Now that your Lambda is deployed, configure Stripe to send webhooks to it.

#### Step 1: Go to Stripe Dashboard

https://dashboard.stripe.com/test/webhooks

#### Step 2: Add Endpoint

1. Click **Add endpoint**
2. **Endpoint URL:** Paste your `WebhookUrl` from deployment output
   - Example: `https://abc123xyz.execute-api.us-east-1.amazonaws.com/development/webhook/stripe`
3. **Description:** Salesforce-Stripe Middleware
4. **Events to send:** Select these events:
   - ✅ `checkout.session.completed`
   - ✅ `payment_intent.succeeded`
   - ✅ `payment_intent.payment_failed`
   - ✅ `customer.subscription.created`
   - ✅ `customer.subscription.updated`
   - ✅ `customer.subscription.deleted`
   - ✅ `customer.updated`
5. Click **Add endpoint**

#### Step 3: Get Webhook Signing Secret

1. Click on your newly created webhook endpoint
2. Click **Reveal** under "Signing secret"
3. Copy the secret (starts with `whsec_`)

#### Step 4: Update Lambda with Webhook Secret

```bash
aws secretsmanager update-secret \
  --secret-id salesforce-stripe-middleware-dev-stripe-webhook-secret \
  --secret-string "whsec_YOUR_ACTUAL_SECRET_HERE" \
  --region us-east-1
```

Or via AWS Console:
1. Go to: https://console.aws.amazon.com/secretsmanager
2. Find: `salesforce-stripe-middleware-dev-stripe-webhook-secret`
3. Click **Retrieve secret value** → **Edit**
4. Paste your webhook secret
5. Click **Save**

---

### 6. Test the Deployment

#### Test 1: Health Check

```bash
WEBHOOK_URL="https://YOUR_API_GATEWAY_URL/development"
curl ${WEBHOOK_URL}/health
```

**Expected response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-10-28T12:00:00Z",
  "version": "1.0.0"
}
```

#### Test 2: Trigger Test Webhook with Stripe CLI

Install Stripe CLI:
```bash
brew install stripe/stripe-cli/stripe
stripe login
```

Trigger a test event:
```bash
stripe trigger payment_intent.succeeded
```

**Check CloudWatch Logs:**
```bash
sam logs --stack-name salesforce-stripe-middleware-dev --tail
```

You should see:
```
[INFO] Received Stripe webhook event
[INFO] Event type: payment_intent.succeeded
[INFO] Signature verified
[INFO] Pushed to SQS queue
[INFO] Processing event...
[INFO] Event processed successfully
```

#### Test 3: Check SQS Queue

```bash
aws sqs get-queue-attributes \
  --queue-url YOUR_QUEUE_URL \
  --attribute-names ApproximateNumberOfMessages \
  --region us-east-1
```

If messages are processing correctly, this should be 0 (or low number).

#### Test 4: End-to-End Test

1. **Create a test subscription in Salesforce:**
   - This will trigger Stripe Checkout creation
2. **Complete checkout in Stripe:**
   - Use test card: `4242 4242 4242 4242`
3. **Stripe sends webhook to Lambda**
4. **Lambda processes and updates Salesforce**
5. **Check Salesforce:**
   - Subscription status should be updated
   - Payment transaction should be created

---

## Monitoring & Troubleshooting

### CloudWatch Logs

**View logs in real-time:**
```bash
sam logs --stack-name salesforce-stripe-middleware-dev --tail
```

**View specific function:**
```bash
aws logs tail /aws/lambda/salesforce-stripe-middleware-dev-webhook-receiver --follow
```

**Search logs:**
```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/salesforce-stripe-middleware-dev-sqs-worker \
  --filter-pattern "ERROR"
```

### Check SQS Queue Depth

```bash
aws sqs get-queue-attributes \
  --queue-url YOUR_QUEUE_URL \
  --attribute-names All \
  --region us-east-1
```

Look for:
- `ApproximateNumberOfMessages` - messages waiting
- `ApproximateNumberOfMessagesNotVisible` - messages being processed
- `ApproximateNumberOfMessagesDelayed` - delayed messages

### Check Dead Letter Queue

```bash
aws sqs receive-message \
  --queue-url YOUR_DLQ_URL \
  --max-number-of-messages 10 \
  --region us-east-1
```

If messages appear here, they've failed after 5 retry attempts.

### Common Issues

#### Issue: Signature Verification Failed

**Symptom:**
```
ERROR: Invalid Stripe webhook signature
```

**Solution:**
Update webhook secret in Secrets Manager:
```bash
aws secretsmanager update-secret \
  --secret-id salesforce-stripe-middleware-dev-stripe-webhook-secret \
  --secret-string "whsec_CORRECT_SECRET" \
  --region us-east-1
```

---

#### Issue: Salesforce Authentication Failed

**Symptom:**
```
ERROR: Authentication failed: invalid_grant
```

**Solution:**
1. Verify Connected App is enabled
2. Check Client ID and Client Secret
3. Update secret:
```bash
aws secretsmanager update-secret \
  --secret-id salesforce-stripe-middleware-dev-salesforce-client-secret \
  --secret-string '{"client_id":"YOUR_ID","client_secret":"YOUR_SECRET","instance_url":"https://login.salesforce.com"}' \
  --region us-east-1
```

---

#### Issue: Redis Connection Error

**Symptom:**
```
ERROR: Failed to connect to Redis
```

**Solution:**
1. **If using ElastiCache:**
   - Ensure Lambda is in same VPC as ElastiCache
   - Check security group allows port 6379
   - Update Redis host in template.yaml and redeploy

2. **If not using Redis:**
   - Modify code to skip Redis caching
   - Or implement DynamoDB fallback

---

#### Issue: Lambda Timeout

**Symptom:**
```
Task timed out after 30.00 seconds
```

**Solution:**
Increase timeout in template.yaml:
```yaml
Globals:
  Function:
    Timeout: 90  # Increase from 30
```

Then redeploy:
```bash
sam deploy
```

---

## Updating the Deployment

### Update Code Only

```bash
sam build --use-container
sam deploy
```

### Update Configuration

Edit `template.yaml`, then:
```bash
sam deploy
```

### Update Secrets

```bash
aws secretsmanager update-secret \
  --secret-id salesforce-stripe-middleware-dev-stripe-api-key \
  --secret-string "sk_test_NEW_KEY" \
  --region us-east-1
```

### View Current Configuration

```bash
aws cloudformation describe-stacks \
  --stack-name salesforce-stripe-middleware-dev \
  --region us-east-1 \
  --query 'Stacks[0].Parameters'
```

---

## Cleanup

### Delete Everything

To avoid charges, delete the entire stack:

```bash
sam delete --stack-name salesforce-stripe-middleware-dev --region us-east-1
```

This removes:
- Lambda functions
- API Gateway
- SQS queues
- Secrets Manager secrets
- CloudWatch log groups
- IAM roles

**Note:** ElastiCache (if created) must be deleted separately:

```bash
aws elasticache delete-cache-cluster \
  --cache-cluster-id salesforce-stripe-redis \
  --region us-east-1
```

---

## Architecture Decisions

### Why Lambda instead of ECS?

| Aspect | Lambda | ECS |
|--------|--------|-----|
| **Cost** | Pay per request (~$0) | Always running (~$30/month) |
| **Scaling** | Automatic (0 to 1000s) | Manual configuration |
| **Management** | Fully managed | Container management |
| **Cold Starts** | 100-500ms first request | None |
| **Best For** | Low/medium traffic | Consistent high traffic |

**For your capstone:** Lambda is ideal (low traffic, low cost, auto-scaling).

### Why API Gateway?

Lambda cannot receive direct HTTP requests. API Gateway provides:
- HTTPS endpoint
- Request/response transformation
- Throttling and rate limiting
- API keys and usage plans

### Why SQS?

- **Decoupling:** Webhook response (200 OK) separate from processing
- **Reliability:** Messages retained for 4 days
- **Retry:** Automatic retry with exponential backoff
- **Dead Letter Queue:** Failed messages preserved for investigation

---

## Cost Optimization Tips

1. **Use Lambda instead of EC2/ECS**
   - Pay only for actual webhook requests

2. **Skip ElastiCache during development**
   - Use local Redis or DynamoDB

3. **Set log retention to 7 days**
   - Reduce CloudWatch Logs storage costs

4. **Use Reserved Concurrency limits**
   - Prevent runaway costs from infinite loops

5. **Monitor costs with AWS Budgets**
   - Set up alerts for unexpected charges

---

## Next Steps

1. ✅ Deploy to AWS Lambda
2. ✅ Configure Stripe webhook
3. ✅ Test end-to-end flow
4. 🚀 Integrate with Salesforce
5. 📊 Set up CloudWatch dashboards
6. 🔔 Configure alerts (email/Slack)
7. 📝 Document for team

---

## Support & Resources

- **AWS SAM Documentation:** https://docs.aws.amazon.com/serverless-application-model/
- **Lambda Best Practices:** https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html
- **Stripe Webhooks Guide:** https://stripe.com/docs/webhooks
- **Troubleshooting:** See [../README.md](../README.md#troubleshooting)

---

**Questions?** Open an issue in the GitHub repository or contact the team.

**Good luck with your capstone project! 🚀**
