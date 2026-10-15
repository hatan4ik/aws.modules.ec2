mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

variables {
  name               = "orders-worker"
  subnet_ids         = ["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002"]
  security_group_ids = ["sg-0a1b2c3d4e5f60001"]
  ami_id             = "ami-0a1b2c3d4e5f60001"
  instance_type      = "m7g.large"

  # Keep the advisory checks quiet in every run that is not about them;
  # tests/checks.tftest.hcl proves each one fires.
  kms_key_arn      = "arn:aws:kms:us-east-2:123456789012:key/11111111-2222-3333-4444-555555555555"
  instance_refresh = { min_healthy_percentage = 100, max_healthy_percentage = 200 }
}

run "behind_a_load_balancer" {
  command = plan

  variables {
    min_size                  = 2
    max_size                  = 6
    health_check_type         = "ELB"
    health_check_grace_period = 120
    target_group_arns         = ["arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/orders/0123456789abcdef"]
  }

  assert {
    condition = (
      aws_autoscaling_group.this.min_size == 2 &&
      aws_autoscaling_group.this.max_size == 6 &&
      aws_autoscaling_group.this.health_check_type == "ELB" &&
      aws_autoscaling_group.this.health_check_grace_period == 120 &&
      length(aws_autoscaling_group.this.target_group_arns) == 1
    )
    error_message = "Sizes, health check, and target group registration must pass through."
  }

  assert {
    condition     = toset(aws_autoscaling_group.this.vpc_zone_identifier) == toset(var.subnet_ids)
    error_message = "The group must launch into exactly the supplied subnets."
  }
}

run "target_tracking_policy" {
  command = plan

  variables {
    min_size                    = 2
    max_size                    = 6
    target_tracking_cpu_percent = 55
  }

  assert {
    condition = (
      length(aws_autoscaling_policy.cpu) == 1 &&
      aws_autoscaling_policy.cpu[0].policy_type == "TargetTrackingScaling" &&
      aws_autoscaling_policy.cpu[0].target_tracking_configuration[0].target_value == 55 &&
      aws_autoscaling_policy.cpu[0].target_tracking_configuration[0].predefined_metric_specification[0].predefined_metric_type == "ASGAverageCPUUtilization"
    )
    error_message = "A CPU target tracking policy must be created at the requested target."
  }
}

run "single_instance_blue_green_refresh" {
  command = plan

  variables {
    instance_refresh = {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = 90
    }
  }

  assert {
    condition = (
      aws_autoscaling_group.this.instance_refresh[0].preferences[0].min_healthy_percentage == 100 &&
      aws_autoscaling_group.this.instance_refresh[0].preferences[0].max_healthy_percentage == 200 &&
      aws_autoscaling_group.this.instance_refresh[0].preferences[0].instance_warmup == "90"
    )
    error_message = "Refresh preferences must pass through."
  }
}

run "instance_refresh_can_be_disabled" {
  command = plan

  variables {
    instance_refresh = { enabled = false }
  }

  assert {
    condition     = length(aws_autoscaling_group.this.instance_refresh) == 0
    error_message = "enabled = false must remove the instance_refresh block."
  }
}

run "min_above_max_is_rejected" {
  command = plan

  variables {
    min_size = 3
    max_size = 2
  }

  expect_failures = [aws_autoscaling_group.this]
}

run "desired_outside_range_is_rejected" {
  command = plan

  variables {
    min_size         = 1
    max_size         = 3
    desired_capacity = 5
  }

  expect_failures = [aws_autoscaling_group.this]
}

run "protected_instances_are_refreshed_too" {
  command = plan

  variables {
    protect_from_scale_in = true
    min_size              = 2
    max_size              = 4
  }

  assert {
    condition     = aws_autoscaling_group.this.protect_from_scale_in == true && aws_autoscaling_group.this.instance_refresh[0].preferences[0].scale_in_protected_instances == "Refresh"
    error_message = "A fleet that launches scale-in protected instances must still roll them on a launch template change."
  }
}

run "unprotected_fleet_leaves_scale_in_protection_default" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.this.instance_refresh[0].preferences[0].scale_in_protected_instances == null
    error_message = "scale_in_protected_instances is only set for a protected fleet."
  }
}

run "refresh_band_of_exactly_100_points_is_accepted" {
  command = plan

  variables {
    instance_refresh = { min_healthy_percentage = 100, max_healthy_percentage = 200 }
  }

  assert {
    condition     = aws_autoscaling_group.this.instance_refresh[0].preferences[0].max_healthy_percentage == 200
    error_message = "min 100 / max 200 is the documented zero-downtime band and must be accepted."
  }
}

run "refresh_band_wider_than_100_points_is_rejected" {
  command = plan

  variables {
    instance_refresh = { max_healthy_percentage = 200 }
  }

  expect_failures = [var.instance_refresh]
}
