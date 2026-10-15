# Integration suite: real apply in the caller's own account.
#
# Requires AWS credentials and a region from the environment (for example
# AWS_PROFILE and AWS_REGION, or the OIDC role assumed by the integration
# workflow) and the ARN of a pre-created, tagged, disposable KMS key passed on
# the command line as volume_key_arn (see tests/integration/README.md). Pass it
# quoted, -var 'volume_key_arn="arn:..."': whether terraform test parses a -var
# for a name that only a run's module declares as an HCL expression or as a
# plain string depends on the Terraform version, and the run below trims the
# quotes so the quoted form works either way.
# Nothing else is hard-coded: the setup module creates a disposable VPC with two
# private subnets, Systems Manager interface endpoints, a security group with no
# inbound rules, and an EC2 key pair registered from a throwaway PUBLIC key. The
# module then launches a one-instance group from the Amazon Linux 2023 SSM
# parameter, and the results are read back from the EC2, Auto Scaling, and
# Systems Manager APIs by the inspect module. Everything is destroyed at the end
# of the file, in reverse order.
#
# Two fleets are exercised in sequence:
#
#   smoke           access = ssm (the default): no key pair, Session Manager.
#   smoke_key_pair  access = both: the fixture's key pair plus Session Manager.
#
# Both runs use the root module's one state, so the second run changes the fleet
# name and Terraform REPLACES the first fleet (destroy, then create) rather than
# updating it in place. This suite therefore proves what AWS reports for each
# configuration, not an in-place launch template roll. The key_pair_public_key
# path (the module registering the key itself) is covered only by the mocked
# contract tests in tests/, not here.
#
# This suite ran once, on 2026-10-15, with administrator credentials in a
# sandbox account, and passed (see "Live evidence" in tests/integration/README.md).
# It has not run under the least-privilege CI role.
#
# Run: terraform init -backend=false -test-directory=tests/integration
#      terraform test -test-directory=tests/integration \
#        -var 'volume_key_arn="arn:aws:kms:<region>:<account>:key/<key-id>"' \
#        -filter=tests/integration/smoke.tftest.hcl

provider "aws" {}

run "setup" {
  module {
    source = "./tests/integration/setup"
  }

  variables {
    name_prefix    = "ec2-it"
    volume_key_arn = trim(var.volume_key_arn, "\"")
  }
}

