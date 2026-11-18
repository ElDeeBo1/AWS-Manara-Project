# ---------------------------------------------------------------
# EC2 Launch Template, Auto Scaling group and scaling policies
# IAM role for Systems Manager Session Manager (no SSH, no bastion)
# Diagram part: 04-compute-asg
# ---------------------------------------------------------------

# Latest Amazon Linux 2023 AMI, resolved through the public SSM parameter
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ----- IAM role + instance profile -----
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${local.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Session Manager access
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Allow the app to read the database credentials from Secrets Manager
data "aws_iam_policy_document" "read_db_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.main.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "read_db_secret" {
  name   = "read-db-secret"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.read_db_secret.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ----- Launch Template -----
resource "aws_launch_template" "web" {
  name_prefix   = "${local.name_prefix}-lt-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  # IMDSv2 only
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    project_name = var.project_name
  }))

  tag_specifications {
    resource_type = "instance"

    tags = { Name = "${local.name_prefix}-web" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ----- Auto Scaling group across both app subnets -----
resource "aws_autoscaling_group" "web" {
  name                      = "${local.name_prefix}-asg"
  min_size                  = var.asg_min_size
  desired_capacity          = var.asg_desired_capacity
  max_size                  = var.asg_max_size
  vpc_zone_identifier       = aws_subnet.app[*].id
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 120
  metrics_granularity       = "1Minute"

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMinSize",
    "GroupMaxSize",
  ]

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-web"
    propagate_at_launch = true
  }

  # The target group must be attached to a listener, and the database must
  # exist, before the first instances come up
  depends_on = [aws_lb_listener.http, aws_db_instance.main]
}

# ----- Target tracking: keep average CPU near the target -----
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${local.name_prefix}-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = var.cpu_target_value
  }
}

# ----- Target tracking: keep requests per instance near the target -----
resource "aws_autoscaling_policy" "requests_target_tracking" {
  name                   = "${local.name_prefix}-requests-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.app.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }

    target_value = var.requests_per_target
  }
}

# ----- Step scaling: faster reaction to sudden CPU spikes -----
resource "aws_autoscaling_policy" "cpu_step_scale_out" {
  name                   = "${local.name_prefix}-cpu-step-scale-out"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "StepScaling"
  adjustment_type        = "ChangeInCapacity"

  # Alarm threshold is 80 percent CPU (see monitoring.tf)
  step_adjustment {
    metric_interval_lower_bound = 0
    metric_interval_upper_bound = 10
    scaling_adjustment          = 1
  }

  step_adjustment {
    metric_interval_lower_bound = 10
    scaling_adjustment          = 2
  }
}
