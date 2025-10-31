#!/bin/bash
#
# AWS Lambda Deployment Script
# Deploys the Salesforce-Stripe middleware to AWS Lambda using AWS SAM
#
# Usage:
#   ./scripts/deploy-lambda.sh [environment] [region]
#
# Examples:
#   ./scripts/deploy-lambda.sh development us-east-1
#   ./scripts/deploy-lambda.sh production us-west-2
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${1:-development}
AWS_REGION=${2:-us-east-1}
STACK_NAME="salesforce-stripe-middleware-${ENVIRONMENT}"
TEMPLATE_FILE="template.yaml"
BUILD_DIR=".aws-sam/build"

# Print colored output
print_info() {
    echo -e "${BLUE}ℹ ${1}${NC}"
}

print_success() {
    echo -e "${GREEN}✓ ${1}${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ ${1}${NC}"
}

print_error() {
    echo -e "${RED}✗ ${1}${NC}"
}

# Print banner
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     Salesforce-Stripe Middleware - AWS Lambda Deployment      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
print_info "Environment: ${ENVIRONMENT}"
print_info "Region: ${AWS_REGION}"
print_info "Stack Name: ${STACK_NAME}"
echo ""

# Check prerequisites
print_info "Checking prerequisites..."

# Check if AWS SAM CLI is installed
if ! command -v sam &> /dev/null; then
    print_error "AWS SAM CLI is not installed!"
    echo ""
    echo "Please install AWS SAM CLI:"
    echo "  macOS:   brew install aws-sam-cli"
    echo "  Linux:   pip install aws-sam-cli"
    echo "  Windows: choco install aws-sam-cli"
    echo ""
    echo "Or see: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html"
    exit 1
fi
print_success "AWS SAM CLI is installed"

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS CLI is not configured!"
    echo ""
    echo "Please configure AWS CLI:"
    echo "  aws configure"
    echo ""
    echo "Or set environment variables:"
    echo "  export AWS_ACCESS_KEY_ID=your_key_id"
    echo "  export AWS_SECRET_ACCESS_KEY=your_secret_key"
    echo "  export AWS_DEFAULT_REGION=${AWS_REGION}"
    exit 1
fi
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
print_success "AWS CLI is configured (Account: ${ACCOUNT_ID})"

# Check if Docker daemon is running and accessible (required for SAM build)
# docker version checks both client and server, failing if daemon is not running
if ! docker version --format '{{.Server.Version}}' &> /dev/null; then
    print_error "Docker daemon is not running or not accessible!"
    echo ""
    echo "AWS SAM requires Docker daemon to build Lambda packages."
    echo "Please start Docker Desktop and wait for it to fully initialize."
    echo ""
    echo "macOS/Windows:"
    echo "  1. Open Docker Desktop application"
    echo "  2. Wait for the icon to show 'Docker Desktop is running'"
    echo "  3. Run this script again"
    echo ""
    echo "Linux:"
    echo "  sudo systemctl start docker"
    echo ""
    echo "To verify Docker is ready, run: docker version"
    exit 1
fi
print_success "Docker daemon is running and accessible"

echo ""
print_info "All prerequisites met!"
echo ""

# Prompt for sensitive parameters
print_warning "You will be prompted for sensitive configuration values."
print_info "These values will be stored in AWS Secrets Manager (encrypted)."
echo ""

read -p "Enter Stripe API Key (sk_test_...): " STRIPE_API_KEY
read -p "Enter Stripe Webhook Secret (whsec_...): " STRIPE_WEBHOOK_SECRET
read -p "Enter Salesforce Client ID: " SALESFORCE_CLIENT_ID
read -sp "Enter Salesforce Client Secret: " SALESFORCE_CLIENT_SECRET
echo ""
read -p "Enter Salesforce Instance URL [https://login.salesforce.com]: " SALESFORCE_INSTANCE_URL
SALESFORCE_INSTANCE_URL=${SALESFORCE_INSTANCE_URL:-https://login.salesforce.com}

echo ""
print_info "Configuration captured successfully!"
print_info "DynamoDB table will be created automatically - no additional setup needed!"
echo ""

# Validate SAM template
print_info "Validating SAM template..."
if sam validate --template ${TEMPLATE_FILE} --region ${AWS_REGION}; then
    print_success "Template validation passed"
else
    print_error "Template validation failed"
    exit 1
fi
echo ""

# Build Lambda package
print_info "Building Lambda package..."
print_warning "This may take a few minutes..."
echo ""

sam build \
    --template ${TEMPLATE_FILE} \
    --use-container \
    --cached \
    --parallel

if [ $? -eq 0 ]; then
    print_success "Lambda package built successfully"
else
    print_error "Build failed"
    exit 1
fi
echo ""

# Deploy to AWS
print_info "Deploying to AWS..."
print_warning "This will create AWS resources (Lambda, API Gateway, SQS, etc.)"
echo ""

sam deploy \
    --template-file ${BUILD_DIR}/template.yaml \
    --stack-name ${STACK_NAME} \
    --region ${AWS_REGION} \
    --capabilities CAPABILITY_IAM \
    --resolve-s3 \
    --parameter-overrides \
        Environment=${ENVIRONMENT} \
        LogLevel=INFO \
        StripeApiKey=${STRIPE_API_KEY} \
        StripeWebhookSecretValue=${STRIPE_WEBHOOK_SECRET} \
        SalesforceClientId=${SALESFORCE_CLIENT_ID} \
        SalesforceClientSecretValue=${SALESFORCE_CLIENT_SECRET} \
        SalesforceInstanceUrl=${SALESFORCE_INSTANCE_URL} \
    --no-confirm-changeset \
    --no-fail-on-empty-changeset

if [ $? -eq 0 ]; then
    echo ""
    print_success "Deployment completed successfully!"
    echo ""
else
    print_error "Deployment failed"
    exit 1
fi

# Get stack outputs
print_info "Retrieving deployment outputs..."
echo ""

WEBHOOK_URL=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`WebhookUrl`].OutputValue' \
    --output text)

