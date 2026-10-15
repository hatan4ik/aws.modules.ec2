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

  kms_key_arn      = "arn:aws:kms:us-east-2:123456789012:key/11111111-2222-3333-4444-555555555555"
  instance_refresh = { min_healthy_percentage = 100, max_healthy_percentage = 200 }
}

run "ssm_is_the_default_and_uses_no_key_pair" {
  command = plan

  assert {
    condition     = output.access == "ssm" && aws_launch_template.this.key_name == null && length(aws_key_pair.this) == 0 && output.key_pair_name == null
    error_message = "access = ssm must launch without a key pair and register none."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm) == 1
    error_message = "access = ssm must attach the SSM managed policy."
  }
}

run "key_pair_by_name_uses_the_existing_key_and_skips_ssm" {
  command = plan

  variables {
    access        = "key_pair"
    key_pair_name = "ops-key"
  }

  assert {
    condition     = aws_launch_template.this.key_name == "ops-key" && length(aws_key_pair.this) == 0 && output.key_pair_name == "ops-key" && output.access == "key_pair"
    error_message = "An existing key pair must be referenced by name and none registered."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm) == 0 && length(aws_iam_role.this) == 1
    error_message = "access = key_pair must not attach the SSM policy by default, but must still create the instance role."
  }
}

run "key_pair_from_public_key_registers_it_under_the_fleet_name" {
  command = plan

  variables {
    access              = "key_pair"
    key_pair_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl ops@example"
  }

  assert {
    condition     = length(aws_key_pair.this) == 1 && aws_key_pair.this[0].key_name_prefix == "orders-worker-" && aws_key_pair.this[0].public_key == "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl ops@example"
    error_message = "A public key must be registered as a key pair named with the fleet-name prefix, so a replacement can coexist with the old one."
  }

  assert {
    condition     = aws_key_pair.this[0].tags["Name"] == "orders-worker"
    error_message = "The registered key pair must carry the fleet tags. (Its generated name is unknown at plan, so the launch template wiring is covered by the integration suite.)"
  }
}

run "both_keeps_ssm_and_adds_the_key_pair" {
  command = plan

  variables {
    access        = "both"
    key_pair_name = "ops-key"
  }

  assert {
    condition     = aws_launch_template.this.key_name == "ops-key" && length(aws_iam_role_policy_attachment.ssm) == 1
    error_message = "access = both must launch with the key pair and keep the SSM managed policy."
  }
}

run "key_pair_can_still_opt_in_to_the_ssm_policy" {
  command = plan

  variables {
    access                        = "key_pair"
    key_pair_name                 = "ops-key"
    iam_attach_ssm_managed_policy = true
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm) == 1
    error_message = "An explicit iam_attach_ssm_managed_policy = true must win over the access default."
  }
}

run "key_pair_access_requires_a_key" {
  command = plan

  variables {
    access = "key_pair"
  }

  expect_failures = [aws_launch_template.this]
}

run "name_and_public_key_together_are_rejected" {
  command = plan

  variables {
    access              = "key_pair"
    key_pair_name       = "ops-key"
    key_pair_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
  }

  expect_failures = [aws_launch_template.this]
}

run "key_inputs_with_ssm_access_are_rejected" {
  command = plan

  variables {
    key_pair_name = "ops-key"
  }

  expect_failures = [aws_launch_template.this]
}

run "private_key_is_rejected" {
  command = plan

  variables {
    access = "key_pair"
    # Assembled so the file never contains a literal private key header (secret
    # scanners match on it); the value is a header with a stub body, not a key.
    key_pair_public_key = join("", ["-----", "BEGIN OPENSSH PRIV", "ATE KEY-----", "\n", "stub", "\n", "-----", "END OPENSSH PRIV", "ATE KEY-----"])
  }

  expect_failures = [var.key_pair_public_key]
}

run "unsupported_key_type_is_rejected" {
  command = plan

  variables {
    access              = "key_pair"
    key_pair_public_key = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
  }

  expect_failures = [var.key_pair_public_key]
}

run "key_pair_name_shape" {
  command = plan

  variables {
    access        = "key_pair"
    key_pair_name = ""
  }

  expect_failures = [var.key_pair_name]
}
