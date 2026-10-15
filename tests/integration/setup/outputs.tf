output "name" {
  description = "Unique fixture name, also used as the fleet name under test."
  value       = local.name
}

output "vpc_id" {
  description = "ID of the disposable VPC."
  value       = aws_vpc.this.id
}

output "subnet_ids" {
  description = "The two private subnet IDs, in different Availability Zones."
  value       = aws_subnet.private[*].id
}

output "security_group_id" {
  description = "ID of the instance security group: no inbound rules, egress 443 to the SSM endpoints only."
  value       = aws_security_group.instances.id
}

output "kms_key_arn" {
  description = "ARN of the pre-created customer managed key (volume_key_arn), read back from KMS."
  value       = data.aws_kms_key.volumes.arn
}

output "autoscaling_service_linked_role_arn" {
  description = "ARN of AWSServiceRoleForAutoScaling, which the fixture requires to exist and does not create."
  value       = data.aws_iam_role.autoscaling_service_linked_role.arn
}

output "key_pair_name" {
  description = "Name of the EC2 key pair the fixture registered from the throwaway public key."
  value       = aws_key_pair.ssh.key_name
}

output "iam_role_path" {
  description = "IAM path for the fleet's role and instance profile; the permissions policy scopes IAM on it."
  value       = var.iam_role_path
}

output "ssm_endpoint_ids" {
  description = "IDs of the Systems Manager interface endpoints, keyed by service."
  value       = { for service, endpoint in aws_vpc_endpoint.ssm : service => endpoint.id }
}

output "account_id" {
  description = "Account the caller's credentials belong to."
  value       = local.account_id
}

output "partition" {
  description = "Partition the caller's credentials belong to."
  value       = local.partition
}

output "region" {
  description = "Region the fixtures were created in, resolved from the caller's credentials."
  value       = local.region
}

output "tags" {
  description = "Identifying tags shared with the fleet under test."
  value       = local.tags
}
