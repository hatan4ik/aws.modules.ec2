# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

variable "name" {
  description = "Fleet name. Also the Auto Scaling group name, the launch template name prefix, the Name tag, and the prefix of the IAM role and instance profile. Lowercase alphanumerics and hyphens, 1-48 characters, so every derived name fits its AWS limit."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,46}[a-z0-9])?$", var.name))
    error_message = "name must be 1-48 lowercase alphanumeric characters or hyphens, starting and ending with an alphanumeric character."
  }
}

variable "tags" {
  description = "Tags applied to every resource the module creates and, through the launch template, to the instances, their volumes, and their network interfaces. The module adds a Name tag and never overrides caller tags."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "region" {
  description = "Region where the launch template, Auto Scaling group, and scaling policy are managed. Null preserves the provider's configured Region. IAM is global and ignores it."
  type        = string
  default     = null

  validation {
    condition     = var.region == null ? true : can(regex("^[a-z]{2}-(gov-|iso-|isob-)?[a-z]+-[0-9]$", var.region))
    error_message = "region, when set, must be an AWS Region code such as us-east-2."
  }
}

variable "partition" {
  description = "AWS partition (aws, aws-us-gov, aws-cn) used to build the SSM managed policy ARN and to pick the EC2 service principal in the role's trust policy. Null reads it from aws_partition, which makes no API call. The isolated partitions are not supported."
  type        = string
  default     = null

  validation {
    condition     = var.partition == null ? true : contains(["aws", "aws-us-gov", "aws-cn"], var.partition)
    error_message = "partition, when set, must be aws, aws-us-gov, or aws-cn."
  }
}

# ---------------------------------------------------------------------------
# Placement and network
# ---------------------------------------------------------------------------

variable "subnet_ids" {
  description = "Private subnet IDs the Auto Scaling group launches into. Use at least two, in different Availability Zones, for any fleet that must survive the loss of one. Instances never receive a public IPv4 address, whatever the subnet's map_public_ip_on_launch says. IPv6 follows the subnet: a subnet that auto-assigns IPv6 addresses gives the instances a globally routable IPv6 address, so reachability then depends only on the security group."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.subnet_ids) >= 1 && length(var.subnet_ids) <= 20 && alltrue([for id in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", id))])
    error_message = "subnet_ids must contain 1-20 subnet IDs (subnet-...)."
  }
}

variable "security_group_ids" {
  description = "Security group IDs attached to every instance's primary network interface. The module does not create security groups: compose aws.modules.security-group and pass its id here. 1-5 groups (the default per-interface quota)."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.security_group_ids) >= 1 && length(var.security_group_ids) <= 5 && alltrue([for id in var.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", id))])
    error_message = "security_group_ids must contain 1-5 security group IDs (sg-...)."
  }
}

# ---------------------------------------------------------------------------
# Image and instance
# ---------------------------------------------------------------------------

variable "ami_id" {
  description = "AMI ID to launch. Exactly one of ami_id and ami_ssm_parameter_name must be set. An AMI ID is immutable, so changing it is a reviewed launch template change and rolls the fleet. The module does not check who owns the AMI: AMI provenance is part of your trust boundary (restrict it with an SCP or the EC2 Allowed AMIs setting)."
  type        = string
  default     = null

  validation {
    condition     = var.ami_id == null ? true : can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id must be an AMI ID (ami-...)."
  }
}

variable "ami_ssm_parameter_name" {
  description = "Public or private SSM parameter that holds the AMI ID, resolved by EC2 when an instance launches (for example /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64). The parameter moving does NOT change the launch template, so it does not roll the fleet by itself; use ami_id when the AMI must be pinned. Whoever can write a private parameter controls what every new instance boots. Exactly one of ami_id and ami_ssm_parameter_name must be set."
  type        = string
  default     = null

  validation {
    condition     = var.ami_ssm_parameter_name == null ? true : can(regex("^/[A-Za-z0-9_.\\-/]{1,1000}$", var.ami_ssm_parameter_name))
    error_message = "ami_ssm_parameter_name must be an SSM parameter path starting with / (letters, digits, _, ., -, /)."
  }
}

variable "instance_type" {
  description = "EC2 instance type, for example t3.small or m7g.large. Choose the type and the AMI architecture together."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[0-9][a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must look like an EC2 instance type (family.size), for example m7g.large."
  }
}

variable "user_data" {
  description = "Boot script or cloud-init document, plain text (the module base64-encodes it). At most 16384 characters. Never put secrets in it: the value is stored in Terraform state and plan output, is kept in every older launch template version, is readable by any local process through the instance metadata service, and is readable through the EC2 API. Fetch secrets at boot from Secrets Manager or SSM Parameter Store with the instance role."
  type        = string
  default     = null

  validation {
    condition     = var.user_data == null ? true : length(var.user_data) <= 16384
    error_message = "user_data must be at most 16384 characters."
  }
}

variable "detailed_monitoring" {
  description = "Publish instance metrics at one-minute instead of five-minute granularity. Billed per instance."
  type        = bool
  default     = false
  nullable    = false
}

variable "metadata_hop_limit" {
  description = "IMDSv2 PUT response hop limit. 1 keeps the token on the instance itself; use 2 only when containers that run on the instance must reach the metadata service, and then every container on the instance can obtain the instance role's credentials, so keep that role minimal. IMDSv2 is always required and cannot be relaxed."
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = contains([1, 2], var.metadata_hop_limit)
    error_message = "metadata_hop_limit must be 1 or 2."
  }
}

