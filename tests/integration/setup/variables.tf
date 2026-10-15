variable "volume_key_arn" {
  description = "ARN of a pre-created, disposable customer managed KMS key, in the Region the suite runs in, that encrypts the fleet's volumes. Create it once as an administrator, tag it IntegrationTest=aws.modules.ec2 and Disposable=true, and give its policy the Auto Scaling service-linked role (see README.md). The integration role can use and grant on a key carrying that tag and cannot create, tag, re-policy, or delete keys."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$", var.volume_key_arn))
    error_message = "volume_key_arn must be a full KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<key-id>), not an alias or a bare key ID."
  }
}

variable "name_prefix" {
  description = "Prefix for every disposable fixture; a random suffix is appended so concurrent runs never collide. The result is the fleet name under test, the prefix of its IAM role, and the Auto Scaling group name, which the integration permissions policy scopes on (ec2-it-*)."
  type        = string
  default     = "ec2-it"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", var.name_prefix))
    error_message = "name_prefix must be 1-32 lowercase alphanumeric characters or hyphens, so the fleet name and its derived IAM names stay within their limits (the key-pair run appends -kp)."
  }
}

variable "iam_role_path" {
  description = "IAM path the fleet's role and instance profile are created under (the module's iam_role_path). The integration permissions policy scopes every IAM statement to this path and the ec2-it- name prefix, so change both together."
  type        = string
  default     = "/ec2-it/"

  validation {
    condition     = can(regex("^/([A-Za-z0-9+=,.@_-]+/)+$", var.iam_role_path))
    error_message = "iam_role_path must be a path below / that starts and ends with / (for example /ec2-it/)."
  }
}

variable "ssh_public_key" {
  description = "OpenSSH PUBLIC key registered as the fixture's EC2 key pair. The default is a throwaway ed25519 public key whose private half was discarded at generation, so the key pair can be attached to instances but nobody can authenticate with it. Never put a private key here."
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ0j+WM7mygcQY1jJRfkfcPRdenSLaeGbKJPsYlAcThN aws.modules.ec2-integration-throwaway"

  validation {
    condition     = can(regex("^(ssh-rsa|ssh-ed25519) [A-Za-z0-9+/]{43,}={0,2}( [^\\n]*)?$", var.ssh_public_key))
    error_message = "ssh_public_key must be a single OpenSSH public key line (ssh-rsa or ssh-ed25519)."
  }
}

variable "cidr_block" {
  description = "CIDR of the disposable VPC. It is /16 and the two private subnets are /24 slices of it."
  type        = string
  default     = "10.98.0.0/16"
}

variable "tags" {
  description = "Tags applied to every fixture in addition to the identifying defaults."
  type        = map(string)
  default     = {}
}
