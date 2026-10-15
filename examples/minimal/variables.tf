variable "region" {
  description = "AWS region the fleet is created in."
  type        = string
  default     = "us-east-1"
}

variable "subnet_id" {
  description = "Existing private subnet ID the instance launches into."
  type        = string

  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8,17}$", var.subnet_id))
    error_message = "subnet_id must be a subnet ID (subnet-...)."
  }
}

variable "security_group_id" {
  description = "Existing security group ID attached to the instance."
  type        = string

  validation {
    condition     = can(regex("^sg-[0-9a-f]{8,17}$", var.security_group_id))
    error_message = "security_group_id must be a security group ID (sg-...)."
  }
}
