# Step 1.0: Create an S3 bucket to store TF state as a backup
terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket = "book-app-terraform-state"
    key    = "global/s3/terraform.tfstate"
    region = "us-east-1"
  }
}

# Step 1.1: Create EC2 Instance for the Landing Page
# Create EC2 instance to host the landing page in a security group that allows HTTP access.

provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "bookAppFrontEnd_WebEC2" {
  ami           = "ami-0e1989e836322f58b" # Replace with the AMI ID for your region
  instance_type = "t3.micro"
  key_name      = "rjm-devops-kp"

  security_groups = [aws_security_group.book_web_sg.name]

  tags = {
    Name           = "BookAppFrontEnd"
    ResourceType   = "EC2"
    ResourceDomain = "Web"
  }
}
resource "aws_security_group" "book_web_sg" {
  name        = "book_web_sg_2025"
  description = "Allow HTTP traffic"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Step 1.2: Create DynamoDB Tables
# For storing book details, user transactions, and purchase history

resource "aws_dynamodb_table" "book_list" {
  name         = "book_list"
  billing_mode = "PAY_PER_REQUEST" # On-demand, no fixed read/write capacity
  hash_key     = "bookId"

  # Attributes used in items
  attribute {
    name = "bookId"
    type = "S"
  }

  attribute {
    name = "title"
    type = "S"
  }

  # Optional: GSI for quick title search
  global_secondary_index {
    name            = "title-index"
    hash_key        = "title"
    projection_type = "ALL"
    # read/write capacity ignored in PAY_PER_REQUEST
  }
}

resource "aws_dynamodb_table" "book_transactions" {
  name         = "book_transactions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "transaction_id"

  attribute {
    name = "transaction_id"
    type = "S"
  }

  # Add more attributes as required
}

# Step 1.3: Create SNS Topics for Core Functionalities
# Each functionality (show book list, check out, buy, return, sell) will have its own SNS topic to promote Event-Driven Architecture (EDA).
# These topics will trigger the appropriate SQS queues.

resource "aws_sns_topic" "book_list" {
  name = "book-list-topic"
}

resource "aws_sns_topic" "book_checkout" {
  name = "book-checkout-topic"
}

resource "aws_sns_topic" "book_buy" {
  name = "book-buy-topic"
}

resource "aws_sns_topic" "book_return" {
  name = "book-return-topic"
}

resource "aws_sns_topic" "book_sell" {
  name = "book-sell-topic"
}

# Step 1.4: Create SQS Queues for Each SNS Topic
# Each SNS topic should trigger an SQS queue to handle the messages

resource "aws_sqs_queue" "book_list_queue" {
  name = "book-list-queue"
}

resource "aws_sqs_queue" "book_checkout_queue" {
  name = "book-checkout-queue"
}

resource "aws_sqs_queue" "book_buy_queue" {
  name = "book-buy-queue"
}

resource "aws_sqs_queue" "book_return_queue" {
  name = "book-return-queue"
}

resource "aws_sqs_queue" "book_sell_queue" {
  name = "book-sell-queue"
}

# Step 1.5: Create SNS-SQS Subscription
# Set up subscribe for the SQS queues to the associated SNS topics

resource "aws_sns_topic_subscription" "book_list_sub" {
  topic_arn = aws_sns_topic.book_list.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.book_list_queue.arn
}

resource "aws_sns_topic_subscription" "checkout_sub" {
  topic_arn = aws_sns_topic.book_checkout.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.book_checkout_queue.arn
}

resource "aws_sns_topic_subscription" "buy_sub" {
  topic_arn = aws_sns_topic.book_buy.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.book_buy_queue.arn
}

resource "aws_sns_topic_subscription" "return_sub" {
  topic_arn = aws_sns_topic.book_return.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.book_return_queue.arn
}

resource "aws_sns_topic_subscription" "sell_sub" {
  topic_arn = aws_sns_topic.book_sell.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.book_sell_queue.arn
}

resource "aws_sqs_queue_policy" "book_list_queue_policy" {
  queue_url = aws_sqs_queue.book_list_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Allow-SNS-SendMessage"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.book_list_queue.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_sns_topic.book_list.arn }
        }
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "book_checkout_queue_policy" {
  queue_url = aws_sqs_queue.book_checkout_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Allow-SNS-SendMessage"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.book_checkout_queue.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_sns_topic.book_checkout.arn }
        }
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "book_buy_queue_policy" {
  queue_url = aws_sqs_queue.book_buy_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Allow-SNS-SendMessage"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.book_buy_queue.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_sns_topic.book_buy.arn }
        }
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "book_return_queue_policy" {
  queue_url = aws_sqs_queue.book_return_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Allow-SNS-SendMessage"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.book_return_queue.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_sns_topic.book_return.arn }
        }
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "book_sell_queue_policy" {
  queue_url = aws_sqs_queue.book_sell_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Allow-SNS-SendMessage"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.book_sell_queue.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_sns_topic.book_sell.arn }
        }
      }
    ]
  })
}