run "smoke" {
  variables {
    name               = run.setup.name
    subnet_ids         = run.setup.subnet_ids
    security_group_ids = [run.setup.security_group_id]
    kms_key_arn        = run.setup.kms_key_arn
    tags               = run.setup.tags

    # access is left at its default (ssm) on purpose: the suite proves the
    # default, and key_pair_name / key_pair_public_key stay null.

    # The policy scopes IAM to this path and the ec2-it- name prefix.
    iam_role_path = run.setup.iam_role_path

    # Resolved by EC2 at launch, which also proves the caller and the Auto
    # Scaling service-linked role may read the public parameter. x86_64 to
    # match t3.micro.
    ami_ssm_parameter_name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    instance_type          = "t3.micro"

    # One instance, and the replacement would launch first if the template
    # ever changed. region and partition stay null on purpose: the suite
    # proves the module's inherit-from-provider behaviour.
    min_size         = 1
    max_size         = 1
    instance_refresh = { min_healthy_percentage = 100, max_healthy_percentage = 200 }

    # Terraform's own capacity wait is the InService proof: the provider
    # returns only when min_size instances are InService and Healthy, and
    # fails the apply at the timeout.
    wait_for_capacity_timeout = "10m"
  }

  assert {
    condition     = output.autoscaling_group_name == run.setup.name
    error_message = "The Auto Scaling group must be named after the fleet."
  }

  assert {
    condition     = startswith(output.autoscaling_group_arn, "arn:${run.setup.partition}:autoscaling:${run.setup.region}:${run.setup.account_id}:autoScalingGroup:") && endswith(output.autoscaling_group_arn, ":autoScalingGroupName/${run.setup.name}")
    error_message = "The group ARN must be in the caller's partition, Region, and account and end in the group name."
  }

  assert {
    condition     = can(regex("^lt-[0-9a-f]+$", output.launch_template_id)) && startswith(output.launch_template_arn, "arn:${run.setup.partition}:ec2:${run.setup.region}:${run.setup.account_id}:launch-template/")
    error_message = "EC2 must have returned a launch template ID and ARN in the caller's partition, Region, and account."
  }

  assert {
    condition     = tonumber(output.launch_template_latest_version) >= 1
    error_message = "The launch template must have at least one version."
  }

  assert {
    condition     = output.image_id == "resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    error_message = "The launch template must carry the unresolved SSM reference, not a pinned AMI ID."
  }

  assert {
    condition     = output.iam_role_name == "${run.setup.name}-instance" && output.instance_profile_name == "${run.setup.name}-instance"
    error_message = "The created role and instance profile must be named <name>-instance."
  }

  assert {
    condition     = startswith(output.iam_role_arn, "arn:${run.setup.partition}:iam::${run.setup.account_id}:role${run.setup.iam_role_path}") && startswith(output.instance_profile_arn, "arn:${run.setup.partition}:iam::${run.setup.account_id}:instance-profile${run.setup.iam_role_path}")
    error_message = "The role and instance profile ARNs must be in the caller's partition and account, under the fixture's IAM path."
  }

  assert {
    condition     = output.access == "ssm" && output.key_pair_name == null
    error_message = "The default access must be ssm with no key pair name."
  }

  assert {
    condition     = aws_launch_template.this.key_name == null || aws_launch_template.this.key_name == ""
    error_message = "With access = ssm the launch template must carry no key pair."
  }

  assert {
    condition     = length(aws_key_pair.this) == 0 && length(aws_iam_role_policy_attachment.ssm) == 1
    error_message = "With access = ssm the module registers no key pair and attaches the SSM managed policy."
  }

  assert {
    condition     = output.scaling_policy_arn == null
    error_message = "No scaling policy is requested, so none may exist."
  }

  assert {
    condition     = aws_autoscaling_group.this.min_size == 1 && aws_autoscaling_group.this.max_size == 1 && aws_autoscaling_group.this.desired_capacity == 1
    error_message = "The group must be a one-instance group; desired_capacity is left to AWS and must come back as 1."
  }

  assert {
    condition = (
      aws_launch_template.this.metadata_options[0].http_tokens == "required" &&
      aws_launch_template.this.network_interfaces[0].associate_public_ip_address == "false" &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].encrypted == "true"
    )
    error_message = "The launch template must require IMDSv2, assign no public IP, and encrypt the root volume."
  }
}

