# Advisory checks: they warn on every plan and apply but never block. Each
# describes a configuration that is valid yet usually unintended.

check "volumes_use_aws_managed_key" {
  assert {
    condition     = local.root_kms_key_arn != null && alltrue([for arn in values(local.volume_kms_key_arns) : arn != null])
    error_message = "At least one volume is encrypted with the AWS managed aws/ebs key because no kms_key_arn is set. That key cannot be shared across accounts, has no key policy you control, and cannot be revoked. Pass a customer managed key from aws.modules.kms."
  }
}

check "single_subnet" {
  assert {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids has a single subnet, so the group runs in one Availability Zone and an AZ outage takes the whole fleet down. Pass subnets from at least two zones."
  }
}

check "elb_health_check_without_target_groups" {
  assert {
    condition     = var.health_check_type != "ELB" || length(var.target_group_arns) > 0
    error_message = "health_check_type is ELB but no target_group_arns are registered, so the group has no load balancer health signal and behaves like EC2 health checks."
  }
}

check "no_way_into_the_instances" {
  assert {
    condition     = !local.create_instance_profile || local.uses_key_pair || local.attach_ssm_policy || length(var.iam_policy_arns) > 0 || length(var.iam_inline_policies) > 0
    error_message = "The created role has no SSM permissions, no other policy, and no key pair is selected, so nothing can open a shell on these instances. Attach AmazonSSMManagedInstanceCore, grant equivalent permissions, or set access to key_pair or both."
  }
}

check "target_tracking_cannot_scale" {
  assert {
    condition     = var.target_tracking_cpu_percent == null || var.max_size > var.min_size
    error_message = "target_tracking_cpu_percent is set but max_size equals min_size, so the scaling policy can never add or remove an instance."
  }
}

check "single_instance_refresh_has_downtime" {
  assert {
    condition     = !var.instance_refresh.enabled || var.max_size > 1 || (var.instance_refresh.min_healthy_percentage == 100 && coalesce(var.instance_refresh.max_healthy_percentage, 0) >= 200)
    error_message = "A one-instance group with this instance_refresh has an outage window while the replacement boots, because the group can terminate the instance before the replacement is in service. min_healthy_percentage = 100 with max_healthy_percentage = 200 is the documented way to launch the replacement first."
  }
}

check "broad_instance_role" {
  assert {
    condition = (
      length([for arn in values(var.iam_policy_arns) : arn if can(regex("/(AdministratorAccess|PowerUserAccess|IAMFullAccess)$", arn))]) == 0 &&
      alltrue([for doc in values(var.iam_inline_policies) : !can(regex("\"Action\"\\s*:\\s*(\\[\\s*)?\"\\*\"", doc))])
    )
    error_message = "The instance role carries an administrator-class managed policy or an inline statement with Action \"*\". Anything that can read the instance metadata service, including every container when metadata_hop_limit is 2, can use these permissions. Grant only what the workload calls."
  }
}
