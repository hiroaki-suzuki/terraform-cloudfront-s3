terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.60.0"
    }
  }
}

provider "aws" {
  region     = "ap-northeast-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

locals {
  app_name    = "organizing-thoughts"
  name_prefix = "${local.app_name}-${var.env}"
}

# フロントエンドバケットの作成
resource "aws_s3_bucket" "front-app" {
  bucket = "${var.env}.${local.app_name}.com"

  tags = {
    Environment = var.env
  }
}

# フロントエンドバケットACLの作成
resource "aws_s3_bucket_acl" "front-app" {
  bucket = aws_s3_bucket.front-app.id
  acl    = "private"
}

# フロントエンドバケットのブロックパブリックアクセス設定の作成
resource "aws_s3_bucket_public_access_block" "front-app" {
  bucket                  = aws_s3_bucket.front-app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# フロントエンドバケットの暗号化設定の作成
resource "aws_s3_bucket_server_side_encryption_configuration" "front-app" {
  bucket = aws_s3_bucket.front-app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# フロントエンドバケットのウェブサイト設定の作成
resource "aws_s3_bucket_website_configuration" "front-app" {
  bucket = aws_s3_bucket.front-app.id

  index_document {
    suffix = "index.html"
  }
}

# フロントエンドバケットのバケットポリシーの作成
resource "aws_s3_bucket_policy" "front-app" {
  bucket = aws_s3_bucket.front-app.id
  policy = data.aws_iam_policy_document.front-app.json
}

# フロントエンドバケットのバケットポリシーのポリシーの作成
data "aws_iam_policy_document" "front-app" {
  statement {
    sid    = "Allow CloudFront"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [
        "arn:aws:iam::${var.aws_account}:root",
        aws_cloudfront_origin_access_identity.front-app.iam_arn,
      ]
    }
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${aws_s3_bucket.front-app.arn}/*",
    ]
  }
}

# CloudFrontの作成
resource "aws_cloudfront_distribution" "front-app" {
  origin {
    domain_name = aws_s3_bucket.front-app.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.front-app.id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.front-app.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.name_prefix}-front-app"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = aws_s3_bucket.front-app.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["JP"]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    # TODO : ACMの証明書を指定する
    #    acm_certificate_arn      = var.acm_certificate_arn
    #    ssl_support_method       = "sni-only"
    #    minimum_protocol_version = "TLSv1.2_2019"
  }

  tags = {
    Environment = var.env
  }
}

# CloudFrontのアクセス許可設定の作成
resource "aws_cloudfront_origin_access_identity" "front-app" {}