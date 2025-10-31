#!/bin/bash
#
# Monitor the middleware system in real-time
# Usage: ./monitor_system.sh [check|logs|sqs|all]
#

set -e

STACK_NAME="salesforce-stripe-middleware-development"
REGION="us-east-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

function check_health() {
    print_header "🏥 Health Check"

    WEBHOOK_URL=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`WebhookUrl`].OutputValue' \
        --output text)

    HEALTH_URL="${WEBHOOK_URL%/webhook/stripe}/health"

    echo "Checking: $HEALTH_URL"
    echo ""

    curl -s "$HEALTH_URL" | python3 -m json.tool
}

function check_sqs_queues() {
    print_header "📬 SQS Queue Status"

    MAIN_QUEUE=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`QueueUrl`].OutputValue' \
        --output text)

    LOW_PRIORITY_QUEUE=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`LowPriorityQueueUrl`].OutputValue' \
        --output text)

    DLQ=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`DlqUrl`].OutputValue' \
        --output text)

    echo -e "${GREEN}Main Queue (HIGH/MEDIUM priority):${NC}"
    aws sqs get-queue-attributes \
        --queue-url "$MAIN_QUEUE" \
        --region "$REGION" \
        --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
        --query 'Attributes' \
        --output json | python3 -m json.tool

    echo -e "\n${YELLOW}Low Priority Queue (Bulk API):${NC}"
    aws sqs get-queue-attributes \
        --queue-url "$LOW_PRIORITY_QUEUE" \
        --region "$REGION" \
        --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
        --query 'Attributes' \
        --output json | python3 -m json.tool

    echo -e "\n${RED}Dead Letter Queue:${NC}"
    aws sqs get-queue-attributes \
        --queue-url "$DLQ" \
        --region "$REGION" \
        --attribute-names ApproximateNumberOfMessages \
        --query 'Attributes' \
        --output json | python3 -m json.tool
}

function tail_webhook_logs() {
    print_header "📝 Webhook Lambda Logs (Last 5 minutes)"

    LOG_GROUP="/aws/lambda/${STACK_NAME}-webhook-receiver"

    echo "Tailing logs from: $LOG_GROUP"
    echo ""

    aws logs tail "$LOG_GROUP" \
        --region "$REGION" \
        --follow \
        --format short \
        --since 5m
}

function tail_worker_logs() {
    print_header "📝 SQS Worker Lambda Logs (Last 5 minutes)"

    LOG_GROUP="/aws/lambda/${STACK_NAME}-sqs-worker"

    echo "Tailing logs from: $LOG_GROUP"
    echo ""

    aws logs tail "$LOG_GROUP" \
        --region "$REGION" \
        --follow \
        --format short \
        --since 5m
}

function tail_bulk_logs() {
    print_header "📝 Bulk Processor Lambda Logs (Last 5 minutes)"

    LOG_GROUP="/aws/lambda/${STACK_NAME}-bulk-processor"

    echo "Tailing logs from: $LOG_GROUP"
    echo ""

    aws logs tail "$LOG_GROUP" \
        --region "$REGION" \
        --follow \
        --format short \
        --since 5m
}

function show_recent_errors() {
    print_header "❌ Recent Errors (Last 10 minutes)"

    for LOG_GROUP in \
        "/aws/lambda/${STACK_NAME}-webhook-receiver" \
        "/aws/lambda/${STACK_NAME}-sqs-worker" \
        "/aws/lambda/${STACK_NAME}-bulk-processor"
    do
        echo -e "\n${RED}Checking: $LOG_GROUP${NC}"
        aws logs filter-log-events \
            --log-group-name "$LOG_GROUP" \
            --region "$REGION" \
            --start-time $(($(date +%s) - 600))000 \
            --filter-pattern "ERROR" \
            --query 'events[].message' \
            --output text | head -20
    done
}

# Main script
case "${1:-all}" in
    check|health)
        check_health
        ;;
    sqs|queues)
        check_sqs_queues
        ;;
    webhook)
        tail_webhook_logs
        ;;
    worker)
        tail_worker_logs
        ;;
    bulk)
        tail_bulk_logs
        ;;
    errors)
        show_recent_errors
        ;;
    all)
        check_health
        echo ""
        check_sqs_queues
        echo ""
        show_recent_errors
        ;;
    *)
        echo "Usage: $0 [check|sqs|webhook|worker|bulk|errors|all]"
        echo ""
        echo "Commands:"
        echo "  check    - Run health check endpoint"
        echo "  sqs      - Check SQS queue depths"
        echo "  webhook  - Tail webhook Lambda logs"
        echo "  worker   - Tail SQS worker Lambda logs"
        echo "  bulk     - Tail bulk processor Lambda logs"
        echo "  errors   - Show recent errors from all Lambdas"
        echo "  all      - Run health check, SQS status, and show errors"
        exit 1
        ;;
esac
