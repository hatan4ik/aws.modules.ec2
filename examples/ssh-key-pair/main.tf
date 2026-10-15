provider "aws" {
  region = var.region
}

# SSH needs an inbound rule on port 22, and the module creates no security
# group. This is how to add one with aws.modules.security-group, from a bastion
# or VPN range and never 0.0.0.0/0. It is commented out because the example
# takes existing groups through var.security_group_ids; uncomment it, declare
# the two variables, and append the group to security_group_ids below.
#
# The shape follows how aws.modules.ecs-service calls aws.modules.security-group
# (v1.1.0). That repository is not checked out here, so this composition has not
# been validated.
#
# variable "vpc_id" {
#   description = "ID of the VPC the subnets belong to."
#   type        = string
# }
#
# variable "ssh_allowed_cidr" {
#   description = "IPv4 CIDR the SSH rule admits: the bastion host or VPN range. Never 0.0.0.0/0."
#   type        = string
# }
#
# module "ssh_access" {
#   source = "git::https://github.com/hatan4ik/aws.modules.security-group.git?ref=<commit-sha>" # v1.1.0 or later
#
#   name        = "ssh-key-pair-example-ssh"
#   description = "SSH to the ssh-key-pair example fleet from the bastion or VPN range"
#   vpc_id      = var.vpc_id
#
#   ingress_rules = {
#     ssh = {
#       description = "SSH from the bastion or VPN range"
#       from_port   = 22
#       to_port     = 22
#       ip_protocol = "tcp"
#       cidr_ipv4   = var.ssh_allowed_cidr
#     }
#   }
# }
#
# Then, in the module call below:
#   security_group_ids = concat(var.security_group_ids, [module.ssh_access.id])

module "instance" {
  source = "../../"

  name                   = "ssh-key-pair-example"
  ami_ssm_parameter_name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
  instance_type          = "t4g.small"

  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids

  kms_key_arn = var.kms_key_arn

  # both: Session Manager stays available (the platform standard, and the path
  # that can be logged and attributed per IAM principal) and the instances also
  # launch with the key pair. The alternatives:
  #   access = "ssm"       the default; no key pair at all
  #   access = "key_pair"  SSH only; AmazonSSMManagedInstanceCore is NOT
  #                        attached unless iam_attach_ssm_managed_policy = true
  access = "both"

  # The PUBLIC half only. The module registers it as the EC2 key pair named
  # after the fleet ("ssh-key-pair-example"). It never generates key material,
  # so no private key reaches Terraform state. To use a key pair that already
  # exists in the Region, set key_pair_name instead; set exactly one of the two.
  key_pair_public_key = var.ssh_public_key

  # One instance: min 100 / max 200 is the documented way to launch the
  # replacement before terminating the old instance, avoiding the outage window
  # a one-instance group otherwise has during a refresh.
  instance_refresh = {
    min_healthy_percentage = 100
    max_healthy_percentage = 200
    instance_warmup        = 120
  }
}
