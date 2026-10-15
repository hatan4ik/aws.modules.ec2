variable "region" {
  description = "AWS region the fleet is created in."
  type        = string
  default     = "us-east-1"
}

variable "subnet_ids" {
  description = "Existing private subnet IDs. One is enough for a single instance; two let the group replace the instance in another Availability Zone if one fails."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", id))])
    error_message = "subnet_ids must contain at least one subnet ID (subnet-...)."
  }
}

variable "security_group_ids" {
  description = "Existing security group IDs attached to the instance."
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) >= 1 && alltrue([for id in var.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", id))])
    error_message = "security_group_ids must contain at least one security group ID (sg-...)."
  }
}

variable "ami_id" {
  description = "AMI ID to run. Pinning an AMI makes a change to it a reviewed launch template change that triggers the instance refresh."
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id must be an AMI ID (ami-...)."
  }
}
