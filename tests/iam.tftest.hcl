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

run "creates_role_with_ssm_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_role.this) == 1 && aws_iam_role.this[0].name == "orders-worker-instance" && aws_iam_role.this[0].path == "/"
    error_message = "The module must create <name>-instance by default."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this[0].assume_role_policy).Statement[0].Principal.Service == "ec2.amazonaws.com" && jsondecode(aws_iam_role.this[0].assume_role_policy).Statement[0].Action == "sts:AssumeRole"
    error_message = "Only the EC2 service may assume the instance role."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm) == 1 && aws_iam_role_policy_attachment.ssm[0].policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "AmazonSSMManagedInstanceCore must be attached by default."
  }

  assert {
    condition     = length(aws_iam_instance_profile.this) == 1 && aws_iam_instance_profile.this[0].name == "orders-worker-instance"
    error_message = "An instance profile named <name>-instance must be created."
  }

  assert {
    condition     = aws_launch_template.this.iam_instance_profile[0].name == "orders-worker-instance"
    error_message = "The launch template must use the created instance profile."
  }
}

run "partition_is_honoured_in_the_policy_arn_and_the_trust_principal" {
  command = plan

  variables {
    partition = "aws-cn"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.ssm[0].policy_arn == "arn:aws-cn:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "The managed policy ARN must use the supplied partition."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this[0].assume_role_policy).Statement[0].Principal.Service == "ec2.amazonaws.com.cn"
    error_message = "The China partition's EC2 service principal is ec2.amazonaws.com.cn, so the role must trust that, not ec2.amazonaws.com."
  }
}

run "additional_policies_boundary_and_inline" {
  command = plan

  variables {
    iam_policy_arns = {
      cloudwatch = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      orders     = "arn:aws:iam::123456789012:policy/orders-read"
    }
    iam_permissions_boundary_arn = "arn:aws:iam::123456789012:policy/platform-boundary"
    iam_role_path                = "/platform/"
    iam_inline_policies = {
      config = jsonencode({
        Version   = "2012-10-17"
        Statement = [{ Effect = "Allow", Action = ["s3:GetObject"], Resource = ["arn:aws:s3:::orders-config/*"] }]
      })
    }
  }

  assert {
    condition     = toset(keys(aws_iam_role_policy_attachment.additional)) == toset(["cloudwatch", "orders"])
    error_message = "Every additional managed policy must be attached under its label."
  }

  assert {
    condition     = aws_iam_role.this[0].permissions_boundary == "arn:aws:iam::123456789012:policy/platform-boundary" && aws_iam_role.this[0].path == "/platform/" && aws_iam_instance_profile.this[0].path == "/platform/"
    error_message = "The boundary and path must apply to the role, and the path to the instance profile."
  }

  assert {
    condition     = length(aws_iam_role_policy.inline) == 1 && aws_iam_role_policy.inline["config"].name == "config" && jsondecode(aws_iam_role_policy.inline["config"].policy).Statement[0].Action[0] == "s3:GetObject"
    error_message = "Each inline policy must be attached unchanged under its key as the policy name."
  }
}

run "ssm_policy_can_be_replaced" {
  command = plan

  variables {
    iam_attach_ssm_managed_policy = false
    iam_policy_arns               = { custom_ssm = "arn:aws:iam::123456789012:policy/custom-ssm" }
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm) == 0 && length(aws_iam_role_policy_attachment.additional) == 1
    error_message = "Turning the SSM managed policy off must leave only the caller's policies."
  }
}

run "existing_profile_creates_no_iam" {
  command = plan

  variables {
    create_instance_profile   = false
    iam_instance_profile_name = "platform-ssm-instance"
  }

  assert {
    condition = (
      length(aws_iam_role.this) == 0 &&
      length(aws_iam_instance_profile.this) == 0 &&
      length(aws_iam_role_policy_attachment.ssm) == 0 &&
      length(aws_iam_role_policy_attachment.additional) == 0 &&
      length(aws_iam_role_policy.inline) == 0
    )
    error_message = "No IAM resource may be created when a profile is supplied."
  }

  assert {
    condition     = aws_launch_template.this.iam_instance_profile[0].name == "platform-ssm-instance" && output.instance_profile_name == "platform-ssm-instance"
    error_message = "The supplied profile must reach the launch template and the output."
  }

  assert {
    condition     = output.iam_role_arn == null && output.iam_role_name == null && output.instance_profile_arn == null
    error_message = "The role and profile outputs must be null for a supplied profile."
  }
}

run "existing_profile_requires_a_name" {
  command = plan

  variables {
    create_instance_profile = false
  }

  expect_failures = [aws_launch_template.this]
}

run "profile_name_without_opting_out_is_rejected" {
  command = plan

  variables {
    iam_instance_profile_name = "platform-ssm-instance"
  }

  expect_failures = [aws_launch_template.this]
}

run "role_inputs_with_existing_profile_are_rejected" {
  command = plan

  variables {
    create_instance_profile   = false
    iam_instance_profile_name = "platform-ssm-instance"
    iam_policy_arns           = { cloudwatch = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" }
  }

  expect_failures = [aws_launch_template.this]
}
