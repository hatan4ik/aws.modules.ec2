output "autoscaling_group_name" {
  description = "Name of the Auto Scaling group."
  value       = module.instance.autoscaling_group_name
}

output "access" {
  description = "How operators reach the instances: ssm, key_pair, or both."
  value       = module.instance.access
}

output "key_pair_name" {
  description = "Name of the key pair the instances launch with: the one the module registered from the public key."
  value       = module.instance.key_pair_name
}

output "instance_profile_name" {
  description = "Name of the instance profile the module created."
  value       = module.instance.instance_profile_name
}

output "iam_role_arn" {
  description = "ARN of the instance role the module created."
  value       = module.instance.iam_role_arn
}