# What EC2, Auto Scaling, and Systems Manager report for the running fleet,
# as opposed to what Terraform's state says. The module is not involved here.
run "inspect_ssm" {
  module {
    source = "./tests/integration/inspect"
  }

  variables {
    autoscaling_group_name = run.smoke.autoscaling_group_name
  }

  assert {
    condition = (
      output.group.min_size == 1 &&
      output.group.max_size == 1 &&
      output.group.desired_capacity == 1 &&
      output.group.health_check_type == "EC2" &&
      output.group.launch_template_id == run.smoke.launch_template_id &&
      output.group.vpc_zone_identifier == sort(run.setup.subnet_ids)
    )
    error_message = "The Auto Scaling API must report a one-instance EC2-health-checked group on the module's launch template across both private subnets."
  }

  assert {
    condition     = length(output.instance_ids) == 1
    error_message = "Exactly one running instance must carry the group's aws:autoscaling:groupName tag."
  }

  assert {
    condition = alltrue([
      for instance in values(output.instances) : (
        instance.instance_state == "running" &&
        instance.http_tokens == "required" &&
        instance.http_endpoint == "enabled" &&
        instance.http_put_response_hop_limit == 1 &&
        instance.instance_metadata_tags == "disabled"
      )
    ])
    error_message = "Every instance must be running with IMDSv2 required, the endpoint enabled, hop limit 1, and metadata tags off."
  }

  assert {
    condition = alltrue([
      for instance in values(output.instances) : (
        (instance.public_ip == null || instance.public_ip == "") &&
        instance.associate_public_ip_address != true &&
        (instance.key_name == null || instance.key_name == "") &&
        contains(run.setup.subnet_ids, instance.subnet_id) &&
        toset(instance.vpc_security_group_ids) == toset([run.setup.security_group_id])
      )
    ])
    error_message = "Every instance must have no public IPv4 address and no key pair, sit in one of the private subnets, and carry exactly the fixture's security group."
  }

  assert {
    condition = alltrue([
      for instance in values(output.instances) : (
        instance.iam_instance_profile == run.smoke.instance_profile_name
      )
    ])
    error_message = "Every instance must run with the module's instance profile."
  }

  assert {
    condition = alltrue([
      for instance in values(output.instances) : (
        instance.root_encrypted == true &&
        instance.root_kms_key_id == run.setup.kms_key_arn &&
        instance.root_volume_encrypted == true &&
        instance.root_volume_kms_key_id == run.setup.kms_key_arn &&
        instance.extra_ebs_volume_count == 0
      )
    ])
    error_message = "Every instance must have only its root volume, encrypted with the customer managed key."
  }

  assert {
    condition = alltrue([
      for instance in values(output.instances) : (
        instance.root_device_name == "/dev/xvda" &&
        instance.root_volume_type == "gp3" &&
        instance.root_volume_size == 30 &&
        instance.root_delete_on_termination == true
      )
    ])
    error_message = "The root volume must be the 30 GiB gp3 default on /dev/xvda and be deleted with the instance."
  }

  assert {
    condition = alltrue([
      for instance in values(output.instances) : (
        lookup(instance.tags, "Name", null) == run.setup.name &&
        lookup(instance.tags, "IntegrationTest", null) == "aws.modules.ec2" &&
        lookup(instance.tags, "Disposable", null) == "true" &&
        lookup(instance.root_volume_tags, "Name", null) == run.setup.name &&
        lookup(instance.root_volume_tags, "Disposable", null) == "true"
      )
    ])
    error_message = "Caller tags and the Name tag must reach the instances and, through the launch template, their volumes."
  }

  # Registration is not part of Auto Scaling's InService, so this waits
  # ssm_registration_wait first. It is the claim that Session Manager works with
  # the module's role and no NAT.
  assert {
    condition     = length(output.ssm_online_instance_ids) == 1 && output.ssm_online_instance_ids == output.instance_ids
    error_message = "The instance must be registered with Systems Manager and Online, through the interface endpoints and the module's instance role."
  }
}

# access = both with a key pair the fixture registered. The name changes, so
# Terraform replaces the first fleet; see the header.
run "smoke_key_pair" {
  variables {
    name               = "${run.setup.name}-kp"
    subnet_ids         = run.setup.subnet_ids
    security_group_ids = [run.setup.security_group_id]
    kms_key_arn        = run.setup.kms_key_arn
    tags               = run.setup.tags
    iam_role_path      = run.setup.iam_role_path

    access        = "both"
    key_pair_name = run.setup.key_pair_name

    ami_ssm_parameter_name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    instance_type          = "t3.micro"

    min_size         = 1
    max_size         = 1
    instance_refresh = { min_healthy_percentage = 100, max_healthy_percentage = 200 }

    wait_for_capacity_timeout = "10m"
  }

  assert {
    condition     = output.autoscaling_group_name == "${run.setup.name}-kp"
    error_message = "The Auto Scaling group must be named after the fleet."
  }

  assert {
    condition     = output.access == "both" && output.key_pair_name == run.setup.key_pair_name
    error_message = "access = both with key_pair_name must report the fixture's key pair."
  }

  assert {
    condition     = aws_launch_template.this.key_name == run.setup.key_pair_name
    error_message = "The launch template must carry the fixture's key pair name as key_name."
  }

  assert {
    condition     = length(aws_key_pair.this) == 0
    error_message = "key_pair_name selects an existing key pair, so the module must register none."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm) == 1 && endswith(aws_iam_role_policy_attachment.ssm[0].policy_arn, ":policy/AmazonSSMManagedInstanceCore")
    error_message = "access = both must keep the SSM managed policy attached so Session Manager still works."
  }

  assert {
    condition = (
      aws_launch_template.this.metadata_options[0].http_tokens == "required" &&
      aws_launch_template.this.network_interfaces[0].associate_public_ip_address == "false" &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].encrypted == "true"
    )
    error_message = "The launch template must still require IMDSv2, assign no public IP, and encrypt the root volume."
  }
}

