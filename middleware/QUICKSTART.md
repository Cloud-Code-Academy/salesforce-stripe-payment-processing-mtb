# Quick Start Guide

Get the Salesforce-Stripe middleware running in 5 minutes.

## 1. Prerequisites Check

- [ ] Docker and Docker Compose installed
- [ ] Stripe account with test API keys
- [ ] Salesforce org with Connected App configured
- [ ] Git repository cloned

## 2. Configuration (2 minutes)

```bash
# Navigate to middleware directory
cd middleware

# Copy environment template
cp .env.example .env

# Edit .env with your credentials
nano .env
```

**Minimum required variables:**
```bash
STRIPE_API_KEY=sk_test_YOUR_KEY
STRIPE_WEBHOOK_SECRET=whsec_YOUR_SECRET
SALESFORCE_CLIENT_ID=YOUR_CONNECTED_APP_ID
SALESFORCE_CLIENT_SECRET=YOUR_CONNECTED_APP_SECRET
SALESFORCE_USERNAME=integration.user@yourorg.com
SALESFORCE_PASSWORD=your_password
SALESFORCE_SECURITY_TOKEN=your_token
```

## 3. Start Services (1 minute)

```bash
# Start all services (FastAPI, Redis, LocalStack)
docker-compose up -d

# Check if running
docker-compose ps
```

Expected output:
```
NAME                          STATUS
salesforce-stripe-middleware  Up
middleware-redis              Up (healthy)
middleware-localstack         Up
```

## 4. Verify Health (30 seconds)

```bash
# Basic health check
curl http://localhost:8000/health

# Check dependencies
curl http://localhost:8000/health/ready
```

Expected response:
```json
{
  "status": "ready",
  "dependencies": {
    "redis": {"status": "healthy"},
    "sqs": {"status": "healthy"},
    "salesforce": {"status": "healthy"}
  }
}
```

## 5. Test Webhook (1 minute)

### Option A: Using Stripe CLI (Recommended)

```bash
# Install Stripe CLI
brew install stripe/stripe-cli/stripe  # macOS
# or download from https://stripe.com/docs/stripe-cli

# Login
stripe login

# Forward webhooks
stripe listen --forward-to localhost:8000/webhook/stripe

# In another terminal, trigger test event
stripe trigger payment_intent.succeeded
```

### Option B: Manual Test with curl

```bash
# Generate test event payload
curl -X POST http://localhost:8000/webhook/stripe \
  -H "Content-Type: application/json" \
  -H "Stripe-Signature: t=123,v1=test" \
  -d '{
    "id": "evt_test",
    "type": "payment_intent.succeeded",
    "data": {
      "object": {
        "id": "pi_test",
        "amount": 2999,
        "currency": "usd"
      }
    }
  }'
```

## 6. View Logs

```bash
# Follow logs
docker-compose logs -f middleware

# Search for specific event
docker-compose logs middleware | grep "evt_"
```

## Common Issues

### Salesforce Authentication Fails
```
Error: Authentication failed: invalid_grant
```
**Fix:** Check username, password, and security token in `.env`

### Redis Connection Error
```
Error: Redis connection failed
```
**Fix:** Ensure Redis is running: `docker-compose ps redis`

### Webhook Signature Verification Fails
```
Error: Invalid Stripe webhook signature
```
**Fix:** For local testing with curl, use Stripe CLI instead

## Next Steps

✅ Middleware running successfully!

Now:
1. Configure Stripe webhook in Dashboard to point to your endpoint
2. Deploy to production (AWS ECS or Lambda)
3. Set up monitoring with Coralogix
4. Review security settings in [README.md](README.md)

## Need Help?

- 📖 Full documentation: [README.md](README.md)
- 🧪 Run tests: `pytest`
- 🐛 Check logs: `docker-compose logs -f`
- 📊 View metrics: `http://localhost:8000/metrics`

---

**Estimated setup time: 5 minutes**
**Status: Ready for development!** 🚀
