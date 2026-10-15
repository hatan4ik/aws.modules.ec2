# Integration fixtures

Disposable prerequisites for the integration suites in the parent directory:
a VPC with two private subnets and no route to the internet, interface
endpoints for `ssm`, `ssmmessages`, and `ec2messages` so Session Manager works
without a NAT gateway, an instance security group with no inbound rules and
egress on 443 to the endpoints only, and an EC2 key pair registered from a
throwaway **public** key. Everything is named with a random suffix and tagged
`Disposable=true` and `IntegrationTest=aws.modules.ec2`. `terraform test`
creates them in the caller's own account before the module under test and
destroys them afterwards. They are not a deployable pattern and are excluded
from policy scans (see `.checkov.yml` and `trivy.yaml` at the repository root).

> **Status: never applied.** These fixtures validate (`terraform fmt`, `init`,
> `validate`) and nothing more. No real AWS account has seen them.

## Prerequisites an administrator creates once

The integration role deliberately cannot create or tag KMS keys and cannot
create service-linked roles, so two things must exist before the first run.

### 1. The Auto Scaling service-linked role

Auto Scaling launches the fleet's instances through
`AWSServiceRoleForAutoScaling`, and the volume key's policy names it. KMS
rejects a key policy that names a principal that does not exist, so the role
must exist before the key is created. AWS creates it when the first Auto
Scaling group is created in an account by a principal that may create
service-linked roles; an account that has never had a group does not have it.
The fixture looks it up (`iam:GetRole`, scoped to that one ARN) and fails with
`NoSuchEntity` when it is missing.

Create it once, as an administrator, with the CLI:

```bash
aws iam create-service-linked-role --aws-service-name autoscaling.amazonaws.com
```

or with Terraform, in the administrator's own configuration, before the key:

```hcl
resource "aws_iam_service_linked_role" "autoscaling" {
  aws_service_name = "autoscaling.amazonaws.com"
}
```

Creating it fails when the account already has it, so add this only to an
account that has never used Auto Scaling, and make the key depend on it. The
fixture does not create the role: it is account-wide, shared by every Auto
Scaling group, and a disposable run must not own or delete it.

### 2. A disposable, tagged volume key

Create one symmetric customer managed key, in the Region the suite runs in,
and tag it `IntegrationTest=aws.modules.ec2` and `Disposable=true`. The
integration role may use and grant on a key that carries the `IntegrationTest`
tag and nothing else: it holds no `kms:CreateKey`, no `kms:TagResource`, no
`kms:PutKeyPolicy`, and no deletion permission, so it can neither mint nor
claim a key. The suite takes the key's ARN as the `volume_key_arn` variable
(`AWS_INTEGRATION_KMS_KEY_ARN` for `make integration-smoke` and the workflow).
The key outlives the runs and is billed while it exists.

The key policy must allow the Auto Scaling service-linked role to use the key
and to create grants for AWS resources; without it the group cannot launch and
the run fails at `wait_for_capacity_timeout`. The fixture cannot read the policy
back, so it cannot check this. With `aws.modules.kms` the statements are a
preset (`service_grants = { AutoScalingEbs = { service = "autoscaling-ebs" } }`),
which at the time of writing is merged on that module's `main` and not in a
tagged release (v2.0.0 does not contain it); pin a commit of a later release
once one is tagged:

```hcl
module "integration_volume_key" {
  source = "git::https://github.com/hatan4ik/aws.modules.kms.git?ref=<commit-sha of a release newer than v2.0.0>"

  description = "Disposable volume key for the aws.modules.ec2 integration suite"
  aliases     = ["ec2-integration/volumes"]
  account_id  = "123456789012"
  partition   = "aws"

  # Renders AutoScalingEbs (use) and AutoScalingEbsAttachPersistentResources
  # (kms:CreateGrant with kms:GrantIsForAWSResource = true).
  service_grants = {
    AutoScalingEbs = { service = "autoscaling-ebs" }
  }

  tags = {
    IntegrationTest = "aws.modules.ec2"
    Disposable      = "true"
  }

  depends_on = [aws_iam_service_linked_role.autoscaling]
}
```

A `kms` release that predates the preset takes the same two statements through
`policy_statements` (placeholder account ID):

