variable "region" {
  description = "AWS region the fleet and the key pair are created in. A key pair belongs to one Region."
  type        = string
  default     = "us-east-1"
}

variable "subnet_ids" {
  description = "Existing private subnet IDs. Use two or more in different Availability Zones; one raises the advisory single_subnet check."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", id))])
    error_message = "subnet_ids must contain at least one subnet ID (subnet-...)."
  }
}

variable "security_group_ids" {
  description = "Existing security group IDs attached to every instance. For SSH, one of them must allow inbound TCP 22 from your bastion or VPN range (never 0.0.0.0/0); the module creates no rule. They must also allow the outbound HTTPS Session Manager needs."
  type        = list(string)

  validation {
    condition     = length(var.security_group_ids) >= 1 && alltrue([for id in var.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", id))])
    error_message = "security_group_ids must contain at least one security group ID (sg-...)."
  }
}

variable "ssh_public_key" {
  description = "OpenSSH PUBLIC key (the contents of the .pub file, one line starting with ssh-ed25519 or ssh-rsa). Never pass or commit the private half."
  type        = string

  validation {
    condition     = can(regex("^(ssh-rsa|ssh-ed25519) [A-Za-z0-9+/]{43,}={0,2}( [^\\n]*)?\\n?$", var.ssh_public_key))
    error_message = "ssh_public_key must be a single OpenSSH public key line starting with ssh-rsa or ssh-ed25519. A private key is rejected: pass the .pub file."
  }
}

variable "kms_key_arn" {
  description = "Full ARN of a customer managed KMS key for the volumes (single-Region or multi-Region mrk-). Null uses the AWS managed aws/ebs key and raises an advisory check. The key policy must allow the Auto Scaling service-linked role; see examples/complete."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a full KMS key ARN, not an alias."
  }
}
