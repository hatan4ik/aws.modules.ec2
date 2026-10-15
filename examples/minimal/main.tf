provider "aws" {
  region = var.region
}

# One instance: min_size and max_size both default to 1. EC2 resolves the AMI
# at launch from the public Amazon Linux 2023 arm64 parameter, and the module
# creates the instance role and profile.
#
# access is not set, so it is "ssm" (the default and the platform standard):
# Session Manager through the instance role, no key pair, no inbound rule. See
# examples/ssh-key-pair to opt in to a key pair.
module "instance" {
  source = "../../"

  name                   = "minimal-example"
  ami_ssm_parameter_name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
  instance_type          = "t4g.small"

  subnet_ids         = [var.subnet_id]
  security_group_ids = [var.security_group_id]
}
