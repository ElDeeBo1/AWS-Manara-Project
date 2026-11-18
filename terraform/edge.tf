# ---------------------------------------------------------------
# CloudFront (dynamic traffic to the ALB, /static/* from S3),
# S3 static bucket with Origin Access Control, Route 53
# Diagram part: 01-edge-route53-cloudfront-s3
# ---------------------------------------------------------------

# ----- S3 bucket for static assets (private, only CloudFront can read) -----
resource "aws_s3_bucket" "static" {
  bucket        = "${local.name_prefix}-static-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = { Name = "${local.name_prefix}-static" }
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.static.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "static" {
  bucket = aws_s3_bucket.static.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static" {
  bucket = aws_s3_bucket.static.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Sample static asset, referenced by the web page as /static/style.css
resource "aws_s3_object" "style" {
  bucket       = aws_s3_bucket.static.id
  key          = "static/style.css"
  content_type = "text/css"
  content      = "body { font-family: sans-serif; margin: 3rem; } h1 { color: #232f3e; }\n"
}

data "aws_iam_policy_document" "static_bucket" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.main.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.static.id
  policy = data.aws_iam_policy_document.static_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.static]
}

# ----- CloudFront -----
resource "aws_cloudfront_origin_access_control" "static" {
  name                              = "${local.name_prefix}-static-oac"
  description                       = "OAC for the static assets bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "main" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${local.name_prefix} web app"
  price_class     = "PriceClass_100"
  aliases         = var.domain_name == "" ? [] : [var.domain_name]

  # Origin 1: the Application Load Balancer (dynamic content)
  origin {
    origin_id   = "alb"
    domain_name = aws_lb.app.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Origin 2: the S3 bucket (static assets)
  origin {
    origin_id                = "s3-static"
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.static.id
  }

  # Default: dynamic traffic goes to the ALB, no caching
  default_cache_behavior {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # Managed policy: CachingDisabled
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    # Managed policy: AllViewer
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
  }

  # Static assets are cached at the edge and served from S3
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "s3-static"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # Managed policy: CachingOptimized
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == ""
    acm_certificate_arn            = var.acm_certificate_arn == "" ? null : var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn == "" ? null : "sni-only"
    minimum_protocol_version       = var.acm_certificate_arn == "" ? null : "TLSv1.2_2021"
  }

  tags = { Name = "${local.name_prefix}-cdn" }
}

# ----- Route 53 -----
# Health check against the public endpoint (through CloudFront to the ALB)
resource "aws_route53_health_check" "web" {
  type              = "HTTPS"
  fqdn              = aws_cloudfront_distribution.main.domain_name
  port              = 443
  resource_path     = "/health"
  request_interval  = 30
  failure_threshold = 3

  tags = { Name = "${local.name_prefix}-health-check" }
}

# Alias record to CloudFront, created only when a custom domain is configured
resource "aws_route53_record" "alias" {
  count = var.domain_name != "" && var.hosted_zone_id != "" ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