run "inspect_both" {
  module {
    source = "./tests/integration/inspect"
  }

  variables {
    autoscaling_group_name = run.smoke_key_pair.autoscaling_group_name
  }

  assert {
    condition = (
      output.group.min_size == 1 &&
      output.group.max_size == 1 &&
      output.group.desired_capacity == 1 &&
      output.group.launch_template_id == run.smoke_key_pair.launch_template_id &&
      output.group.vpc_zone_identifier == sort(run.setup.subnet_ids)
    )
    error_message = "The Auto Scaling API must report a one-instance group on the key-pair fleet's launch template across both private subnets."
  }

  assert {
    condition     = length(output.instance_ids) == 1
    error_message = "Exactly one running instance must carry the key-pair group's aws:autoscaling:groupName tag."
  }

  # EC2's own view of the key pair and of the address: the key name reaches the
  # instance, and attaching a key pair does not give it a public IPv4 address.
  assert {
    condition = alltrue([
      for instance in values(output.instances) : (
        instance.key_name == run.setup.key_pair_name &&
        (instance.public_ip == null || instance.public_ip == "") &&
        instance.associate_public_ip_address != true &&
        contains(run.setup.subnet_ids, instance.subnet_id) &&
        toset(instance.vpc_security_group_ids) == toset([run.setup.security_group_id])
      )
    ])
    error_message = "Every instance must carry the fixture's key pair, have no public IPv4 address, sit in a private subnet, and carry exactly the fixture's security group."
  }

  assert {
    condition = alltrue([
      for instance in values(output.instances) : (
        instance.instance_state == "running" &&
        instance.http_tokens == "required" &&
        instance.http_endpoint == "enabled" &&
        instance.http_put_response_hop_limit == 1 &&
        instance.instance_metadata_tags == "disabled" &&
        instance.iam_instance_profile == run.smoke_key_pair.instance_profile_name
      )
    ])
    error_message = "Every instance must be running with IMDSv2 required, the endpoint enabled, hop limit 1, metadata tags off, and the module's instance profile."
  }

  assert {
    condition = alltrue([
      for instance in values(output.instances) : (
        instance.root_encrypted == true &&
        instance.root_kms_key_id == run.setup.kms_key_arn &&
        instance.root_volume_encrypted == true &&
        instance.root_volume_kms_key_id == run.setup.kms_key_arn &&
        instance.extra_ebs_volume_count == 0
      )
    ])
    error_message = "Every instance must have only its root volume, encrypted with the customer managed key."
  }

  assert {
    condition = alltrue([
      for instance in values(output.instances) : (
        lookup(instance.tags, "Name", null) == "${run.setup.name}-kp" &&
        lookup(instance.tags, "IntegrationTest", null) == "aws.modules.ec2" &&
        lookup(instance.root_volume_tags, "Name", null) == "${run.setup.name}-kp"
      )
    ])
    error_message = "Caller tags and the Name tag must reach the key-pair fleet's instances and root volumes."
  }

  # access = both keeps Session Manager: the key pair adds a way in, it does
  # not replace the default one.
  assert {
    condition     = length(output.ssm_online_instance_ids) == 1 && output.ssm_online_instance_ids == output.instance_ids
    error_message = "With access = both the instance must still register with Systems Manager and be Online."
  }
}
