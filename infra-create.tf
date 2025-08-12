# Step 1.1: Create EC2 Instance for the Landing Page
# Create EC2 instance to host the landing page in a security group that allows HTTP access.

provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "web_app" {
  ami           = "ami-0e1989e836322f58b"  # Replace with the AMI ID for your region
  instance_type = "t3.micro"
  key_name      = "rjm-devops-kp"

  security_groups = [aws_security_group.book_web_sg.name]

  tags = {
    Name = "BookAppLandingPage"
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
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "book_id"

  attribute {
    name = "book_id"
    type = "S"
  }

  attribute {
    name = "book_title"
    type = "S"
  }

  # Define the Global Secondary Index for book_title
  global_secondary_index {
    name               = "book-title-index"
    hash_key           = "book_title"  # The attribute to index
    projection_type    = "ALL"  # You can choose to project only specific attributes if needed
    read_capacity      = 5
    write_capacity     = 5
  }

  # Add more attributes as required
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
