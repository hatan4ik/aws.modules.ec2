# Each advisory check must fire on the configuration it describes. In
# terraform test a failing check is a failure, so expect_failures is how a
# warning is asserted here.

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
  kms_key_arn        = "arn:aws:kms:us-east-2:123456789012:key/11111111-2222-3333-4444-555555555555"
  instance_refresh   = { min_healthy_percentage = 100, max_healthy_percentage = 200 }
}

run "quiet_when_configured_as_intended" {
  command = plan
}

run "default_ebs_key_is_flagged" {
  command = plan

  variables {
    kms_key_arn = null
  }

  expect_failures = [check.volumes_use_aws_managed_key]
}

run "one_volume_without_a_key_is_flagged" {
  command = plan

  variables {
    kms_key_arn = null
    root_volume = { kms_key_arn = "arn:aws:kms:us-east-2:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }
    ebs_volumes = { data = { device_name = "/dev/sdf", size_gib = 10 } }
  }

  expect_failures = [check.volumes_use_aws_managed_key]
}

run "single_subnet_is_flagged" {
  command = plan

  variables {
    subnet_ids = ["subnet-0a1b2c3d4e5f60001"]
  }

  expect_failures = [check.single_subnet]
}

run "elb_health_without_target_groups_is_flagged" {
  command = plan

  variables {
    health_check_type = "ELB"
  }

  expect_failures = [check.elb_health_check_without_target_groups]
}

run "role_without_any_permission_is_flagged" {
  command = plan

  variables {
    iam_attach_ssm_managed_policy = false
  }

  expect_failures = [check.no_way_into_the_instances]
}

run "scaling_policy_on_fixed_size_group_is_flagged" {
  command = plan

  variables {
    target_tracking_cpu_percent = 50
  }

  expect_failures = [check.target_tracking_cannot_scale]
}

run "single_instance_default_refresh_is_flagged" {
  command = plan

  variables {
    instance_refresh = {}
  }

  expect_failures = [check.single_instance_refresh_has_downtime]
}

run "administrator_policy_is_flagged" {
  command = plan

  variables {
    iam_policy_arns = { admin = "arn:aws:iam::aws:policy/AdministratorAccess" }
  }

  expect_failures = [check.broad_instance_role]
}

run "wildcard_inline_statement_is_flagged" {
  command = plan

  variables {
    iam_inline_policies = {
      everything = jsonencode({
        Version   = "2012-10-17"
        Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }]
      })
    }
  }

  expect_failures = [check.broad_instance_role]
}

run "scoped_inline_statement_is_not_flagged" {
  command = plan

  variables {
    iam_inline_policies = {
      config = jsonencode({
        Version   = "2012-10-17"
        Statement = [{ Effect = "Allow", Action = ["s3:GetObject"], Resource = ["arn:aws:s3:::orders-config/*"] }]
      })
    }
  }
}

run "single_instance_with_band_below_200_is_still_flagged" {
  command = plan

  variables {
    instance_refresh = { min_healthy_percentage = 100, max_healthy_percentage = 150 }
  }

  expect_failures = [check.single_instance_refresh_has_downtime]
}

run "key_pair_without_ssm_policy_is_not_flagged_as_unreachable" {
  command = plan

  variables {
    access        = "key_pair"
    key_pair_name = "ops-key"
  }
}