WEBHOOK_FUNCTION_ARN=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`WebhookFunctionArn`].OutputValue' \
    --output text)

SQS_WORKER_FUNCTION_ARN=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`SqsWorkerFunctionArn`].OutputValue' \
    --output text)

BULK_PROCESSOR_FUNCTION_ARN=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`BulkProcessorFunctionArn`].OutputValue' \
    --output text)

QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`QueueUrl`].OutputValue' \
    --output text)

LOW_PRIORITY_QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`LowPriorityQueueUrl`].OutputValue' \
    --output text)

DLQ_URL=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`DlqUrl`].OutputValue' \
    --output text)

BATCH_ACCUMULATOR_TABLE=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`BatchAccumulatorTableName`].OutputValue' \
    --output text)

# Display summary
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Deployment Summary                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
print_success "Stack Name: ${STACK_NAME}"
print_success "Region: ${AWS_REGION}"
print_success "Environment: ${ENVIRONMENT}"
echo ""
print_info "🔗 Webhook URL (configure in Stripe):"
echo "  ${WEBHOOK_URL}"
echo ""
print_info "⚡ Lambda Functions (3-tier architecture):"
echo "  Webhook Receiver:  ${WEBHOOK_FUNCTION_ARN##*/}"
echo "  SQS Worker:        ${SQS_WORKER_FUNCTION_ARN##*/}"
echo "  Bulk Processor:    ${BULK_PROCESSOR_FUNCTION_ARN##*/}"
echo ""
print_info "📬 SQS Queues:"
echo "  Main Queue (HIGH/MEDIUM):     ${QUEUE_URL##*/}"
echo "  Low-Priority Queue (BULK):    ${LOW_PRIORITY_QUEUE_URL##*/}"
echo "  Dead Letter Queue:            ${DLQ_URL##*/}"
echo ""
print_info "💾 DynamoDB Tables:"
echo "  Batch Accumulator: ${BATCH_ACCUMULATOR_TABLE}"
echo ""

# Next steps
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                        Next Steps                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "1. Deploy CloudWatch Dashboard (recommended):"
echo "   ./scripts/deploy-dashboard.sh ${STACK_NAME} ${AWS_REGION}"
echo ""
echo "2. Configure Stripe Webhook:"
echo "   - Go to: https://dashboard.stripe.com/webhooks"
echo "   - Click 'Add endpoint'"
echo "   - Endpoint URL: ${WEBHOOK_URL}"
echo "   - Select events: checkout.session.completed, payment_intent.succeeded, etc."
echo ""
echo "3. Test the webhook:"
echo "   stripe trigger payment_intent.succeeded"
echo ""
echo "4. Monitor Lambda logs (all 3 functions):"
echo "   sam logs --stack-name ${STACK_NAME} --tail"
echo ""
echo "5. View CloudWatch Dashboard:"
echo "   https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${STACK_NAME}"
echo ""
echo "6. Check health endpoint:"
echo "   curl ${WEBHOOK_URL%/webhook/stripe}/health/ready"
echo ""
echo "7. View SQS queues:"
echo "   https://console.aws.amazon.com/sqs/v2/home?region=${AWS_REGION}"
echo ""
echo "📊 Architecture Summary:"
echo "   • Webhook Receiver → Signature verification, priority routing"
echo "   • SQS Worker → HIGH/MEDIUM priority (REST API)"
echo "   • Bulk Processor → LOW priority (Bulk API 2.0, sliding window)"
echo "   • 13 CloudWatch Alarms → Comprehensive monitoring"
echo ""

print_success "Deployment complete! 🚀"
echo ""
