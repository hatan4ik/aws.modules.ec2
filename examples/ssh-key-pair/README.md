# Instance with an SSH key pair

One private EC2 instance that Session Manager and SSH can both reach:
`access = "both"` with a key pair the module registers from a **public** key you
supply. Session Manager stays the platform standard and the default of the
module; this example shows the opt-in for workloads that need SSH too.

> **Not applied against a real account.** This example has been checked with
> `terraform fmt`, `terraform init -backend=false` and `terraform validate`.
> This example itself has not been applied. The module's key pair registration
> and rotation were observed live on 2026-10-15 (see
> [Live evidence](../../tests/integration/README.md#live-evidence-2026-10-15)), but no SSH or Session Manager session has
> been opened through it. The port 22 composition below was written from another
> module's usage of `aws.modules.security-group` and has not been validated.

## Choosing how operators get in

`access` takes one of three values:

| `access` | Key pair | `AmazonSSMManagedInstanceCore` | Needs an inbound port 22 rule |
|----------|----------|--------------------------------|-------------------------------|
| `ssm` (default) | None | Attached | No |
| `key_pair` | Yes | **Not** attached, unless `iam_attach_ssm_managed_policy = true` | Yes, for SSH to work |
| `both` | Yes | Attached | Yes, for SSH to work |

With a key pair selected, set exactly one of:

- `key_pair_public_key`: an OpenSSH public key (`ssh-ed25519` or `ssh-rsa`).
  The module registers it as an EC2 key pair named after the fleet with a
  generated suffix (see the `key_pair_name` output). This example uses it.
- `key_pair_name`: the name of a key pair that already exists in the Region.

Both must be null when `access = "ssm"`; the module rejects them otherwise.

The module never generates key material, so no private key can reach Terraform
state. The public key is stored in state, which is fine: it is public.

## What it creates

- One EC2 key pair named `ssh-key-pair-example`, registered from
  `var.ssh_public_key`. Key pair names are unique per Region in an account, so
  this fails if one with that name already exists.
- One launch template and one Auto Scaling group with `min_size = max_size = 1`,
  launching with that key pair. `instance_refresh` is `min 100 / max 200`, so a
  launch template change is configured to launch the replacement before
  terminating the old instance (the documented way to avoid an outage window
  with one instance; observed once on 2026-10-15 in a similar group).
- One IAM role and instance profile named `ssh-key-pair-example-instance`, with
  `AmazonSSMManagedInstanceCore` attached (because `access = "both"`).

The module always runs the instance with IMDSv2 required and no public IPv4
address (IPv6 follows the subnet). Every volume the module declares is
encrypted. It creates no security group and no inbound rule.

## What it needs from you

| Input | What it must be |
|-------|-----------------|
| `ssh_public_key` | The contents of a `.pub` file. See below. |
| `subnet_ids` | Existing private subnets, two or more zones. One subnet raises the advisory `single_subnet` check. |
| `security_group_ids` | Existing groups. For SSH, one must allow inbound TCP 22 from your bastion or VPN range, **never `0.0.0.0/0`**. They must also allow outbound HTTPS for Session Manager. |
| A route for Session Manager | A NAT gateway or the `ssm`, `ssmmessages`, and `ec2messages` VPC endpoints. |
| A network path for SSH | A bastion host, VPN, or Direct Connect that can reach the private subnet on port 22. The instance has no public IPv4 address. |
| `kms_key_arn` (optional) | The full ARN of a customer managed key. Without it the volumes use the AWS managed `aws/ebs` key and `volumes_use_aws_managed_key` warns. The key policy needs the Auto Scaling service-linked role; the `autoscaling-ebs` preset of `aws.modules.kms` (v2.1.0 or later) is shown in [`complete`](../complete). |
| `region` | Any region where the instance type and AMI parameter exist. The platform rule that limits it to US regions is recorded in `docs/ARCHITECTURE.md` of `devops-aws-infra`. |

## Generate a key pair

Create the key on the operator's own machine, protect the private half with a
passphrase, and pass only the `.pub` file to Terraform:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/ssh-key-pair-example -C "ops@example.com"
```

> **Never commit, paste, or pass the private key** (`~/.ssh/ssh-key-pair-example`,
> the file without `.pub`). Only `ssh-key-pair-example.pub` goes into Terraform.
> The module and this example reject a value that is not a one-line public key.
> Add the private key's path to `.gitignore` if you generate it inside a repository.

```sh
terraform apply \
  -var "ssh_public_key=$(cat ~/.ssh/ssh-key-pair-example.pub)" \
  -var 'subnet_ids=["subnet-0123456789abcdef0","subnet-0123456789abcdef1"]' \
  -var 'security_group_ids=["sg-0123456789abcdef0"]'
```

A key pair is one long-lived shared credential: anyone holding the private key
can log in as the instance's default user (`ec2-user` on Amazon Linux). EC2
installs the key when an instance first boots, so rotating a key means
replacing instances; this example does not automate that. Prefer Session Manager
for day-to-day access, which is authenticated by IAM per user.

## The port 22 rule

A key pair alone opens nothing. SSH also needs an inbound rule on port 22 in one
of the groups in `security_group_ids`, and this module does not create it.
`main.tf` carries a commented composition with `aws.modules.security-group` that
admits port 22 from a single `ssh_allowed_cidr` variable (your bastion or VPN
range, not `0.0.0.0/0`) and appends the group to `security_group_ids`. It is
commented out so the example needs only existing groups. Keep the rule narrow:
a key pair that is reachable from the internet is a brute-force target.

With `access = "both"` you can also tunnel SSH through Session Manager
(`AWS-StartSSHSession`) instead of opening port 22 at all, using the same key
pair. That path was not exercised here.

## Session Manager caveats

- **Anyone with `ssm:StartSession` on an instance gets a shell as `ssm-user`,
  which is a sudoer.** Grant it narrowly, by tag or instance, not broadly.
- **Sessions are not logged unless Session Manager preferences are configured**
  (CloudWatch Logs or S3, in the account and Region). **Turn session logging on**
  before relying on Session Manager as the audited path; this example does not
  configure it. Direct SSH sessions are not captured by Session Manager logging.
- **Tags are visible metadata, not secrets.** Anyone who can describe the
  instances sees them.
- **Provider `default_tags` do not reach instances, volumes, or network
  interfaces.** Only the module's `tags` do.

## Run

```hcl
# terraform.tfvars (the public key goes on the command line or in a TF_VAR_ variable)
subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
security_group_ids = ["sg-0123456789abcdef0"]
```

```sh
export TF_VAR_ssh_public_key="$(cat ~/.ssh/ssh-key-pair-example.pub)"
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
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | Full ARN of a customer managed KMS key for the volumes (single-Region or multi-Region mrk-). Null uses the AWS managed aws/ebs key and raises an advisory check. The key policy must allow the Auto Scaling service-linked role; see examples/complete. | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region the fleet and the key pair are created in. A key pair belongs to one Region. | `string` | `"us-east-1"` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Existing security group IDs attached to every instance. For SSH, one of them must allow inbound TCP 22 from your bastion or VPN range (never 0.0.0.0/0); the module creates no rule. They must also allow the outbound HTTPS Session Manager needs. | `list(string)` | n/a | yes |
| <a name="input_ssh_public_key"></a> [ssh\_public\_key](#input\_ssh\_public\_key) | OpenSSH PUBLIC key (the contents of the .pub file, one line starting with ssh-ed25519 or ssh-rsa). Never pass or commit the private half. | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Existing private subnet IDs. Use two or more in different Availability Zones; one raises the advisory single\_subnet check. | `list(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access"></a> [access](#output\_access) | How operators reach the instances: ssm, key\_pair, or both. |
| <a name="output_autoscaling_group_name"></a> [autoscaling\_group\_name](#output\_autoscaling\_group\_name) | Name of the Auto Scaling group. |
| <a name="output_iam_role_arn"></a> [iam\_role\_arn](#output\_iam\_role\_arn) | ARN of the instance role the module created. |
| <a name="output_instance_profile_name"></a> [instance\_profile\_name](#output\_instance\_profile\_name) | Name of the instance profile the module created. |
| <a name="output_key_pair_name"></a> [key\_pair\_name](#output\_key\_pair\_name) | Name of the key pair the instances launch with: the one the module registered from the public key. |
<!-- END_TF_DOCS -->
