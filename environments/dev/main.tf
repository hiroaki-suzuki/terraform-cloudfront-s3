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
  app_name    = "hs-cloudfront-s3"
  name_prefix = "${local.app_name}-${var.env}"
}

# ================================================================================
# Resource
# ================================================================================

# フロントエンドデプロイ用IAMユーザーの作成
resource "aws_iam_user" "front-app-deploy" {
  name = "${local.name_prefix}-front-app-deploy"

  tags = {
    Environment = "dev"
  }
}

# フロントエンドデプロイ用IAMユーザーのポリシーの作成
data "aws_iam_policy_document" "front-app-deploy" {
  statement {
    effect  = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = ["${aws_s3_bucket.front-app.arn}/*"]
  }
}

# フロントエンドデプロイ用IAMユーザーのポリシーのアタッチ
resource "aws_iam_user_policy" "front-app-deploy" {
  name   = "${local.name_prefix}-front-app-deploy-policy"
  user   = aws_iam_user.front-app-deploy.name
  policy = data.aws_iam_policy_document.front-app-deploy.json
}

resource "aws_iam_access_key" "front-app-deploy" {
  user    = aws_iam_user.front-app-deploy.name
  pgp_key = var.front_app_deployer_gpg
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
        aws_iam_user.front-app-deploy.arn
      ]
    }
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "${aws_s3_bucket.front-app.arn}/*",
      aws_s3_bucket.front-app.arn
    ]
  }
}

# Basic認証のCloudFront Functionの作成
resource "aws_cloudfront_function" "front-app" {
  name    = "${local.name_prefix}-basic-auth"
  runtime = "cloudfront-js-1.0"
  comment = "Basic Auth"
  publish = true
  code    = <<EOT
function handler(event) {
    var request = event.request;
    var headers = request.headers;
    var authString = "Basic xxxxxxxxxxxxxxxxxxxx";

    if (
        typeof headers.authorization === "undefined" ||
        headers.authorization.value !== authString
    ) {
        return {
            statusCode: 401,
            statusDescription: "Unauthorized",
            headers: { "www-authenticate": { value: "Basic" } }
        };
    }

    return request;
}
EOT
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

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.front-app.arn
    }
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

# ================================================================================
# Outputs
# ================================================================================

# フロンド資材のデプロイ用ユーザーのシークレットアクセスキーの出力
output "front-app-deployer-secret" {
  value = aws_iam_access_key.front-app-deploy.encrypted_secret
}
