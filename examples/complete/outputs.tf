output "autoscaling_group_name" {
  description = "Name of the Auto Scaling group."
  value       = module.fleet.autoscaling_group_name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling group."
  value       = module.fleet.autoscaling_group_arn
}

output "launch_template_id" {
  description = "ID of the launch template."
  value       = module.fleet.launch_template_id
}

output "launch_template_latest_version" {
  description = "Launch template version the group runs."
  value       = module.fleet.launch_template_latest_version
}

output "image_id" {
  description = "Pinned AMI ID in the launch template."
  value       = module.fleet.image_id
}

output "instance_profile_name" {
  description = "Name of the instance profile attached to the instances (created or supplied)."
  value       = module.fleet.instance_profile_name
}

output "iam_role_arn" {
  description = "ARN of the created role. Null when an existing instance profile is supplied."
  value       = module.fleet.iam_role_arn
}

output "access" {
  description = "How operators reach the instances: ssm, key_pair, or both."
  value       = module.fleet.access
}

output "scaling_policy_arn" {
  description = "ARN of the CPU target tracking policy."
  value       = module.fleet.scaling_policy_arn
}
