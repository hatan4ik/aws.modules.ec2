# Single instance with a replacement-first refresh

One instance that is replaced without an outage window when its launch template
changes. This is the same module as `minimal`; the only difference that matters
is `instance_refresh`.

> **Not applied against a real account.** This example has been checked with
> `terraform fmt`, `terraform init -backend=false` and `terraform validate`.
> It has never been applied to an AWS account, so the refresh behavior described
> here comes from the Auto Scaling documentation, not from an observed run.

## The problem it solves

A single instance is a group with `min_size = max_size = 1`. With the module's
default `instance_refresh` (`min_healthy_percentage = 90`, no
`max_healthy_percentage`), a launch template change has an outage window while
the replacement boots: the group can terminate the one instance before its
replacement is in service, so the workload is down for the boot time. The
module warns about this with the advisory check
`single_instance_refresh_has_downtime`.

## The setting

```hcl
instance_refresh = {
  min_healthy_percentage = 100
  max_healthy_percentage = 200
  instance_warmup        = 120
}
```

`max_healthy_percentage = 200` lets the group run two instances while it rolls,
so the replacement launches before the old instance is terminated, which is the
documented way to avoid the outage window with one instance.
`min_healthy_percentage = 100` forbids dropping below one healthy instance.
`instance_warmup` is the number of seconds the replacement is given before it
counts as healthy; size it to your boot time. The check stays silent when the
group is configured this way (min 100, max 200).

The module rejects a band wider than 100 points
(`max_healthy_percentage - min_healthy_percentage <= 100`, which Auto Scaling
also enforces), so `max_healthy_percentage = 200` needs
`min_healthy_percentage = 100`; the default min of 90 is not enough.

Because the group briefly runs two instances, the workload must tolerate two
copies at once (a database or a single-writer service may not), and your
account needs capacity for both.

## What it creates

- One launch template and one Auto Scaling group with `min_size = max_size = 1`.
- One IAM role and instance profile named `single-instance-example-instance`,
  with `AmazonSSMManagedInstanceCore` attached.

The module always runs the instance with IMDSv2 required and no public IPv4
address (IPv6 follows the subnet). Every volume the module declares (here, the
root volume) is encrypted. There is no key pair by default: `access` is `ssm`,
so the documented way in is Session Manager. Anyone with `ssm:StartSession` on
the instance gets a shell as `ssm-user`, which is a sudoer, and sessions are not
logged unless Session Manager preferences are configured. To opt in to a key
pair, see [`ssh-key-pair`](../ssh-key-pair).

## What it needs from you

| Input | What it must be |
|-------|-----------------|
| `ami_id` | An AMI ID for arm64 (the example uses `t4g.small`) whose root device is `/dev/xvda`, such as Amazon Linux 2023. Changing it is what triggers the refresh. The module does not check who owns the AMI; image provenance is part of your trust boundary. |
| `subnet_ids` | One or more existing private subnets. One subnet raises the advisory `single_subnet` check; two let the group replace the instance in another zone if one fails. |
| `security_group_ids` | Existing security groups. The module creates none. |
| A route for Session Manager | A NAT gateway or the `ssm`, `ssmmessages`, and `ec2messages` VPC endpoints. |
| `region` | Any region where the instance type and AMI exist. The platform rule that limits it to US regions is recorded in `docs/ARCHITECTURE.md` of `devops-aws-infra`. |

The volumes use the AWS managed `aws/ebs` key because no `kms_key_arn` is set,
which raises `volumes_use_aws_managed_key`. The `complete` example shows a
customer managed key.

## Run

```hcl
# terraform.tfvars
subnet_ids         = ["subnet-0123456789abcdef0"]
security_group_ids = ["sg-0123456789abcdef0"]
ami_id             = "ami-0123456789abcdef0"
```

```sh
terraform init && terraform plan
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_instance"></a> [instance](#module\_instance) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | AMI ID to run. Pinning an AMI makes a change to it a reviewed launch template change that triggers the instance refresh. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region the fleet is created in. | `string` | `"us-east-1"` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Existing security group IDs attached to the instance. | `list(string)` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Existing private subnet IDs. One is enough for a single instance; two let the group replace the instance in another Availability Zone if one fails. | `list(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access"></a> [access](#output\_access) | How operators reach the instance: ssm, key\_pair, or both. |
| <a name="output_autoscaling_group_name"></a> [autoscaling\_group\_name](#output\_autoscaling\_group\_name) | Name of the Auto Scaling group that holds the one instance. |
| <a name="output_image_id"></a> [image\_id](#output\_image\_id) | Pinned AMI ID in the launch template. |
| <a name="output_instance_profile_name"></a> [instance\_profile\_name](#output\_instance\_profile\_name) | Name of the instance profile the module created. |
| <a name="output_launch_template_latest_version"></a> [launch\_template\_latest\_version](#output\_launch\_template\_latest\_version) | Launch template version the group runs; it increments on every launch template change, which starts the refresh. |
<!-- END_TF_DOCS -->
