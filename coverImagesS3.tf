############################
# Vars
############################
variable "env" {
  description = "Environment name (dev|test|prod)"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name for images (must be globally unique)"
  type        = string
  default     = null
}

variable "allowed_put_origins" {
  description = "Origins allowed to upload via presigned PUT (CORS). Dev default allows CRA."
  type        = list(string)
  default     = ["http://localhost:3000"]
}

# Optional: IAM role name used by your Spring app to generate presigned URLs
variable "app_role_name" {
  description = "IAM role name of the backend service (for presign PUT/HeadObject). Leave null to skip policy attachment."
  type        = string
  default     = null
}

# Create a role in this module (optional).
variable "app_role_create" {
  description = "Create the backend IAM role in this module"
  type        = bool
  default     = false
}

variable "app_role_trust" {
  description = "Service that will assume the role when app_role_create=true (ecs|ec2|lambda)"
  type        = string
  default     = "ecs"
  validation {
    condition     = contains(["ecs", "ec2", "lambda"], var.app_role_trust)
    error_message = "app_role_trust must be one of: ecs, ec2, lambda."
  }
}

############################
# Provider sanity (optional but recommended)
############################
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.30"
    }
  }
}

############################
# Data
############################
data "aws_caller_identity" "current" {}

# Managed policies for CloudFront convenience
data "aws_cloudfront_cache_policy" "managed_caching_optimized" {
  name = "Managed-CachingOptimized"
}

# Managed CORS with preflight (exact name, case-sensitive)
data "aws_cloudfront_response_headers_policy" "managed_cors_with_preflight" {
  name = "Managed-CORS-With-Preflight"
}

############################
# S3 bucket (private)
############################
resource "aws_s3_bucket" "covers" {
  bucket = coalesce(var.bucket_name, "books-eda-images-${var.env}")
}

# Disable ACLs, bucket-owner enforced
resource "aws_s3_bucket_ownership_controls" "covers" {
  bucket = aws_s3_bucket.covers.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Block ALL public access
resource "aws_s3_bucket_public_access_block" "covers" {
  bucket                  = aws_s3_bucket.covers.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Server-side encryption (SSE-S3). Use KMS if you prefer.
resource "aws_s3_bucket_server_side_encryption_configuration" "covers" {
  bucket = aws_s3_bucket.covers.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# (Optional) Versioning for rollback / overwrites
resource "aws_s3_bucket_versioning" "covers" {
  bucket = aws_s3_bucket.covers.id
  versioning_configuration { status = "Enabled" }
}

# CORS for browser uploads (presigned PUT) + GET for previews
resource "aws_s3_bucket_cors_configuration" "covers" {
  bucket = aws_s3_bucket.covers.id

  cors_rule {
    allowed_methods = ["PUT"]
    allowed_origins = var.allowed_put_origins
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }

  cors_rule {
    allowed_methods = ["GET"]
    allowed_origins = ["*"] # reads will go through CloudFront, but GET preflight sometimes hits S3 during dev tools
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

############################
# CloudFront (public) -> S3 (private via OAC)
############################
resource "aws_cloudfront_origin_access_control" "covers" {
  name                              = "books-covers-oac-${var.env}"
  description                       = "OAC for private S3 images"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "covers" {
  enabled         = true
  is_ipv6_enabled = true
  price_class     = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.covers.bucket_regional_domain_name
    origin_id                = "s3-covers-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.covers.id
  }

  default_cache_behavior {
    # ✅ match the origin_id above
    target_origin_id            = "s3-covers-origin"
    viewer_protocol_policy      = "redirect-to-https"
    allowed_methods             = ["GET", "HEAD", "OPTIONS"]
    cached_methods              = ["GET", "HEAD", "OPTIONS"]
    compress                    = true

    cache_policy_id             = data.aws_cloudfront_cache_policy.managed_caching_optimized.id
    response_headers_policy_id  = data.aws_cloudfront_response_headers_policy.managed_cors_with_preflight.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Use default cert for now (adds a *.cloudfront.net domain). Swap to ACM cert + aliases for custom domain later.
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    App = "books-eda"
    Env = var.env
  }
}

# Allow ONLY CloudFront distribution to read objects from S3 (via OAC)
resource "aws_s3_bucket_policy" "covers_allow_cf" {
  bucket = aws_s3_bucket.covers.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOACRead",
        Effect    = "Allow",
        Principal = { Service = "cloudfront.amazonaws.com" },
        Action    = ["s3:GetObject"],
        Resource  = "${aws_s3_bucket.covers.arn}/*",
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.covers.arn
          }
        }
      }
    ]
  })
}

############################
# IAM policy for the backend role (presign PUT, optional)
############################
# When you presign, the request is authorized as the signing principal.
# So your app role MUST have permission to PutObject/AbortMultipart/HeadObject on the bucket/prefix you use.
locals {
  covers_prefix_arn = "${aws_s3_bucket.covers.arn}/*"
  trust_principal = {
    ecs    = "ecs-tasks.amazonaws.com"
    ec2    = "ec2.amazonaws.com"
    lambda = "lambda.amazonaws.com"
  }
}

resource "aws_iam_policy" "app_covers_write" {
  name        = "books-covers-write-${var.env}"
  description = "Allow app to presign PUT/HEAD for images bucket (no public access)."
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "PutAndAbortMultipart",
        Effect = "Allow",
        Action = ["s3:PutObject", "s3:AbortMultipartUpload"],
        Resource = local.covers_prefix_arn
      },
      {
        Sid    = "HeadAndGetForChecks",
        Effect = "Allow",
        Action = ["s3:HeadObject", "s3:GetObject"],
        Resource = local.covers_prefix_arn
      }
    ]
  })
}

# Create the role here, if requested
resource "aws_iam_role" "backend" {
  count = var.app_role_create ? 1 : 0
  name  = coalesce(var.app_role_name, "books-backend-role-${var.env}")

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = local.trust_principal[var.app_role_trust] },
      Action    = "sts:AssumeRole"
    }]
  })
}

# For EC2, you typically need an instance profile
resource "aws_iam_instance_profile" "backend" {
  count = (var.app_role_create && var.app_role_trust == "ec2") ? 1 : 0
  name  = "books-backend-profile-${var.env}"
  role  = aws_iam_role.backend[0].name
}

# (B2) Attach the policy to the role we CREATE here
resource "aws_iam_role_policy_attachment" "attach_app_covers_write_created" {
  count      = var.app_role_create ? 1 : 0
  role       = aws_iam_role.backend[0].name
  policy_arn = aws_iam_policy.app_covers_write.arn
}

# (A) Attach the policy to an EXISTING role by name (if provided)
resource "aws_iam_role_policy_attachment" "attach_app_covers_write_existing" {
  count      = (!var.app_role_create && var.app_role_name != null) ? 1 : 0
  role       = var.app_role_name
  policy_arn = aws_iam_policy.app_covers_write.arn
}

############################
# Outputs
############################
output "covers_bucket_name" {
  value       = aws_s3_bucket.covers.bucket
  description = "Private S3 bucket holding book covers"
}

output "covers_cloudfront_domain" {
  value       = aws_cloudfront_distribution.covers.domain_name
  description = "Public viewer domain for book covers (set REACT_APP_IMAGE_BASE to https://<this>)"
}

output "covers_base_url" {
  value       = "https://${aws_cloudfront_distribution.covers.domain_name}"
  description = "Use in the frontend as REACT_APP_IMAGE_BASE"
}
