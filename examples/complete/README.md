# Complete fleet

A load-balanced, autoscaled, encrypted private fleet that exercises most of the
inputs of `aws.modules.ec2` in one call. Use it as a reference for the shape of
each input, then copy the parts you need.

> **Not applied against a real account.** This example has been checked with
> `terraform fmt`, `terraform init -backend=false` and `terraform validate`.
> This example itself has not been applied: no load balancer target has
> registered through it and its user data has not run. The module it calls, and
> the key policy the preset renders, were exercised live on 2026-10-15 (see
> [Live evidence](../../tests/integration/README.md#live-evidence-2026-10-15)).

## What it creates

- One launch template: a pinned `ami_id`, `m7g.large`, a 50 GiB gp3 root volume
  (`/dev/xvda`) and a 100 GiB gp3 data volume (`/dev/sdf`, 4000 IOPS,
  250 MiB/s), both encrypted with your customer managed key, and the user data
  below.
- One Auto Scaling group across at least two subnets, `min_size = 2`,
  `max_size = 6`, `desired_capacity` left null so scaling is not drift, registered
  with your target group, with `health_check_type = "ELB"` and a 300 second grace
  period.
- One CPU target tracking policy at 60 percent average utilization.
- An instance refresh with `min_healthy_percentage = 50`, so a two-instance fleet
  rolls one instance at a time.
- Either an IAM role and instance profile named `complete-example-instance`
  (default), or your existing profile when `existing_instance_profile_name` is
  set. The example sets `create_instance_profile` from that choice and fills the
  role inputs only when it creates the role, because the module rejects them
  when a profile is supplied. The created role carries
  `AmazonSSMManagedInstanceCore` (because `access = "ssm"`), the CloudWatch
  agent managed policy (`iam_policy_arns`, keyed `cloudwatch_agent`), an inline
  policy named `ReadReleaseArtifacts` that reads one S3 prefix
  (`iam_inline_policies`), and an optional permissions boundary.
- Tags `Environment` and `Team` on the group, template, role, instances, volumes,
  and network interfaces, plus the `Name` tag the module adds.

The module always runs the instances with IMDSv2 required and no public IPv4
address (IPv6 follows the subnet). Every volume the module declares, the root
volume and each `ebs_volumes` entry, is encrypted; see
[Root device names](#root-device-names) for what that does not cover. There is
no key pair by default: `access = "ssm"`, so the documented way in is Session
Manager. To opt in to a key pair, see [`ssh-key-pair`](../ssh-key-pair).

## What it needs from you

| Input | What it must be |
|-------|-----------------|
| `ami_id` | An arm64 Amazon Linux 2023 AMI (root device `/dev/xvda`, with `dnf`, because the user data installs nginx). The module does not check who owns the AMI: image provenance is part of your trust boundary, so restrict AMI sources with an SCP or the EC2 Allowed AMIs setting. |
| `subnet_ids` | At least two existing private subnets in different Availability Zones. |
| `security_group_ids` | Existing groups that allow the load balancer to reach port 80. The module creates none; compose `aws.modules.security-group`. No inbound rule is needed for Session Manager. |
| `kms_key_arn` | The full ARN of a customer managed key, from `aws.modules.kms`. An alias or bare key ID is rejected: the module requires the full ARN so it can be validated at plan time. |
| `target_group_arn` | An existing target group on port 80, for example from `aws.modules.alb`, with a health check the nginx default page passes. |
| A route to the internet or VPC endpoints | For `dnf` to reach the package repositories and for Session Manager (`ssm`, `ssmmessages`, `ec2messages`). |
| `existing_instance_profile_name` (optional) | A profile that grants SSM access itself. Leave null to have the module create the role. |
| `artifact_bucket_arn` (optional) | The bucket whose `releases/` prefix the created role may read. The default is a placeholder. |

## The KMS key policy

When a customer managed key encrypts volumes launched by an Auto Scaling group,
the key policy must allow the service-linked role
`AWSServiceRoleForAutoScaling` to use the key and to create grants. The instance
role does not help: the service-linked role makes the launch call. Without the
policy the group cannot launch instances; the failure shows up in the scaling
activity history rather than as a Terraform error on the key. The exact error
text was not verified.

`aws.modules.kms` has a preset for exactly this. It needs release **v2.1.0 or
later** (commit `66f78e1c4ef81a3fbf36af8133f4a632a2e80f27`); `v2.0.0` does not contain it.

```hcl
module "fleet_key" {
  source = "git::https://github.com/hatan4ik/aws.modules.kms.git?ref=66f78e1c4ef81a3fbf36af8133f4a632a2e80f27" # v2.1.0"

  description = "EBS key for the complete-example fleet"
  aliases     = ["complete-example/ebs"]
  account_id  = "123456789012"
  partition   = "aws"

  # Renders AutoScalingEbs (use) and AutoScalingEbsAttachPersistentResources
  # (kms:CreateGrant with kms:GrantIsForAWSResource = true).
  service_grants = {
    AutoScalingEbs = { service = "autoscaling-ebs" }
  }
}
```

Pass `module.fleet_key.arn` as `kms_key_arn`. Two things to know:

- **The service-linked role must already exist.** KMS rejects a key policy that
  names a principal that does not exist. An account that has never created an
  Auto Scaling group has no `AWSServiceRoleForAutoScaling`; create it first:

  ```hcl
  resource "aws_iam_service_linked_role" "autoscaling" {
    aws_service_name = "autoscaling.amazonaws.com"
  }
  ```

  Creating it fails if the account already has it, so add this only for an
  account that has never used Auto Scaling, and make the key depend on it.
- **A kms release before v2.1.0** needs the same two statements
  through `policy_statements`. This is the fallback shape, with placeholder
  account IDs:

  ```hcl
  policy_statements = {
    AllowAutoScalingUseOfKey = {
      principals = {
        AWS = ["arn:aws:iam::123456789012:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
      }
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
    }

    AllowAutoScalingCreateGrant = {
      principals = {
        AWS = ["arn:aws:iam::123456789012:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
      }
      actions = ["kms:CreateGrant"]
      conditions = [{
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }]
    }
  }
  ```

Neither snippet has been fed through a plan of `aws.modules.kms` or accepted by
the KMS API.

## Root device names

`root_volume.device_name` must be the root device the AMI defines, because the
launch template overrides the AMI's block device mapping by device name:

| AMI family | Root device |
|------------|-------------|
| Amazon Linux 2023, Amazon Linux 2, Bottlerocket (OS volume) | `/dev/xvda` |
| Ubuntu, Debian | `/dev/sda1` |

Read it from the image instead of guessing:

```sh
aws ec2 describe-images --image-ids ami-0123456789abcdef0 \
  --query 'Images[0].[RootDeviceName,BlockDeviceMappings[].DeviceName]'
```

A wrong name adds a second volume instead of resizing the root. The module
encrypts the volumes it declares, the root volume and `ebs_volumes`. **A volume
the AMI defines under another device name is not covered** (Bottlerocket's
separate data volume is one example, per its documentation) unless account-level
EBS encryption by default is on. Name such a device in `ebs_volumes` if the
module should encrypt it.

## Notes

- **The AMI is pinned.** Changing `ami_id` creates a new launch template version
  and rolls the fleet. With `ami_ssm_parameter_name` the parameter is resolved
  when an instance launches, so a moved parameter does not roll the fleet, and
  whoever can write a private parameter controls what every new instance boots.
- **The data volume is unformatted.** It is attached at launch; formatting and
  mounting it is the workload's job.
- **The user data is a placeholder.** It installs and starts nginx so there is
  something to health check; it was never executed. Do not put secrets in user
  data: it is stored in Terraform state and plan output, kept in every older
  launch template version, readable by any local process through the metadata
  service, and readable through the EC2 API.
- **Session Manager.** Anyone with `ssm:StartSession` on an instance gets a shell
  as `ssm-user`, which is a sudoer. Sessions are not logged unless Session
  Manager preferences are configured in the account and Region; the example does
  not configure them.
- **The metadata hop limit stays at 1.** Setting `metadata_hop_limit = 2` lets
  every container on the instance obtain the instance role's credentials, so
  keep that role minimal if you do.
- **Tags are metadata, not secrets.** Anyone who can describe the instances sees
  them. The module's `tags` reach instances, volumes, and network interfaces
  through the launch template; provider `default_tags` do not.
- **Snapshots.** This example has no `snapshot_id`. If you add one, the module
  requests `encrypted = true` and your key, but whether AWS accepts a restore
  from an unencrypted snapshot into an encrypted volume was not verified; if it
  refuses, the failure is at launch, not at plan.
- **Role permissions.** Everything that can read the instance metadata service
  can use the role. The advisory check `broad_instance_role` warns on an
  administrator-class managed policy or an inline `Action: "*"`; this example
  triggers neither.

## Run

```hcl
# terraform.tfvars
ami_id             = "ami-0123456789abcdef0"
subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
security_group_ids = ["sg-0123456789abcdef0"]
kms_key_arn        = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
target_group_arn   = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/app/0123456789abcdef"
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
| <a name="module_fleet"></a> [fleet](#module\_fleet) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ami_id"></a> [ami\_id](#input\_ami\_id) | AMI ID to run, built for arm64 (the example uses an m7g instance type). | `string` | n/a | yes |
| <a name="input_artifact_bucket_arn"></a> [artifact\_bucket\_arn](#input\_artifact\_bucket\_arn) | ARN of the S3 bucket whose releases/ prefix the created role may read. Used only when the module creates the role. | `string` | `"arn:aws:s3:::example-release-artifacts"` | no |
| <a name="input_existing_instance_profile_name"></a> [existing\_instance\_profile\_name](#input\_existing\_instance\_profile\_name) | Name of an existing instance profile to attach. Null makes the module create a role and profile with the extra policies below. An existing profile must grant SSM access itself, because the module attaches nothing to a profile it did not create. | `string` | `null` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Full ARN of the customer managed KMS key that encrypts the volumes (a single-Region or multi-Region mrk- key). The module needs the full ARN so it can be validated at plan time. Its key policy must allow the Auto Scaling service-linked role. | `string` | n/a | yes |
| <a name="input_permissions_boundary_arn"></a> [permissions\_boundary\_arn](#input\_permissions\_boundary\_arn) | Permissions boundary for the created role. Null sets none. Used only when the module creates the role. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region the fleet is created in. | `string` | `"us-east-1"` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Existing security group IDs attached to every instance. They must allow the load balancer to reach the workload port. | `list(string)` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Existing private subnet IDs in at least two Availability Zones. | `list(string)` | n/a | yes |
| <a name="input_target_group_arn"></a> [target\_group\_arn](#input\_target\_group\_arn) | ARN of an existing load balancer target group (port 80) the instances register with. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access"></a> [access](#output\_access) | How operators reach the instances: ssm, key\_pair, or both. |
| <a name="output_autoscaling_group_arn"></a> [autoscaling\_group\_arn](#output\_autoscaling\_group\_arn) | ARN of the Auto Scaling group. |
| <a name="output_autoscaling_group_name"></a> [autoscaling\_group\_name](#output\_autoscaling\_group\_name) | Name of the Auto Scaling group. |
| <a name="output_iam_role_arn"></a> [iam\_role\_arn](#output\_iam\_role\_arn) | ARN of the created role. Null when an existing instance profile is supplied. |
| <a name="output_image_id"></a> [image\_id](#output\_image\_id) | Pinned AMI ID in the launch template. |
| <a name="output_instance_profile_name"></a> [instance\_profile\_name](#output\_instance\_profile\_name) | Name of the instance profile attached to the instances (created or supplied). |
| <a name="output_launch_template_id"></a> [launch\_template\_id](#output\_launch\_template\_id) | ID of the launch template. |
| <a name="output_launch_template_latest_version"></a> [launch\_template\_latest\_version](#output\_launch\_template\_latest\_version) | Launch template version the group runs. |
| <a name="output_scaling_policy_arn"></a> [scaling\_policy\_arn](#output\_scaling\_policy\_arn) | ARN of the CPU target tracking policy. |
<!-- END_TF_DOCS -->