```hcl
policy_statements = {
  AllowAutoScalingUseOfKey = {
    principals = {
      AWS = ["arn:aws:iam::123456789012:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
    actions = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
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

Neither snippet has been planned against `aws.modules.kms` or accepted by the
KMS API from this repository. Replace the `<REGION>`, `<ACCOUNT_ID>`, and
`<KEY_ID>` placeholders of `iam/integration-permissions-policy.json` with this
key's Region, account, and key ID.

## Inputs worth knowing

- `volume_key_arn` is required and must be a full key ARN. It reaches the
  fixture through `-var 'volume_key_arn="arn:..."'` on `terraform test` (the
  Makefile and the workflow add the inner double quotes). The root module does
  not declare this variable, and `terraform test` handles such a `-var` as an
  HCL expression or as a plain string depending on whether a run's module
  declares the same name (observed on 1.7.5: plain string). The test file
  trims the quotes, so the quoted form is correct either way; an unquoted
  value can fail to parse where the HCL mode applies.
- `iam_role_path` (default `/ec2-it/`) is the IAM path the fleet's role and
  profile are created under. The permissions policy scopes every IAM
  statement to `role/ec2-it/ec2-it-*`; change the path and the policy together.
- `ssh_public_key` defaults to a throwaway ed25519 public key whose private
  half was discarded at generation. The key pair exists so the suite can prove
  that `access = "both"` attaches a key pair; nobody can authenticate with it,
  and the instance security group has no inbound rules in any case. A key pair
  alone opens nothing.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.6.0, < 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.6.0, < 4.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_key_pair.ssh](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) | resource |
| [aws_security_group.endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.instances](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_security_group_egress_rule.instances_to_endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.endpoints_from_instances](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [random_id.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_role.autoscaling_service_linked_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_role) | data source |
| [aws_kms_key.volumes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/kms_key) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cidr_block"></a> [cidr\_block](#input\_cidr\_block) | CIDR of the disposable VPC. It is /16 and the two private subnets are /24 slices of it. | `string` | `"10.98.0.0/16"` | no |
| <a name="input_iam_role_path"></a> [iam\_role\_path](#input\_iam\_role\_path) | IAM path the fleet's role and instance profile are created under (the module's iam\_role\_path). The integration permissions policy scopes every IAM statement to this path and the ec2-it- name prefix, so change both together. | `string` | `"/ec2-it/"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for every disposable fixture; a random suffix is appended so concurrent runs never collide. The result is the fleet name under test, the prefix of its IAM role, and the Auto Scaling group name, which the integration permissions policy scopes on (ec2-it-*). | `string` | `"ec2-it"` | no |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | OpenSSH PUBLIC key registered as the fixture's EC2 key pair. The default is a throwaway ed25519 public key whose private half was discarded at generation, so the key pair can be attached to instances but nobody can authenticate with it. Never put a private key here. | `string` | `"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ0j+WM7mygcQY1jJRfkfcPRdenSLaeGbKJPsYlAcThN aws.modules.ec2-integration-throwaway"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every fixture in addition to the identifying defaults. | `map(string)` | `{}` | no |
| <a name="input_volume_key_arn"></a> [volume\_key\_arn](#input\_volume\_key\_arn) | ARN of a pre-created, disposable customer managed KMS key, in the Region the suite runs in, that encrypts the fleet's volumes. Create it once as an administrator, tag it IntegrationTest=aws.modules.ec2 and Disposable=true, and give its policy the Auto Scaling service-linked role (see README.md). The integration role can use and grant on a key carrying that tag and cannot create, tag, re-policy, or delete keys. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_account_id"></a> [account\_id](#output\_account\_id) | Account the caller's credentials belong to. |
| <a name="output_autoscaling_service_linked_role_arn"></a> [autoscaling\_service\_linked\_role\_arn](#output\_autoscaling\_service\_linked\_role\_arn) | ARN of AWSServiceRoleForAutoScaling, which the fixture requires to exist and does not create. |
| <a name="output_iam_role_path"></a> [iam\_role\_path](#output\_iam\_role\_path) | IAM path for the fleet's role and instance profile; the permissions policy scopes IAM on it. |
| <a name="output_key_pair_name"></a> [key\_pair\_name](#output\_key\_pair\_name) | Name of the EC2 key pair the fixture registered from the throwaway public key. |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the pre-created customer managed key (volume\_key\_arn), read back from KMS. |
| <a name="output_name"></a> [name](#output\_name) | Unique fixture name, also used as the fleet name under test. |
| <a name="output_partition"></a> [partition](#output\_partition) | Partition the caller's credentials belong to. |
| <a name="output_region"></a> [region](#output\_region) | Region the fixtures were created in, resolved from the caller's credentials. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the instance security group: no inbound rules, egress 443 to the SSM endpoints only. |
| <a name="output_ssm_endpoint_ids"></a> [ssm\_endpoint\_ids](#output\_ssm\_endpoint\_ids) | IDs of the Systems Manager interface endpoints, keyed by service. |
| <a name="output_subnet_ids"></a> [subnet\_ids](#output\_subnet\_ids) | The two private subnet IDs, in different Availability Zones. |
| <a name="output_tags"></a> [tags](#output\_tags) | Identifying tags shared with the fleet under test. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | ID of the disposable VPC. |
<!-- END_TF_DOCS -->
