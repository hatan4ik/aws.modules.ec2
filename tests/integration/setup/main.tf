# Disposable prerequisites for the integration suites: a VPC with two private
# subnets and no route to the internet, interface endpoints for Systems Manager
# so Session Manager works without a NAT gateway, a security group with no
# inbound rules, and an EC2 key pair registered from a throwaway PUBLIC key.
# Everything is created and destroyed by `terraform test` in the caller's own
# account; nothing here is shared or long-lived. The module under test creates
# the instance role, the launch template, and the Auto Scaling group.
#
# The volume key is NOT created here. The CI role holds neither kms:CreateKey
# nor kms:TagResource (that pair would let it tag, and then manage, any key in
# the account), so a key is created once by an administrator, tagged, and
# passed in as volume_key_arn. See README.md.

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

# Auto Scaling launches instances through AWSServiceRoleForAutoScaling, and the
# volume key's policy names it, so the role must exist before the suite runs. AWS
# creates it when the first Auto Scaling group is created by a principal that
# may create service-linked roles; the integration role may not
# (iam:CreateServiceLinkedRole is deliberately not granted), so an account that
# has never had a group needs it created once by an administrator. The role is
# not created here: it is account-wide, shared by every Auto Scaling group, and
# a disposable run must not own or delete it. The lookup is iam:GetRole on that
# one ARN, which the policy can scope; iam:ListRoles cannot be scoped.
data "aws_iam_role" "autoscaling_service_linked_role" {
  name = "AWSServiceRoleForAutoScaling"

  lifecycle {
    postcondition {
      condition     = self.path == "/aws-service-role/autoscaling.amazonaws.com/"
      error_message = "A role named AWSServiceRoleForAutoScaling exists but is not the Auto Scaling service-linked role (path ${self.path})."
    }
  }
}

# The pre-created, tagged, disposable key. The read is kms:DescribeKey, which
# the integration role holds only for keys tagged IntegrationTest, so an
# untagged or foreign key fails here with AccessDenied before anything is
# created. The key policy itself cannot be read back; see README.md for what it
# must say.
data "aws_kms_key" "volumes" {
  key_id = var.volume_key_arn

  lifecycle {
    postcondition {
      condition     = self.key_manager == "CUSTOMER" && self.key_state == "Enabled" && self.key_usage == "ENCRYPT_DECRYPT"
      error_message = "volume_key_arn must name an enabled, customer managed, ENCRYPT_DECRYPT KMS key (found manager ${self.key_manager}, state ${self.key_state}, usage ${self.key_usage})."
    }
  }
}

resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name = "${var.name_prefix}-${random_id.suffix.hex}"
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)

  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  # The three interface endpoints Session Manager needs from a subnet with no
  # internet route.
  ssm_endpoint_services = toset(["ssm", "ssmmessages", "ec2messages"])

  tags = merge(var.tags, {
    IntegrationTest = "aws.modules.ec2"
    Disposable      = "true"
  })
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = local.name })
}

# No internet gateway, no NAT gateway, no route other than the VPC's local one:
# the instances can reach only the endpoints below.
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.cidr_block, 8, count.index)
  availability_zone = local.azs[count.index]

  tags = merge(local.tags, { Name = "${local.name}-private-${count.index}", Tier = "private" })
}

# Instances: no inbound rules at all, and egress only to the endpoint security
# group on 443.
resource "aws_security_group" "instances" {
  name        = "${local.name}-instances"
  description = "Disposable integration test instances: no inbound, egress 443 to the SSM endpoints only"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-instances" })
}

resource "aws_security_group" "endpoints" {
  name        = "${local.name}-endpoints"
  description = "Disposable integration test SSM interface endpoints: 443 from the instances only"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name}-endpoints" })
}

resource "aws_vpc_security_group_egress_rule" "instances_to_endpoints" {
  security_group_id            = aws_security_group.instances.id
  description                  = "HTTPS to the Systems Manager interface endpoints"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.endpoints.id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_instances" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "HTTPS from the instances"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.instances.id

  tags = local.tags
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = local.ssm_endpoint_services

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${local.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "${local.name}-${each.key}" })
}

# ---------------------------------------------------------------------------
# Key pair
# ---------------------------------------------------------------------------

# Registered from a public key literal only. The private half was discarded when
# the throwaway pair was generated and exists nowhere, so no one can open an
# SSH session with this key pair; it exists to prove that the module attaches
# an existing key pair (access = both) and nothing more. The instance security
# group has no inbound rules, which is the other half of the claim that a key
# pair alone opens nothing.
resource "aws_key_pair" "ssh" {
  key_name   = "${local.name}-ssh"
  public_key = var.ssh_public_key

  tags = merge(local.tags, { Name = "${local.name}-ssh" })
}
