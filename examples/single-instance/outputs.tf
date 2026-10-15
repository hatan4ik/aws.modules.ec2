output "autoscaling_group_name" {
  description = "Name of the Auto Scaling group that holds the one instance."
  value       = module.instance.autoscaling_group_name
}

output "launch_template_latest_version" {
  description = "Launch template version the group runs; it increments on every launch template change, which starts the refresh."
  value       = module.instance.launch_template_latest_version
}

output "image_id" {
  description = "Pinned AMI ID in the launch template."
  value       = module.instance.image_id
}

output "access" {
  description = "How operators reach the instance: ssm, key_pair, or both."
  value       = module.instance.access
}

output "instance_profile_name" {
  description = "Name of the instance profile the module created."
  value       = module.instance.instance_profile_name
}
