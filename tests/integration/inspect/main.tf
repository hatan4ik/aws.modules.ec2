# Read-only view of what AWS actually built for the fleet under test. The
# module's own outputs are what Terraform believes; everything here is read
# back from the EC2, Auto Scaling, and Systems Manager APIs, so the smoke suite
# can assert on the real instances. No resource here changes the account except
# a local timer.

data "aws_autoscaling_group" "this" {
  name = var.autoscaling_group_name
}

# Every instance an Auto Scaling group launches carries this tag. The state
# filter excludes instances that are still shutting down from an earlier run
# of the same group.
data "aws_instances" "fleet" {
  instance_state_names = ["running"]

  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [var.autoscaling_group_name]
  }
}

data "aws_instance" "this" {
  for_each = toset(data.aws_instances.fleet.ids)

  instance_id = each.value
}

data "aws_ebs_volume" "root" {
  for_each = data.aws_instance.this

  most_recent = true

  filter {
    name   = "volume-id"
    values = [one(each.value.root_block_device).volume_id]
  }
}

# The instances are registered with Systems Manager by the agent a few minutes
# after boot. Terraform's own capacity wait only covers Auto Scaling health.
# The trigger re-creates the timer, and so waits again, when the smoke suite
# inspects a second group (the access = both run replaces the first fleet).
resource "time_sleep" "ssm_registration" {
  create_duration = var.ssm_registration_wait

  triggers = {
    autoscaling_group_name = var.autoscaling_group_name
  }
}

data "aws_ssm_instances" "online" {
  # An empty InstanceIds filter is an API error; with no instances the smoke
  # suite's own assertions report the real problem.
  count = length(data.aws_instances.fleet.ids) > 0 ? 1 : 0

  filter {
    name   = "InstanceIds"
    values = data.aws_instances.fleet.ids
  }

  filter {
    name   = "PingStatus"
    values = ["Online"]
  }

  depends_on = [time_sleep.ssm_registration]
}
