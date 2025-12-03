#!/bin/bash

###############################################################################
# CloudWatch Dashboard Deployment Script
#
# Deploys comprehensive CloudWatch Dashboard for the 3-Lambda architecture
#
# Usage:
#   ./scripts/deploy-dashboard.sh <stack-name> <region>
#
# Example:
#   ./scripts/deploy-dashboard.sh salesforce-stripe-middleware-dev us-east-1
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Parameters
STACK_NAME=${1:-}
REGION=${2:-us-east-1}

# Validate parameters
if [ -z "$STACK_NAME" ]; then
    echo -e "${RED}❌ Error: Stack name is required${NC}"
    echo "Usage: $0 <stack-name> <region>"
    echo "Example: $0 salesforce-stripe-middleware-dev us-east-1"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       CloudWatch Dashboard Deployment                          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Stack Name:${NC} $STACK_NAME"
echo -e "${BLUE}Region:${NC} $REGION"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ Error: AWS CLI is not installed${NC}"
    echo "Install it from: https://aws.amazon.com/cli/"
    exit 1
fi

# Check if stack exists
echo -e "${YELLOW}⏳ Checking if stack exists...${NC}"
if ! aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" &> /dev/null; then
    echo -e "${RED}❌ Error: Stack '$STACK_NAME' not found${NC}"
    echo "Deploy the stack first with: sam deploy"
    exit 1
fi

echo -e "${GREEN}✓ Stack exists${NC}"

# Get stack outputs
echo -e "${YELLOW}⏳ Retrieving stack outputs...${NC}"

WEBHOOK_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='WebhookFunctionArn'].OutputValue" \
    --output text | awk -F':' '{print $NF}')

SQS_WORKER_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='SqsWorkerFunctionArn'].OutputValue" \
    --output text | awk -F':' '{print $NF}')

BULK_PROCESSOR_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='BulkProcessorFunctionArn'].OutputValue" \
    --output text | awk -F':' '{print $NF}')

MAIN_QUEUE=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='QueueUrl'].OutputValue" \
    --output text | awk -F'/' '{print $NF}')

LOW_PRIORITY_QUEUE=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='LowPriorityQueueUrl'].OutputValue" \
    --output text | awk -F'/' '{print $NF}')

DLQ=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='DlqUrl'].OutputValue" \
    --output text | awk -F'/' '{print $NF}')

API_GATEWAY=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='ApiId'].OutputValue" \
    --output text)

CACHE_TABLE=$(aws cloudformation describe-stack-resources \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "StackResources[?LogicalResourceId=='CacheTable'].PhysicalResourceId" \
    --output text)

BATCH_ACCUMULATOR_TABLE=$(aws cloudformation describe-stack-resources \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "StackResources[?LogicalResourceId=='BatchAccumulatorTable'].PhysicalResourceId" \
    --output text)

echo -e "${GREEN}✓ Stack outputs retrieved${NC}"

# Create dashboard JSON with substitutions
echo -e "${YELLOW}⏳ Creating dashboard definition...${NC}"

DASHBOARD_NAME="${STACK_NAME}-middleware-dashboard"
DASHBOARD_BODY=$(cat "$PROJECT_ROOT/cloudwatch-dashboard.json" | \
    sed "s/\${AWS::StackName}/$STACK_NAME/g" | \
    sed "s/\${AWS::Region}/$REGION/g" | \
    sed "s/\${WebhookFunction}/$WEBHOOK_FUNCTION/g" | \
    sed "s/\${SqsWorkerFunction}/$SQS_WORKER_FUNCTION/g" | \
    sed "s/\${BulkProcessorFunction}/$BULK_PROCESSOR_FUNCTION/g" | \
    sed "s/\${StripeEventQueue.QueueName}/$MAIN_QUEUE/g" | \
    sed "s/\${LowPriorityEventQueue.QueueName}/$LOW_PRIORITY_QUEUE/g" | \
    sed "s/\${StripeEventDLQ.QueueName}/$DLQ/g" | \
    sed "s/\${WebhookHttpApi}/$API_GATEWAY/g" | \
    sed "s/\${CacheTable}/$CACHE_TABLE/g" | \
    sed "s/\${BatchAccumulatorTable}/$BATCH_ACCUMULATOR_TABLE/g" | \
    sed "s/\${Environment}/$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query "Stacks[0].Parameters[?ParameterKey=='Environment'].ParameterValue" --output text)/g")

echo -e "${GREEN}✓ Dashboard definition created${NC}"

# Deploy dashboard
echo -e "${YELLOW}⏳ Deploying CloudWatch Dashboard...${NC}"

aws cloudwatch put-dashboard \
    --dashboard-name "$DASHBOARD_NAME" \
    --dashboard-body "$DASHBOARD_BODY" \
    --region "$REGION"

echo -e "${GREEN}✓ Dashboard deployed successfully${NC}"

# Generate dashboard URL
DASHBOARD_URL="https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards:name=${DASHBOARD_NAME}"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                 Deployment Successful!                         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📊 Dashboard Name:${NC} $DASHBOARD_NAME"
echo -e "${BLUE}🔗 Dashboard URL:${NC}"
echo -e "   $DASHBOARD_URL"
echo ""
echo -e "${YELLOW}ℹ  Tip: Bookmark the dashboard URL for quick access${NC}"
echo ""
echo -e "${GREEN}✓ The dashboard includes:${NC}"
echo "  • Lambda Invocations (all 3 functions)"
echo "  • Lambda Errors & Duration"
echo "  • Queue Depths (main + low-priority + DLQ)"
echo "  • API Gateway Metrics"
echo "  • DynamoDB Capacity"
echo "  • Recent Error Logs"
echo ""
echo -e "${YELLOW}📋 CloudWatch Alarms are already deployed via SAM template${NC}"
echo ""
