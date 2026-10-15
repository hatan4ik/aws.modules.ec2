variable "region" {
  description = "AWS region the fleet is created in."
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "AMI ID to run, built for arm64 (the example uses an m7g instance type)."
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id must be an AMI ID (ami-...)."
  }
}

variable "subnet_ids" {
  description = "Existing private subnet IDs in at least two Availability Zones."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", id))])
    error_message = "subnet_ids must contain at least two subnet IDs (subnet-...)."
  }
}

variable "security_group_ids" {
  description = "Existing security group IDs attached to every instance. They must allow the load balancer to reach the workload port."
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) >= 1 && alltrue([for id in var.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", id))])
    error_message = "security_group_ids must contain at least one security group ID (sg-...)."
  }
}

variable "kms_key_arn" {
  description = "Full ARN of the customer managed KMS key that encrypts the volumes (a single-Region or multi-Region mrk- key). The module needs the full ARN so it can be validated at plan time. Its key policy must allow the Auto Scaling service-linked role."
  type        = string

  validation {
    condition     = can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a full KMS key ARN, not an alias."
  }
}

variable "target_group_arn" {
  description = "ARN of an existing load balancer target group (port 80) the instances register with."
  type        = string

  validation {
    condition     = can(regex("^arn:[a-z-]+:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:targetgroup/[A-Za-z0-9-]+/[0-9a-f]+$", var.target_group_arn))
    error_message = "target_group_arn must be a target group ARN."
  }
}

variable "existing_instance_profile_name" {
  description = "Name of an existing instance profile to attach. Null makes the module create a role and profile with the extra policies below. An existing profile must grant SSM access itself, because the module attaches nothing to a profile it did not create."
  type        = string
  default     = null
}

variable "artifact_bucket_arn" {
  description = "ARN of the S3 bucket whose releases/ prefix the created role may read. Used only when the module creates the role."
  type        = string
  default     = "arn:aws:s3:::example-release-artifacts"
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for the created role. Null sets none. Used only when the module creates the role."
  type        = string
  default     = null
}
