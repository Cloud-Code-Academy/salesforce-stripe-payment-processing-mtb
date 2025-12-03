#!/bin/bash

# Initialize LocalStack SQS Queue for Development

echo "Initializing LocalStack SQS queue..."

# Create SQS queue
awslocal sqs create-queue \
    --queue-name stripe-webhook-events \
    --attributes VisibilityTimeout=300,MessageRetentionPeriod=345600

echo "SQS queue 'stripe-webhook-events' created successfully"

# List queues to verify
awslocal sqs list-queues

echo "LocalStack initialization complete"