# ---------------------------------------------------------------------------
# Storage (every volume is encrypted; there is no switch to turn that off)
# ---------------------------------------------------------------------------

variable "kms_key_arn" {
  description = "Customer managed KMS key ARN that encrypts the root and additional volumes unless a volume sets its own. Null encrypts with the AWS managed aws/ebs key and raises an advisory check. The key policy must allow the Auto Scaling service-linked role AWSServiceRoleForAutoScaling to use the key and create grants; see docs/DESIGN.md."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$", var.kms_key_arn))
    error_message = "kms_key_arn must be a full KMS key ARN (arn:<partition>:kms:<region>:<account>:key/<key-id>, including multi-Region mrk- keys). The module requires the full ARN so it can be checked at plan time; aliases and bare key IDs are not accepted."
  }
}

variable "root_volume" {
  description = "Root volume. device_name is the AMI's root device (/dev/xvda for Amazon Linux and Bottlerocket, /dev/sda1 for Ubuntu and Debian); a wrong name adds a second volume instead of resizing the root. size_gib is 8-16384; type is gp3, gp2, io1, or io2; iops is required for io1 and io2 and optional for gp3 (3000-16000); throughput applies to gp3 only (125-1000 MiB/s). kms_key_arn overrides the module-level key for this volume."
  type = object({
    device_name = optional(string, "/dev/xvda")
    size_gib    = optional(number, 30)
    type        = optional(string, "gp3")
    iops        = optional(number)
    throughput  = optional(number)
    kms_key_arn = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = can(regex("^/dev/(xvda|sda1|sda)$", var.root_volume.device_name))
    error_message = "root_volume.device_name must be /dev/xvda, /dev/sda1, or /dev/sda."
  }

  validation {
    condition     = var.root_volume.size_gib >= 8 && var.root_volume.size_gib <= 16384
    error_message = "root_volume.size_gib must be between 8 and 16384."
  }

  validation {
    condition     = contains(["gp3", "gp2", "io1", "io2"], var.root_volume.type)
    error_message = "root_volume.type must be gp3, gp2, io1, or io2."
  }

  # AWS rejects a provisioned-IOPS volume without iops, and the failure shows
  # up as a launch error after the capacity wait, not at plan time.
  validation {
    condition = (
      contains(["io1", "io2"], var.root_volume.type)
      ? (var.root_volume.iops == null ? false : (var.root_volume.iops >= 100 && var.root_volume.iops <= (var.root_volume.type == "io1" ? 64000 : 256000)))
      : (var.root_volume.type == "gp3" ? (var.root_volume.iops == null ? true : (var.root_volume.iops >= 3000 && var.root_volume.iops <= 16000)) : var.root_volume.iops == null)
    )
    error_message = "root_volume.iops is required for io1 (100-64000) and io2 (100-256000), optional for gp3 (3000-16000), and not valid for gp2."
  }

  validation {
    condition     = var.root_volume.throughput == null ? true : (var.root_volume.type == "gp3" && var.root_volume.throughput >= 125 && var.root_volume.throughput <= 1000)
    error_message = "root_volume.throughput is valid only for gp3 and must be between 125 and 1000."
  }

  validation {
    condition     = var.root_volume.kms_key_arn == null ? true : can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$", var.root_volume.kms_key_arn))
    error_message = "root_volume.kms_key_arn must be a full KMS key ARN."
  }
}

variable "ebs_volumes" {
  description = "Additional EBS volumes keyed by a stable name, attached to every instance at launch. device_name is the block device name: /dev/sdf through /dev/sdp, or /dev/xvdb through /dev/xvdd with an optional trailing letter. delete_on_termination defaults to true. snapshot_id restores from a snapshot; the module still requests encrypted = true (and the key), and a restore that AWS refuses fails at launch, not at plan. kms_key_arn overrides the module-level key."
  type = map(object({
    device_name           = string
    size_gib              = number
    type                  = optional(string, "gp3")
    iops                  = optional(number)
    throughput            = optional(number)
    kms_key_arn           = optional(string)
    snapshot_id           = optional(string)
    delete_on_termination = optional(bool, true)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for name in keys(var.ebs_volumes) : can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", name))])
    error_message = "Every ebs_volumes key must be 1-32 lowercase alphanumeric characters or hyphens."
  }

  validation {
    condition     = alltrue([for v in values(var.ebs_volumes) : can(regex("^/dev/(sd[f-p]|xvd[b-d][a-z]?)$", v.device_name))])
    error_message = "Every ebs_volumes device_name must be /dev/sdf through /dev/sdp (or /dev/xvdb-/dev/xvdd...)."
  }

  validation {
    condition     = length(distinct([for v in values(var.ebs_volumes) : v.device_name])) == length(var.ebs_volumes)
    error_message = "Every ebs_volumes device_name must be unique."
  }

  validation {
    condition     = alltrue([for v in values(var.ebs_volumes) : v.size_gib >= 1 && v.size_gib <= 16384 && contains(["gp3", "gp2", "io1", "io2", "st1", "sc1"], v.type)])
    error_message = "Every ebs_volumes size_gib must be 1-16384 and type one of gp3, gp2, io1, io2, st1, sc1."
  }

  validation {
    condition     = alltrue([for v in values(var.ebs_volumes) : contains(["st1", "sc1"], v.type) ? v.size_gib >= 125 : true])
    error_message = "An st1 or sc1 ebs_volumes entry must be at least 125 GiB."
  }

  validation {
    condition = alltrue([for v in values(var.ebs_volumes) : (
      contains(["io1", "io2"], v.type)
      ? (v.iops == null ? false : (v.iops >= 100 && v.iops <= (v.type == "io1" ? 64000 : 256000)))
      : (v.type == "gp3" ? (v.iops == null ? true : (v.iops >= 3000 && v.iops <= 16000)) : v.iops == null)
    )])
    error_message = "ebs_volumes iops is required for io1 (100-64000) and io2 (100-256000), optional for gp3 (3000-16000), and not valid for gp2, st1, and sc1."
  }

  validation {
    condition     = alltrue([for v in values(var.ebs_volumes) : v.throughput == null ? true : (v.type == "gp3" && v.throughput >= 125 && v.throughput <= 1000)])
    error_message = "ebs_volumes throughput is valid only for gp3 and must be between 125 and 1000."
  }

  validation {
    condition     = alltrue([for v in values(var.ebs_volumes) : v.snapshot_id == null ? true : can(regex("^snap-[0-9a-f]{8,17}$", v.snapshot_id))])
    error_message = "Every ebs_volumes snapshot_id must be a snapshot ID (snap-...)."
  }

  validation {
    condition     = alltrue([for v in values(var.ebs_volumes) : v.kms_key_arn == null ? true : can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/(mrk-[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$", v.kms_key_arn))])
    error_message = "Every ebs_volumes kms_key_arn must be a full KMS key ARN."
  }
}

# ---------------------------------------------------------------------------
# Access: how an operator gets a shell on an instance
# ---------------------------------------------------------------------------

variable "access" {
  description = "How operators reach the instances. ssm (default, the platform standard): Session Manager through the instance role; no key pair, no inbound rule needed. key_pair: SSH with an EC2 key pair; the SSM managed policy is not attached unless iam_attach_ssm_managed_policy = true. both: Session Manager and SSH. A key pair alone opens nothing: SSH also needs an inbound rule on port 22 in one of security_group_ids, which this module does not create (use aws.modules.security-group, from a bastion or VPN range, never 0.0.0.0/0)."
  type        = string
  default     = "ssm"
  nullable    = false

  validation {
    condition     = contains(["ssm", "key_pair", "both"], var.access)
    error_message = "access must be ssm, key_pair, or both."
  }
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair, in the instances' Region. Used when access is key_pair or both. Exactly one of key_pair_name and key_pair_public_key must be set then; both must be null when access = ssm."
  type        = string
  default     = null

  validation {
    condition     = var.key_pair_name == null ? true : can(regex("^[A-Za-z0-9 _.:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.key_pair_name))
    error_message = "key_pair_name must be 1-255 characters of letters, digits, spaces and _.:/()#,@[]+=&;{}!$*-."
  }
}

variable "key_pair_public_key" {
  description = "OpenSSH public key (ssh-rsa or ssh-ed25519) the module registers as an EC2 key pair named <name>-<random suffix> (see the key_pair_name output). Rotating the key creates the new key pair first, then the launch template rolls the fleet. Used when access is key_pair or both, instead of key_pair_name. Pass the PUBLIC half only: the module never generates a key, so no private key ever reaches Terraform state. The value must be known at plan time."
  type        = string
  default     = null

  validation {
    condition     = var.key_pair_public_key == null ? true : can(regex("^(ssh-rsa|ssh-ed25519) [A-Za-z0-9+/]{43,}={0,2}( [^\\n]*)?\\n?$", var.key_pair_public_key))
    error_message = "key_pair_public_key must be a single OpenSSH public key line starting with ssh-rsa or ssh-ed25519. A private key is rejected: pass the .pub file."
  }
}

# ---------------------------------------------------------------------------
# Instance profile
# ---------------------------------------------------------------------------

variable "create_instance_profile" {
  description = "Create a role and instance profile named <name>-instance. Set false to attach an existing profile through iam_instance_profile_name. This is its own input, not derived from iam_instance_profile_name being null, so the module still plans when the profile name is computed in the same apply."
  type        = bool
  default     = true
  nullable    = false
}

variable "iam_instance_profile_name" {
  description = "Name of an existing instance profile to attach. Required when create_instance_profile = false and rejected by a precondition when it is true. The existing profile is responsible for granting SSM access when access includes ssm; every other iam_* input is rejected by a precondition when create_instance_profile = false."
  type        = string
  default     = null

  validation {
    condition     = var.iam_instance_profile_name == null ? true : can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", var.iam_instance_profile_name))
    error_message = "iam_instance_profile_name must be 1-128 characters of letters, digits, and +=,.@_-."
  }
}

variable "iam_attach_ssm_managed_policy" {
  description = "Attach AmazonSSMManagedInstanceCore to the created role. Null (default) attaches it when access is ssm or both and not when it is key_pair. Without it (or equivalent permissions) Session Manager cannot reach the instances."
  type        = bool
  default     = null
}

variable "iam_policy_arns" {
  description = "Additional managed policy ARNs to attach to the created role, keyed by a label that is static in your configuration (for example { s3_read = aws_iam_policy.s3_read.arn }). The keys, not the ARNs, decide what exists, so an ARN created in the same apply is fine."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for label in keys(var.iam_policy_arns) : can(regex("^[A-Za-z0-9_-]{1,64}$", label))])
    error_message = "Every iam_policy_arns key must be 1-64 letters, digits, underscores or hyphens."
  }

  validation {
    condition     = alltrue([for arn in values(var.iam_policy_arns) : can(regex("^arn:[a-z-]+:iam::(aws|[0-9]{12}):policy/[A-Za-z0-9+=,.@_/-]+$", arn))])
    error_message = "Every iam_policy_arns value must be an IAM managed policy ARN."
  }
}

variable "iam_inline_policies" {
  description = "Inline policy documents (JSON) for the created role, keyed by policy name. For permissions that exist only for this fleet. The module neither widens nor narrows them: an Allow on Action * and Resource * is accepted (and flagged by an advisory check). The keys decide what exists, so a document built from an ARN created in the same apply is fine."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for name in keys(var.iam_inline_policies) : can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", name))])
    error_message = "Every iam_inline_policies key must be 1-128 characters of letters, digits and +=,.@_-."
  }

  # A document built from a value that is only known after apply is unknown
  # here, and an unknown condition is checked at apply, not rejected at plan.
  validation {
    condition     = alltrue([for doc in values(var.iam_inline_policies) : can(jsondecode(doc))])
    error_message = "Every iam_inline_policies value must be valid JSON."
  }
}

variable "iam_permissions_boundary_arn" {
  description = "Permissions boundary policy ARN for the created role."
  type        = string
  default     = null

  validation {
    condition     = var.iam_permissions_boundary_arn == null ? true : can(regex("^arn:[a-z-]+:iam::[0-9]{12}:policy/[A-Za-z0-9+=,.@_/-]+$", var.iam_permissions_boundary_arn))
    error_message = "iam_permissions_boundary_arn must be an IAM policy ARN."
  }
}

variable "iam_role_path" {
  description = "IAM path of the created role and instance profile. Changing it replaces both under the same names, which IAM rejects while the old ones exist; rename the fleet or destroy and recreate it to change the path."
  type        = string
  default     = "/"
  nullable    = false

  validation {
    condition     = can(regex("^/([A-Za-z0-9+=,.@_-]+/)*$", var.iam_role_path))
    error_message = "iam_role_path must start and end with / (for example / or /platform/)."
  }
}

# ---------------------------------------------------------------------------
# Auto Scaling group
# ---------------------------------------------------------------------------

variable "min_size" {
  description = "Minimum number of instances."
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.min_size >= 0 && var.min_size <= 1000 && floor(var.min_size) == var.min_size
    error_message = "min_size must be a whole number between 0 and 1000."
  }
}

variable "max_size" {
  description = "Maximum number of instances. Must be at least min_size."
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.max_size >= 1 && var.max_size <= 1000 && floor(var.max_size) == var.max_size
    error_message = "max_size must be a whole number between 1 and 1000."
  }
}

variable "desired_capacity" {
  description = "Desired number of instances. Null leaves the count to AWS (the group starts at min_size and a scaling policy keeps it), so a later scaling event does not show up as drift. Set it only for a fleet that is deliberately sized by Terraform."
  type        = number
  default     = null

  validation {
    condition     = var.desired_capacity == null ? true : (var.desired_capacity >= 0 && var.desired_capacity <= 1000 && floor(var.desired_capacity) == var.desired_capacity)
    error_message = "desired_capacity, when set, must be a whole number between 0 and 1000."
  }
}

variable "health_check_type" {
  description = "EC2 replaces instances that fail EC2 status checks; ELB also replaces instances that a load balancer target group reports unhealthy (set target_group_arns)."
  type        = string
  default     = "EC2"
  nullable    = false

  validation {
    condition     = contains(["EC2", "ELB"], var.health_check_type)
    error_message = "health_check_type must be EC2 or ELB."
  }
}

variable "health_check_grace_period" {
  description = "Seconds after launch before health checks start counting. Size it to the boot time of the workload."
  type        = number
  default     = 300
  nullable    = false

  validation {
    condition     = var.health_check_grace_period >= 0 && var.health_check_grace_period <= 7200
    error_message = "health_check_grace_period must be between 0 and 7200 seconds."
  }
}

variable "target_group_arns" {
  description = "Load balancer target group ARNs the group registers instances with, for example from aws.modules.alb."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for arn in var.target_group_arns : can(regex("^arn:[a-z-]+:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:targetgroup/[A-Za-z0-9-]+/[0-9a-f]+$", arn))])
    error_message = "Every target_group_arns entry must be a target group ARN."
  }
}

