provider "aws" {
  region = var.region
}

# A single instance is a group with min_size = max_size = 1; there is no
# separate single-instance mode, so an instance that fails is replaced.
#
# With the default instance_refresh, a launch template change (a new ami_id, a
# new user_data) has an outage window: the group can terminate the one instance
# before its replacement is in service. max_healthy_percentage = 200 lets the
# group run two instances while it rolls, and min_healthy_percentage = 100
# forbids going below one healthy instance, so the replacement launches first.
# The band between the two must be 100 points or less, which is why min is 100
# here: the default min of 90 with a max of 200 would be rejected.
#
# access is not set, so it is "ssm" (the default): Session Manager through the
# instance role, no key pair.
module "instance" {
  source = "../../"

  name          = "single-instance-example"
  ami_id        = var.ami_id
  instance_type = "t4g.small"

  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids

  min_size = 1
  max_size = 1

  instance_refresh = {
    min_healthy_percentage = 100
    max_healthy_percentage = 200
    instance_warmup        = 120
  }
}
