# Minimal instance

One private EC2 instance and nothing else: the module's defaults, an existing
subnet and security group, and the public Amazon Linux 2023 arm64 AMI parameter.
Session Manager is the way in; no key pair is created or selected.

> **Not applied against a real account.** This example has been checked with
> `terraform fmt`, `terraform init -backend=false` and `terraform validate`,
> which prove the HCL is well formed and type-checks against the module's
> interface. This example itself has not been applied; the module it calls was
> applied once on 2026-10-15 (see [Live evidence](../../tests/integration/README.md#live-evidence-2026-10-15)).

## What it creates

- One launch template and one Auto Scaling group with `min_size = max_size = 1`
  (there is no separate single-instance mode, so a failed instance is replaced).
- One IAM role and instance profile named `minimal-example-instance`, with the
  AWS managed policy `AmazonSSMManagedInstanceCore` attached.

The module always runs the instance with IMDSv2 required and no public IPv4
address (IPv6 follows the subnet). Every volume the module declares (here, the
root volume) is encrypted, with the AWS managed `aws/ebs` key because no
`kms_key_arn` is set. There is no key pair by default: `access` is `ssm`, so the
documented way in is Session Manager through the instance role. To opt in to a
key pair, see [`ssh-key-pair`](../ssh-key-pair).

## What it needs from you

| Input | What it must be |
|-------|-----------------|
| `subnet_id` | An existing private subnet. |
| `security_group_id` | An existing security group. The module creates none; compose `aws.modules.security-group`. With Session Manager it needs outbound HTTPS to the endpoints below and no inbound rule. |
| A route for Session Manager | A NAT gateway or the `ssm`, `ssmmessages`, and `ec2messages` VPC endpoints, or the instance never registers and there is no way in. |
| `region` | Any region where the instance type and AMI parameter exist. The module is region-agnostic; the platform rule that limits it to US regions is recorded in `docs/ARCHITECTURE.md` of `devops-aws-infra`. |

## Things to know about the defaults

- **Anyone with `ssm:StartSession` on the instance gets a shell as `ssm-user`,
  which is a sudoer.** Session Manager sessions are not logged unless Session
  Manager preferences (CloudWatch Logs or S3 logging) are configured in the
  account and Region; this example does not configure them. Grant
  `ssm:StartSession` narrowly.
- **The image is part of the trust boundary.** The public AWS parameter points
  at an AWS-published AMI; a private parameter would let whoever can write it
  choose what every new instance boots.
- **`ami_ssm_parameter_name` is resolved by EC2 when an instance launches.** When
  the parameter moves to a newer AMI the launch template does not change, so the
  fleet is not rolled; only instances launched later get the new image. Use
  `ami_id` when the image must be pinned.
- **Encryption covers the volumes the module declares.** `root_volume.device_name`
  defaults to `/dev/xvda`, which is the root device of Amazon Linux 2023. An AMI
  that defines another volume under a different device name (see the `complete`
  example) is not covered by the module's encryption unless account-level EBS
  encryption by default is on.
- **Tags.** The module's `tags` (plus `Name`) reach the instance, its volumes,
  and its network interface through the launch template. Provider
  `default_tags` do not reach instances, volumes, or network interfaces.

## Advisory warnings you will see

A plan prints three non-blocking checks, because this example takes the
shortest path:

- `volumes_use_aws_managed_key`: no `kms_key_arn`, so volumes use the AWS managed
  `aws/ebs` key. See the `complete` example for a customer managed key.
- `single_subnet`: one subnet means one Availability Zone.
- `single_instance_refresh_has_downtime`: with the default `instance_refresh`, a
  launch template change has an outage window while the replacement boots. See
  the `single-instance` example.

## Run

```hcl
# terraform.tfvars
subnet_id         = "subnet-0123456789abcdef0"
security_group_id = "sg-0123456789abcdef0"
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
| <a name="input_region"></a> [region](#input\_region) | AWS region the fleet is created in. | `string` | `"us-east-1"` | no |
| <a name="input_security_group_id"></a> [security\_group\_id](#input\_security\_group\_id) | Existing security group ID attached to the instance. | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | Existing private subnet ID the instance launches into. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access"></a> [access](#output\_access) | How operators reach the instance: ssm, key\_pair, or both. |
| <a name="output_autoscaling_group_name"></a> [autoscaling\_group\_name](#output\_autoscaling\_group\_name) | Name of the Auto Scaling group. |
| <a name="output_iam_role_arn"></a> [iam\_role\_arn](#output\_iam\_role\_arn) | ARN of the instance role the module created. |
| <a name="output_image_id"></a> [image\_id](#output\_image\_id) | Image reference in the launch template (resolve:ssm:<parameter>). |
| <a name="output_launch_template_id"></a> [launch\_template\_id](#output\_launch\_template\_id) | ID of the launch template. |
<!-- END_TF_DOCS -->