variable "termination_policies" {
  description = "Order in which the group picks instances to terminate on scale-in."
  type        = list(string)
  default     = ["Default"]
  nullable    = false

  validation {
    condition = alltrue([for p in var.termination_policies : contains([
      "Default", "AllocationStrategy", "ClosestToNextInstanceHour", "NewestInstance", "OldestInstance", "OldestLaunchConfiguration", "OldestLaunchTemplate",
    ], p)])
    error_message = "termination_policies entries must be Default, AllocationStrategy, ClosestToNextInstanceHour, NewestInstance, OldestInstance, OldestLaunchConfiguration, or OldestLaunchTemplate."
  }
}

variable "protect_from_scale_in" {
  description = "Protect new instances from scale-in termination. Auto Scaling health replacement still replaces them, and the module sets the instance refresh to Refresh protected instances too, so a launch template change still rolls the fleet."
  type        = bool
  default     = false
  nullable    = false
}

variable "instance_refresh" {
  description = "Rolling replacement of instances when the launch template changes. min_healthy_percentage is the share of the group that must stay in service during the roll; max_healthy_percentage (100-200) lets the group launch replacements before terminating, which is how a single-instance group avoids downtime (min 100, max 200). enabled=false turns refresh off and leaves old instances running until they are replaced by other means."
  type = object({
    enabled                = optional(bool, true)
    min_healthy_percentage = optional(number, 90)
    max_healthy_percentage = optional(number)
    instance_warmup        = optional(number)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.instance_refresh.min_healthy_percentage >= 0 && var.instance_refresh.min_healthy_percentage <= 100
    error_message = "instance_refresh.min_healthy_percentage must be between 0 and 100."
  }

  validation {
    condition     = var.instance_refresh.max_healthy_percentage == null ? true : (var.instance_refresh.max_healthy_percentage >= 100 && var.instance_refresh.max_healthy_percentage <= 200 && var.instance_refresh.max_healthy_percentage >= var.instance_refresh.min_healthy_percentage && var.instance_refresh.max_healthy_percentage - var.instance_refresh.min_healthy_percentage <= 100)
    error_message = "instance_refresh.max_healthy_percentage must be between 100 and 200, at least min_healthy_percentage, and at most 100 points above it (Auto Scaling rejects a wider band). The default min is 90, so a max above 190 needs a higher min."
  }

  validation {
    condition     = var.instance_refresh.instance_warmup == null ? true : (var.instance_refresh.instance_warmup >= 0 && var.instance_refresh.instance_warmup <= 7200)
    error_message = "instance_refresh.instance_warmup must be between 0 and 7200 seconds."
  }
}

variable "target_tracking_cpu_percent" {
  description = "Average CPU utilization (10-90) a target tracking policy holds the group at. Null creates no scaling policy. Requires max_size greater than min_size to have any effect."
  type        = number
  default     = null

  validation {
    condition     = var.target_tracking_cpu_percent == null ? true : (var.target_tracking_cpu_percent >= 10 && var.target_tracking_cpu_percent <= 90)
    error_message = "target_tracking_cpu_percent, when set, must be between 10 and 90."
  }
}

variable "wait_for_capacity_timeout" {
  description = "How long Terraform waits for min_size instances to pass health checks after create or update (a duration such as 10m). 0 disables waiting."
  type        = string
  default     = "10m"
  nullable    = false

  validation {
    condition     = var.wait_for_capacity_timeout == "0" || can(regex("^[0-9]+(s|m|h)$", var.wait_for_capacity_timeout))
    error_message = "wait_for_capacity_timeout must be 0 or a duration such as 300s, 10m, or 1h."
  }
}
