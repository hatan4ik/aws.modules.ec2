# One launch template and one Auto Scaling group. A single instance is a group
# with min_size = max_size = 1; there is no separate single-instance mode, so
# an instance that fails is always replaced.

# The partition is needed only to build the SSM managed policy ARN. The data
# source reads the provider's configuration and makes no API call. It is read
# whenever the caller does not supply the partition, even when an instance
# profile is brought: locals are always evaluated, and indexing an empty data
# source would fail the plan.
data "aws_partition" "current" {
  count = var.partition == null ? 1 : 0
}

# Registered from a public key only. Terraform never sees the private half.
# The launch template is create_before_destroy and Terraform extends that to
# what it depends on, so a fixed key pair name would make a key rotation try
# to create the replacement under a name that still exists. A name prefix lets
# the replacement coexist with the old key pair for one apply.
resource "aws_key_pair" "this" {
  count = local.create_key_pair ? 1 : 0

  region          = var.region
  key_name_prefix = "${var.name}-"
  public_key      = var.key_pair_public_key
  tags            = local.tags
}

resource "aws_launch_template" "this" {
  region      = var.region
  name_prefix = "${var.name}-"
  description = "Launch template for the ${var.name} fleet"

  image_id      = local.image_id
  instance_type = var.instance_type
  user_data     = var.user_data == null ? null : base64encode(var.user_data)

  # No key pair unless access asks for one. The name is either an existing key
  # pair or the one this module registers from a public key.
  key_name = local.key_name

  # A new template version is the unit of change; the Auto Scaling group
  # follows latest_version, so an edit rolls the fleet (see instance_refresh).
  update_default_version = true

  iam_instance_profile {
    name = local.instance_profile_name
  }

  # IMDSv2 only. http_tokens is not an input: a v1-capable instance can hand
  # its role credentials to anything that can make a plain GET (SSRF).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = var.metadata_hop_limit
    instance_metadata_tags      = "disabled"
  }

  monitoring {
    enabled = var.detailed_monitoring
  }

  # Declared explicitly so a subnet with map_public_ip_on_launch = true can
  # never give these instances a public address.
  network_interfaces {
    device_index                = 0
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = var.security_group_ids
  }

  block_device_mappings {
    device_name = var.root_volume.device_name

    ebs {
      volume_size           = var.root_volume.size_gib
      volume_type           = var.root_volume.type
      iops                  = var.root_volume.iops
      throughput            = var.root_volume.throughput
      encrypted             = true
      kms_key_id            = local.root_kms_key_arn
      delete_on_termination = true
    }
  }

  dynamic "block_device_mappings" {
    for_each = var.ebs_volumes

    content {
      device_name = block_device_mappings.value.device_name

      ebs {
        volume_size           = block_device_mappings.value.size_gib
        volume_type           = block_device_mappings.value.type
        iops                  = block_device_mappings.value.iops
        throughput            = block_device_mappings.value.throughput
        snapshot_id           = block_device_mappings.value.snapshot_id
        encrypted             = true
        kms_key_id            = local.volume_kms_key_arns[block_device_mappings.key]
        delete_on_termination = block_device_mappings.value.delete_on_termination
      }
    }
  }

  dynamic "tag_specifications" {
    for_each = toset(["instance", "volume", "network-interface"])

    content {
      resource_type = tag_specifications.value
      tags          = local.tags
    }
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = (var.ami_id != null) != (var.ami_ssm_parameter_name != null)
      error_message = "Set exactly one of ami_id and ami_ssm_parameter_name."
    }

    precondition {
      condition     = var.create_instance_profile ? var.iam_instance_profile_name == null : var.iam_instance_profile_name != null
      error_message = "Set iam_instance_profile_name exactly when create_instance_profile is false: it names the existing profile to attach, and the module creates none."
    }

    precondition {
      condition     = local.create_instance_profile || !local.iam_create_inputs_set
      error_message = "iam_attach_ssm_managed_policy, iam_policy_arns, iam_inline_policies, iam_permissions_boundary_arn, and iam_role_path configure the role the module creates; they have no effect when create_instance_profile is false. Remove them or let the module create the profile."
    }

    precondition {
      condition     = local.uses_key_pair || (var.key_pair_name == null && var.key_pair_public_key == null)
      error_message = "key_pair_name and key_pair_public_key are only used when access is key_pair or both. Remove them or change access."
    }

    precondition {
      condition     = !local.uses_key_pair || ((var.key_pair_name != null) != (var.key_pair_public_key != null))
      error_message = "access = ${var.access} needs a key pair: set exactly one of key_pair_name (an existing key pair) and key_pair_public_key (a public key for the module to register)."
    }
  }
}

resource "aws_autoscaling_group" "this" {
  region = var.region
  name   = var.name

  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.subnet_ids

  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period
  target_group_arns         = tolist(var.target_group_arns)
  termination_policies      = var.termination_policies
  protect_from_scale_in     = var.protect_from_scale_in
  wait_for_capacity_timeout = var.wait_for_capacity_timeout

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  # The role's policies are attached before the first instance can boot, so
  # an instance never starts without the permissions Session Manager needs,
  # and on destroy they are detached only after the group is gone.
  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    aws_iam_role_policy_attachment.additional,
    aws_iam_role_policy.inline,
  ]

  dynamic "instance_refresh" {
    for_each = var.instance_refresh.enabled ? [var.instance_refresh] : []

    content {
      strategy = "Rolling"

      preferences {
        min_healthy_percentage = instance_refresh.value.min_healthy_percentage
        max_healthy_percentage = instance_refresh.value.max_healthy_percentage
        instance_warmup        = instance_refresh.value.instance_warmup == null ? null : tostring(instance_refresh.value.instance_warmup)

        # By default a refresh skips scale-in-protected instances, which
        # would leave a protected fleet on the old launch template forever.
        scale_in_protected_instances = var.protect_from_scale_in ? "Refresh" : null
      }
    }
  }

  # Tags on the group itself. Instances, volumes, and network interfaces are
  # tagged by the launch template's tag_specifications, which is the only
  # place that reaches volumes created from block_device_mappings.
  dynamic "tag" {
    for_each = local.tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }

  lifecycle {
    precondition {
      condition     = var.min_size <= var.max_size
      error_message = "min_size must not exceed max_size."
    }

    precondition {
      condition     = var.desired_capacity == null ? true : (var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size)
      error_message = "desired_capacity must be between min_size and max_size."
    }
  }
}

resource "aws_autoscaling_policy" "cpu" {
  count = var.target_tracking_cpu_percent == null ? 0 : 1

  region                 = var.region
  name                   = "${var.name}-cpu"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    target_value = var.target_tracking_cpu_percent

    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
  }
}
