output "autoscaling_group_name" {
  description = "Name of the Auto Scaling group."
  value       = aws_autoscaling_group.this.name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling group."
  value       = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  description = "ID of the launch template."
  value       = aws_launch_template.this.id
}

output "launch_template_arn" {
  description = "ARN of the launch template."
  value       = aws_launch_template.this.arn
}

output "launch_template_latest_version" {
  description = "Latest launch template version the Auto Scaling group runs."
  value       = aws_launch_template.this.latest_version
}

output "image_id" {
  description = "Image the launch template uses: an AMI ID, or resolve:ssm:<parameter> when ami_ssm_parameter_name is set."
  value       = aws_launch_template.this.image_id
}

output "instance_profile_name" {
  description = "Name of the instance profile attached to the instances (created or supplied)."
  value       = local.instance_profile_name
}

output "instance_profile_arn" {
  description = "ARN of the instance profile the module created. Null when iam_instance_profile_name brought an existing profile."
  value       = local.create_instance_profile ? aws_iam_instance_profile.this[0].arn : null
}

output "iam_role_arn" {
  description = "ARN of the role the module created. Null when iam_instance_profile_name brought an existing profile."
  value       = local.create_instance_profile ? aws_iam_role.this[0].arn : null
}

output "iam_role_name" {
  description = "Name of the role the module created, for attaching further policies. Null when iam_instance_profile_name brought an existing profile."
  value       = local.create_instance_profile ? aws_iam_role.this[0].name : null
}

output "scaling_policy_arn" {
  description = "ARN of the CPU target tracking policy. Null when target_tracking_cpu_percent is null."
  value       = var.target_tracking_cpu_percent == null ? null : aws_autoscaling_policy.cpu[0].arn
}

output "access" {
  description = "How operators reach the instances: ssm, key_pair, or both."
  value       = var.access
}

output "key_pair_name" {
  description = "Name of the key pair the instances launch with: the one the module registered from key_pair_public_key, or the existing key_pair_name. Null when access = ssm."
  value       = local.key_name
}
