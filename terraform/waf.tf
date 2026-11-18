# ---------------------------------------------------------------
# AWS WAF (regional) attached to the ALB, OWASP Top 10 oriented
# Diagram part: 03-security-waf-alb
# ---------------------------------------------------------------

locals {
  waf_managed_rule_groups = {
    # Covers many OWASP Top 10 risks (XSS, LFI, bad bots, etc.)
    AWSManagedRulesCommonRuleSet = 10
    # Blocks requests with patterns known to exploit vulnerabilities (for example Log4j)
    AWSManagedRulesKnownBadInputsRuleSet = 20
    # SQL injection protection
    AWSManagedRulesSQLiRuleSet = 30
  }
}

resource "aws_wafv2_web_acl" "alb" {
  name        = "${local.name_prefix}-web-acl"
  description = "OWASP Top 10 protection for the ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Rate limit per client IP. Traffic arrives through CloudFront, so the client
  # IP is read from the X-Forwarded-For header.
  rule {
    name     = "RateLimitPerIP"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "FORWARDED_IP"

        forwarded_ip_config {
          header_name       = "X-Forwarded-For"
          fallback_behavior = "MATCH"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerIP"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = local.waf_managed_rule_groups

    content {
      name     = rule.key
      priority = rule.value

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${local.name_prefix}-web-acl" }
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.app.arn
  web_acl_arn  = aws_wafv2_web_acl.alb.arn
}
