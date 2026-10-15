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

run "module_key_encrypts_every_volume" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-2:123456789012:key/11111111-2222-3333-4444-555555555555"
    ebs_volumes = {
      data = { device_name = "/dev/sdf", size_gib = 100 }
      logs = { device_name = "/dev/sdg", size_gib = 20, type = "gp3", throughput = 250, iops = 4000 }
    }
  }

  assert {
    condition = alltrue([
      for mapping in aws_launch_template.this.block_device_mappings :
      mapping.ebs[0].encrypted == "true" && mapping.ebs[0].kms_key_id == "arn:aws:kms:us-east-2:123456789012:key/11111111-2222-3333-4444-555555555555"
    ])
    error_message = "Every volume must be encrypted with the module-level key."
  }

  assert {
    condition     = length(aws_launch_template.this.block_device_mappings) == 3
    error_message = "The root volume and both additional volumes must be mapped."
  }
}

run "per_volume_key_overrides_module_key" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-2:123456789012:key/11111111-2222-3333-4444-555555555555"
    root_volume = { kms_key_arn = "arn:aws:kms:us-east-2:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }
    ebs_volumes = {
      data = { device_name = "/dev/sdf", size_gib = 100, kms_key_arn = "arn:aws:kms:us-east-2:123456789012:key/99999999-8888-7777-6666-555555555555" }
    }
  }

  assert {
    condition     = local.root_kms_key_arn == "arn:aws:kms:us-east-2:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    error_message = "The root volume key must override the module-level key."
  }

  assert {
    condition     = local.volume_kms_key_arns["data"] == "arn:aws:kms:us-east-2:123456789012:key/99999999-8888-7777-6666-555555555555"
    error_message = "A per-volume key must override the module-level key."
  }
}

run "no_key_still_encrypts_with_the_default_key" {
  command = plan

  variables {
    kms_key_arn = null
  }

  expect_failures = [check.volumes_use_aws_managed_key]

  assert {
    condition     = aws_launch_template.this.block_device_mappings[0].ebs[0].encrypted == "true" && aws_launch_template.this.block_device_mappings[0].ebs[0].kms_key_id == null
    error_message = "Without a key the volume must still be encrypted (AWS managed key), never unencrypted."
  }
}

run "volume_settings_pass_through" {
  command = plan

  variables {
    root_volume = { device_name = "/dev/sda1", size_gib = 64, type = "io2", iops = 6000 }
    ebs_volumes = {
      scratch = { device_name = "/dev/sdh", size_gib = 500, type = "gp3", iops = 5000, throughput = 500, delete_on_termination = false }
      restore = { device_name = "/dev/sdi", size_gib = 200, snapshot_id = "snap-0a1b2c3d4e5f60001" }
    }
  }

  assert {
    condition = (
      aws_launch_template.this.block_device_mappings[0].device_name == "/dev/sda1" &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].volume_type == "io2" &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].iops == 6000 &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].volume_size == 64
    )
    error_message = "Root volume device name, type, size, and iops must pass through."
  }

  assert {
    condition = anytrue([
      for m in aws_launch_template.this.block_device_mappings :
      m.device_name == "/dev/sdh" && m.ebs[0].delete_on_termination == "false" && m.ebs[0].throughput == 500
    ])
    error_message = "delete_on_termination = false and throughput must pass through for an additional volume."
  }

  assert {
    condition = anytrue([
      for m in aws_launch_template.this.block_device_mappings :
      m.device_name == "/dev/sdi" && m.ebs[0].snapshot_id == "snap-0a1b2c3d4e5f60001" && m.ebs[0].encrypted == "true"
    ])
    error_message = "A volume restored from a snapshot must stay encrypted."
  }
}

run "multi_region_key_arn_is_accepted" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-2:123456789012:key/mrk-1234567890abcdef1234567890abcdef"
  }

  assert {
    condition     = aws_launch_template.this.block_device_mappings[0].ebs[0].kms_key_id == "arn:aws:kms:us-east-2:123456789012:key/mrk-1234567890abcdef1234567890abcdef"
    error_message = "A multi-Region key ARN (mrk-...) must be accepted and passed through."
  }
}
