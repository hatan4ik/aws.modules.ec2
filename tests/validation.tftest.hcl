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

run "name_must_be_dns_like" {
  command = plan
  variables { name = "Orders_Worker" }
  expect_failures = [var.name]
}

run "name_too_long" {
  command = plan
  variables { name = "a1234567890123456789012345678901234567890123456789" }
  expect_failures = [var.name]
}

run "subnet_id_shape" {
  command = plan
  variables { subnet_ids = ["vpc-0a1b2c3d4e5f60001"] }
  expect_failures = [var.subnet_ids]
}

run "at_least_one_subnet" {
  command = plan
  variables { subnet_ids = [] }
  expect_failures = [var.subnet_ids]
}

run "at_least_one_security_group" {
  command = plan
  variables { security_group_ids = [] }
  expect_failures = [var.security_group_ids]
}

run "security_group_id_shape" {
  command = plan
  variables { security_group_ids = ["default"] }
  expect_failures = [var.security_group_ids]
}

run "ami_id_shape" {
  command = plan
  variables { ami_id = "al2023" }
  expect_failures = [var.ami_id]
}

run "ami_and_ssm_parameter_together_are_rejected" {
  command = plan

  variables {
    ami_ssm_parameter_name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  }

  expect_failures = [aws_launch_template.this]
}

run "no_image_is_rejected" {
  command = plan
  variables { ami_id = null }
  expect_failures = [aws_launch_template.this]
}

run "ssm_parameter_must_be_a_path" {
  command = plan

  variables {
    ami_id                 = null
    ami_ssm_parameter_name = "al2023"
  }

  expect_failures = [var.ami_ssm_parameter_name]
}

run "instance_type_shape" {
  command = plan
  variables { instance_type = "large" }
  expect_failures = [var.instance_type]
}

run "hop_limit_bounds" {
  command = plan
  variables { metadata_hop_limit = 3 }
  expect_failures = [var.metadata_hop_limit]
}

run "user_data_size" {
  command = plan
  variables { user_data = join("", [for i in range(17) : join("", [for j in range(1000) : "x"])]) } # 17000 characters; range() is capped at 1024
  expect_failures = [var.user_data]
}

run "kms_key_must_be_an_arn" {
  command = plan
  variables { kms_key_arn = "alias/orders" }
  expect_failures = [var.kms_key_arn]
}

run "root_volume_type" {
  command = plan
  variables { root_volume = { type = "standard" } }
  expect_failures = [var.root_volume]
}

run "root_volume_iops_on_gp2" {
  command = plan
  variables { root_volume = { type = "gp2", iops = 3000 } }
  expect_failures = [var.root_volume]
}

run "root_volume_throughput_only_gp3" {
  command = plan
  variables { root_volume = { type = "io2", throughput = 500 } }
  expect_failures = [var.root_volume]
}

run "root_volume_device_name" {
  command = plan
  variables { root_volume = { device_name = "/dev/sdf" } }
  expect_failures = [var.root_volume]
}

run "additional_volume_duplicate_device" {
  command = plan

  variables {
    ebs_volumes = {
      a = { device_name = "/dev/sdf", size_gib = 10 }
      b = { device_name = "/dev/sdf", size_gib = 10 }
    }
  }

  expect_failures = [var.ebs_volumes]
}

run "additional_volume_cannot_use_the_root_device" {
  command = plan

  variables {
    ebs_volumes = {
      a = { device_name = "/dev/xvda", size_gib = 10 }
    }
  }

  expect_failures = [var.ebs_volumes]
}

run "additional_volume_type" {
  command = plan

  variables {
    ebs_volumes = {
      a = { device_name = "/dev/sdf", size_gib = 10, type = "magnetic" }
    }
  }

  expect_failures = [var.ebs_volumes]
}

run "inline_policy_must_be_json" {
  command = plan
  variables { iam_inline_policies = { broken = "not json" } }
  expect_failures = [var.iam_inline_policies]
}

run "managed_policy_arn_shape" {
  command = plan
  variables { iam_policy_arns = { s3 = "AmazonS3ReadOnlyAccess" } }
  expect_failures = [var.iam_policy_arns]
}

run "role_path_shape" {
  command = plan
  variables { iam_role_path = "platform" }
  expect_failures = [var.iam_role_path]
}

run "health_check_type" {
  command = plan
  variables { health_check_type = "HTTP" }
  expect_failures = [var.health_check_type]
}

run "target_group_arn_shape" {
  command = plan
  variables { target_group_arns = ["orders"] }
  expect_failures = [var.target_group_arns]
}

run "termination_policy_name" {
  command = plan
  variables { termination_policies = ["Random"] }
  expect_failures = [var.termination_policies]
}

run "refresh_max_below_min_is_rejected" {
  command = plan
  variables { instance_refresh = { min_healthy_percentage = 90, max_healthy_percentage = 100, instance_warmup = 9000 } }
  expect_failures = [var.instance_refresh]
}

run "cpu_target_bounds" {
  command = plan
  variables { target_tracking_cpu_percent = 95 }
  expect_failures = [var.target_tracking_cpu_percent]
}

run "region_shape" {
  command = plan
  variables { region = "useast2" }
  expect_failures = [var.region]
}

run "partition_value" {
  command = plan
  variables { partition = "azure" }
  expect_failures = [var.partition]
}

run "wait_timeout_shape" {
  command = plan
  variables { wait_for_capacity_timeout = "ten minutes" }
  expect_failures = [var.wait_for_capacity_timeout]
}

run "io2_root_volume_needs_iops" {
  command = plan
  variables { root_volume = { type = "io2" } }
  expect_failures = [var.root_volume]
}

run "gp3_root_iops_below_the_gp3_floor" {
  command = plan
  variables { root_volume = { type = "gp3", iops = 100 } }
  expect_failures = [var.root_volume]
}

run "st1_volume_below_minimum_size" {
  command = plan

  variables {
    ebs_volumes = { cold = { device_name = "/dev/sdf", size_gib = 100, type = "st1" } }
  }

  expect_failures = [var.ebs_volumes]
}

run "io1_additional_volume_needs_iops" {
  command = plan

  variables {
    ebs_volumes = { fast = { device_name = "/dev/sdf", size_gib = 100, type = "io1" } }
  }

  expect_failures = [var.ebs_volumes]
}

run "snapshot_id_shape" {
  command = plan

  variables {
    ebs_volumes = { restore = { device_name = "/dev/sdf", size_gib = 100, snapshot_id = "latest" } }
  }

  expect_failures = [var.ebs_volumes]
}

run "access_value" {
  command = plan
  variables { access = "ssh" }
  expect_failures = [var.access]
}

run "isolated_partitions_are_not_supported" {
  command = plan
  variables { partition = "aws-iso" }
  expect_failures = [var.partition]
}

run "policy_arn_label_shape" {
  command = plan
  variables { iam_policy_arns = { "not a label" = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" } }
  expect_failures = [var.iam_policy_arns]
}
