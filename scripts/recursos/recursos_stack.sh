#!/bin/bash

echo ""
aws s3api list-buckets --query "Buckets[].Name" --output text >> ./src/.resources.txt
aws iam list-roles --query "Roles[].RoleName" --output text >> ./src/.resources.txt
aws sqs list-queues --query "QueueUrls" --output text >> ./src/.resources.txt
aws dynamodb list-tables --query "TableNames" --output text >> ./src/.resources.txt
aws sns list-topics --query "Topics[].TopicArn" --output text >> ./src/.resources.txt
aws stepfunctions list-state-machines --output text >> ./src/.resources.txt
