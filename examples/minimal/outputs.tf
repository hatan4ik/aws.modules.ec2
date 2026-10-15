output "autoscaling_group_name" {
  description = "Name of the Auto Scaling group."
  value       = module.instance.autoscaling_group_name
}

output "launch_template_id" {
  description = "ID of the launch template."
  value       = module.instance.launch_template_id
}

output "image_id" {
  description = "Image reference in the launch template (resolve:ssm:<parameter>)."
  value       = module.instance.image_id
}

output "access" {
  description = "How operators reach the instance: ssm, key_pair, or both."
  value       = module.instance.access
}

output "iam_role_arn" {
  description = "ARN of the instance role the module created."
  value       = module.instance.iam_role_arn
}
