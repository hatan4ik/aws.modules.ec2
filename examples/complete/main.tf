provider "aws" {
  region = var.region
}

locals {
  # The module rejects the iam_* role inputs when an existing profile is
  # supplied (create_instance_profile = false), so they are set only when the
  # module creates the role.
  create_role = var.existing_instance_profile_name == null
}

module "fleet" {
  source = "../../"

  name = "complete-example"

  # Pinned AMI: changing it is a reviewed launch template change and rolls the
  # fleet. An ami_ssm_parameter_name would be resolved at launch and would not.
  ami_id        = var.ami_id
  instance_type = "m7g.large"

  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids

  # Session Manager is the default and the platform standard. A key pair is
  # opt-in; see examples/ssh-key-pair. Listed here so the choice is visible.
  access = "ssm"

  # Customer managed key for the root and data volumes. Its key policy must
  # allow AWSServiceRoleForAutoScaling; see the README.
  kms_key_arn = var.kms_key_arn

  # device_name must be the AMI's root device. /dev/xvda is right for Amazon
  # Linux 2023; Ubuntu and Debian AMIs use /dev/sda1. A wrong name adds a
  # second volume instead of resizing the root.
  root_volume = {
    device_name = "/dev/xvda"
    size_gib    = 50
    type        = "gp3"
  }

  # An additional encrypted volume, attached unformatted at launch. Formatting
  # and mounting it is the workload's job.
  ebs_volumes = {
    data = {
      device_name = "/dev/sdf"
      size_gib    = 100
      type        = "gp3"
      iops        = 4000
      throughput  = 250
    }
  }

  # Installs and starts a placeholder web server so the target group has
  # something to health check. Needs a route to the package repositories (a NAT
  # gateway or VPC endpoints). Never put secrets in user data: it is stored in
  # state and plan output, kept in old launch template versions, and readable
  # from the metadata service.
  user_data = <<-EOT
    #!/bin/bash
    set -euo pipefail
    dnf -y install nginx
    systemctl enable --now nginx
  EOT

  # Either let the module create the role and profile ...
  create_instance_profile = local.create_role

  # ... or bring an existing profile, which must grant SSM access itself.
  iam_instance_profile_name = var.existing_instance_profile_name

  # When the module creates the role, AmazonSSMManagedInstanceCore follows
  # access (attached for ssm and both). These add the CloudWatch agent and
  # read access to one release prefix. Both maps are keyed by a label that is
  # static in this configuration.
  iam_policy_arns = local.create_role ? {
    cloudwatch_agent = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  } : {}

  iam_inline_policies = local.create_role ? {
    ReadReleaseArtifacts = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "ReadReleaseArtifacts"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${var.artifact_bucket_arn}/releases/*"]
      }]
    })
  } : {}

  iam_permissions_boundary_arn = local.create_role ? var.permissions_boundary_arn : null

  # Two to six instances, held near 60 percent average CPU. desired_capacity
  # stays null so scaling activity is not shown as drift.
  min_size                    = 2
  max_size                    = 6
  target_tracking_cpu_percent = 60

  # Register with the load balancer and replace instances it reports unhealthy.
  target_group_arns         = [var.target_group_arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  # With two instances, 50 percent keeps one in service while the other is
  # replaced, so the fleet rolls one instance at a time.
  instance_refresh = {
    min_healthy_percentage = 50
    instance_warmup        = 120
  }

  # Reach the instances, volumes, and network interfaces through the launch
  # template. Provider default_tags do not.
  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
