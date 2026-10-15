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

run "secure_defaults" {
  command = plan

  assert {
    condition = (
      aws_launch_template.this.metadata_options[0].http_tokens == "required" &&
      aws_launch_template.this.metadata_options[0].http_endpoint == "enabled" &&
      aws_launch_template.this.metadata_options[0].http_put_response_hop_limit == 1 &&
      aws_launch_template.this.metadata_options[0].instance_metadata_tags == "disabled"
    )
    error_message = "IMDSv2 must be required with a hop limit of 1 and instance metadata tags off."
  }

  assert {
    condition     = aws_launch_template.this.network_interfaces[0].associate_public_ip_address == "false" && aws_launch_template.this.network_interfaces[0].device_index == 0
    error_message = "Instances must never get a public IP address."
  }

  assert {
    condition     = aws_launch_template.this.monitoring[0].enabled == false
    error_message = "Detailed monitoring is off by default."
  }

  assert {
    condition     = aws_launch_template.this.key_name == null && output.key_pair_name == null && output.access == "ssm"
    error_message = "The default access is Session Manager with no key pair."
  }

  assert {
    condition = (
      length(aws_launch_template.this.block_device_mappings) == 1 &&
      aws_launch_template.this.block_device_mappings[0].device_name == "/dev/xvda" &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].encrypted == "true" &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].volume_type == "gp3" &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].volume_size == 30 &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].delete_on_termination == "true"
    )
    error_message = "The root volume must be an encrypted 30 GiB gp3 volume that is deleted with the instance."
  }

  assert {
    condition     = aws_launch_template.this.image_id == "ami-0a1b2c3d4e5f60001" && aws_launch_template.this.instance_type == "m7g.large"
    error_message = "The AMI and instance type must reach the launch template unchanged."
  }

  assert {
    condition     = aws_launch_template.this.user_data == null
    error_message = "No user data is set unless the caller provides it."
  }
}

run "fleet_defaults" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.this.name == "orders-worker" && aws_autoscaling_group.this.min_size == 1 && aws_autoscaling_group.this.max_size == 1
    error_message = "The default fleet is a single instance."
  }

  assert {
    condition     = aws_autoscaling_group.this.health_check_type == "EC2" && aws_autoscaling_group.this.health_check_grace_period == 300
    error_message = "Health checks default to EC2 with a 300 second grace period."
  }

  assert {
    condition     = length(aws_autoscaling_policy.cpu) == 0 && output.scaling_policy_arn == null
    error_message = "No scaling policy exists unless target_tracking_cpu_percent is set."
  }
}

run "tags_reach_instances_volumes_and_interfaces" {
  command = plan

  variables {
    tags = { team = "orders", Name = "caller-wins" }
  }

  assert {
    condition = alltrue([
      for spec in aws_launch_template.this.tag_specifications :
      spec.tags["team"] == "orders" && spec.tags["Name"] == "caller-wins"
    ])
    error_message = "Every tag specification must carry the caller's tags, and a caller Name must win."
  }

  assert {
    condition     = toset([for spec in aws_launch_template.this.tag_specifications : spec.resource_type]) == toset(["instance", "volume", "network-interface"])
    error_message = "Tags must be applied to instances, volumes, and network interfaces."
  }

  assert {
    condition     = aws_launch_template.this.tags["team"] == "orders"
    error_message = "The launch template itself must be tagged."
  }
}

run "name_tag_defaults_to_name" {
  command = plan

  assert {
    condition     = alltrue([for spec in aws_launch_template.this.tag_specifications : spec.tags["Name"] == "orders-worker"])
    error_message = "Name must default to the fleet name."
  }
}

run "user_data_is_base64_encoded" {
  command = plan

  variables {
    user_data = "#!/bin/bash\necho hello\n"
  }

  assert {
    condition     = aws_launch_template.this.user_data == base64encode("#!/bin/bash\necho hello\n")
    error_message = "user_data must be base64 encoded for the launch template."
  }
}

run "hop_limit_two_for_containers" {
  command = plan

  variables {
    metadata_hop_limit = 2
  }

  assert {
    condition     = aws_launch_template.this.metadata_options[0].http_put_response_hop_limit == 2 && aws_launch_template.this.metadata_options[0].http_tokens == "required"
    error_message = "A hop limit of 2 must not relax the IMDSv2 requirement."
  }
}

run "detailed_monitoring_opt_in" {
  command = plan

  variables {
    detailed_monitoring = true
  }

  assert {
    condition     = aws_launch_template.this.monitoring[0].enabled == true
    error_message = "detailed_monitoring must switch the launch template monitoring on."
  }
}

run "ssm_parameter_image_is_resolved_by_ec2" {
  command = plan

  variables {
    ami_id                 = null
    ami_ssm_parameter_name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
  }

  assert {
    condition     = aws_launch_template.this.image_id == "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
    error_message = "An SSM parameter image must be passed to EC2 with the resolve:ssm: prefix."
  }

  assert {
    condition     = output.image_id == "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
    error_message = "The image_id output must show what the launch template uses."
  }
}

run "default_instance_refresh_is_rolling_at_90_percent" {
  command = plan

  variables {
    max_size         = 2
    instance_refresh = {}
  }

  assert {
    condition = (
      length(aws_autoscaling_group.this.instance_refresh) == 1 &&
      aws_autoscaling_group.this.instance_refresh[0].strategy == "Rolling" &&
      aws_autoscaling_group.this.instance_refresh[0].preferences[0].min_healthy_percentage == 90
    )
    error_message = "Rolling instance refresh at 90 percent healthy must be on by default."
  }
}

run "desired_capacity_passes_through_when_set" {
  command = plan

  variables {
    min_size         = 1
    max_size         = 4
    desired_capacity = 3
  }

  assert {
    condition     = aws_autoscaling_group.this.desired_capacity == 3
    error_message = "A desired_capacity set by the caller must reach the group. (Left null it is computed by AWS, which a mocked provider cannot show.)"
  }
}
