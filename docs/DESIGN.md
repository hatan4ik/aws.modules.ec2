# Design: aws.modules.ec2 v1

Status: released as v0.1.1 (pre-1.0; the interface may change in a minor version until v1.0.0). Applied live once, in a sandbox account on 2026-10-15 (see the Live evidence section of tests/integration/README.md); whatever that run did not exercise is checked only by `terraform test` against a mock provider (97 `run` blocks) or by reading the code. Where a statement depends on how AWS behaves, it says whether that comes from documentation, from inference, or from the live run.

## Purpose

`aws.modules.ec2` provisions **one** private EC2 fleet per module call: a launch template, an Auto Scaling group that runs the template's latest version, an optional CPU target tracking policy, an optional EC2 key pair registered from a public key, and, unless the caller brings one, the instance role and instance profile. A single instance is the same group with `min_size = max_size = 1`; there is no second code path for "just one box", so a failed instance is always replaced.

The module is secure by default (IMDSv2 required, every volume it declares encrypted, no public IPv4, no key pair), explicit by declaration (image, sizes, volumes, access, role policies are typed inputs), and composable: it creates no security groups, subnets, or KMS keys and takes their identifiers as inputs.

The module deliberately does **not** create security groups, subnets, KMS keys, load balancers or target groups, or anything that is attached to the fleet rather than part of launching it. Those have separate lifecycles and owners. The module consumes their identifiers and exposes the fleet's identifiers for them to reference.

## Principles

| Principle | How the module applies it |
| --- | --- |
| Single responsibility | One launch template, one group, one optional policy, one optional key pair, one role and profile. Network and encryption primitives belong to `aws.modules.vpc`, `aws.modules.security-group`, and `aws.modules.kms`. |
| Secure defaults that are not inputs | IMDSv2 (`http_tokens`), encryption of declared volumes, and no public IPv4 have no variable. A caller cannot weaken them; only a new major version of the module could. The default of the one security-relevant choice that is an input, `access`, is `ssm`. |
| Open/closed | New capacity or access is added by declaring data: a volume in `ebs_volumes`, a policy in `iam_policy_arns`, a target group in `target_group_arns`, a key pair through `access`. |
| Fail at plan time where the value is known | Identifier shapes, ranges, and combinations the provider or AWS would reject at apply or launch are rejected at plan time with a message that names the input to change. The rules are listed under [Validation ownership](#validation-ownership); anything that needs an AWS API call is out of reach. |
| Advisory over silent | A valid but usually unintended configuration raises a `check` that warns on every plan and apply, and never blocks. |
| No lookups | The only data source is `aws_partition`, which reads provider configuration and makes no API call. The module reads no AMI, subnet, or key. |
| Existence from static values | Counts and `for_each` depend on values that are known at plan time (`create_instance_profile`, map keys, nullness of `key_pair_public_key`), never on a value that may be computed in the same apply. |

## Architecture

```text
root
├── data.aws_partition.current[0]            main.tf, count = 1 only when partition is null
├── aws_key_pair.this[0]                     main.tf, only when access includes a key pair and key_pair_public_key is set
├── aws_launch_template.this                 main.tf
├── aws_autoscaling_group.this               main.tf
├── aws_autoscaling_policy.cpu[0]            main.tf, only when target_tracking_cpu_percent is set
├── aws_iam_role.this[0]                     iam.tf, only when create_instance_profile is true
├── aws_iam_role_policy_attachment.ssm[0]    iam.tf, when access includes ssm or iam_attach_ssm_managed_policy = true
├── aws_iam_role_policy_attachment.additional["<label>"]
├── aws_iam_role_policy.inline["<policy name>"]
└── aws_iam_instance_profile.this[0]         iam.tf
```

Data flows one way. `locals.tf` resolves the access mode (`uses_ssm`, `uses_key_pair`), the key pair name (the registered one, or `key_pair_name`, or null), whether the SSM managed policy is attached, the EC2 service principal for the partition, the image (`ami_id`, or `resolve:ssm:<parameter>`), the effective KMS key per volume (volume key, else `kms_key_arn`, else null for the AWS managed key), the tag map, and the instance profile name (created or supplied). `main.tf` renders the launch template from those and points the group at `aws_launch_template.this.latest_version`. The group `depends_on` the role's policy attachments so they exist before the first instance boots.

Everything that defines an instance is on the launch template and nothing is set on the group's instances directly. In particular, the instance, volume, and network interface tags are `tag_specifications` on the template, because that is the only place that reaches volumes created from `block_device_mappings`. The group's own tags have `propagate_at_launch = false`. Provider `default_tags` do not reach the instances, volumes, or network interfaces the group launches; only the module's `tags` do.

### Root interface (summary)

| Group | Inputs |
| --- | --- |
| Identity | `name`, `tags`, `region`, `partition` |
| Placement and network | `subnet_ids`, `security_group_ids` |
| Image and instance | `ami_id`, `ami_ssm_parameter_name`, `instance_type`, `user_data`, `detailed_monitoring`, `metadata_hop_limit` |
| Storage | `kms_key_arn`, `root_volume`, `ebs_volumes` |
| Access | `access`, `key_pair_name`, `key_pair_public_key` |
| Instance profile | `create_instance_profile`, `iam_instance_profile_name`, `iam_attach_ssm_managed_policy`, `iam_policy_arns`, `iam_inline_policies`, `iam_permissions_boundary_arn`, `iam_role_path` |
| Auto Scaling group | `min_size`, `max_size`, `desired_capacity`, `health_check_type`, `health_check_grace_period`, `target_group_arns`, `termination_policies`, `protect_from_scale_in`, `instance_refresh`, `target_tracking_cpu_percent`, `wait_for_capacity_timeout` |

Outputs: `autoscaling_group_name`, `autoscaling_group_arn`, `launch_template_id`, `launch_template_arn`, `launch_template_latest_version`, `image_id`, `instance_profile_name`, `instance_profile_arn`, `iam_role_arn`, `iam_role_name`, `scaling_policy_arn`, `access`, `key_pair_name`. `instance_profile_arn`, `iam_role_arn`, and `iam_role_name` are null when a profile is supplied; `key_pair_name` is null when `access = "ssm"`.

## Validation ownership

Each rule lives in the one place that can express it.

| Layer | Owns | Why there |
| --- | --- | --- |
| `variable` validation | The shape of one input: ID patterns (`subnet-`, `sg-`, `ami-`, `snap-`), ARN patterns (including `mrk-` KMS keys), ranges, enums (`access`, `partition`), volume type with its `iops`, `throughput`, and size rules (gp3 iops 3000-16000, io1 100-64000, io2 100-256000 and required for both, st1 and sc1 at least 125 GiB), device names, unique device names, the OpenSSH public key shape (a private key is rejected), and `instance_refresh` bounds including `max_healthy_percentage - min_healthy_percentage <= 100`. | Fails earliest, with the variable's name in the message. Terraform 1.7 cannot reference another variable inside a variable validation, so a rule may only compare fields of the same input. |
| `lifecycle.precondition` on `aws_launch_template.this` | Cross-input rules: exactly one of `ami_id` and `ami_ssm_parameter_name`; `iam_instance_profile_name` set exactly when `create_instance_profile` is false; no role inputs when it is false; `key_pair_name` and `key_pair_public_key` unset unless `access` includes a key pair; exactly one of them set when it does. | These compare two or more variables, which a variable validation cannot do in 1.7. |
| `lifecycle.precondition` on `aws_autoscaling_group.this` | `min_size <= max_size` and `desired_capacity` within the range. | Same reason. |
| `check` blocks (`checks.tf`) | Valid but usually unintended configurations: `volumes_use_aws_managed_key`, `single_subnet`, `elb_health_check_without_target_groups`, `no_way_into_the_instances`, `target_tracking_cannot_scale`, `single_instance_refresh_has_downtime`, `broad_instance_role`. | A `check` warns without blocking, so an intentional single-subnet fleet is allowed. |
| AWS | Whether the AMI exists, suits the instance type's architecture, and defines volumes under other device names, whether a security group belongs to the subnets' VPC and carries a port 22 rule, whether a key policy grants the service-linked role, whether SSM can reach the instance, whether the instance type supports what the template asks for. | The module makes no API calls, so none of this is checkable at plan time. |

`||` and `&&` do not short-circuit in Terraform 1.7. Conditions that read a field of a nullable value use a conditional (`x == null ? true : x.field > 0`).

`single_instance_refresh_has_downtime` looks at `max_size` only: it fires for `max_size = 1` without min 100 and max 200, and does not fire for a larger group that happens to be running one instance. `broad_instance_role` is a text match, not a policy analyser: it matches `AdministratorAccess`, `PowerUserAccess`, and `IAMFullAccess` policy ARNs and an inline `"Action": "*"` (or a list that starts with `"*"`).

## Security defaults

These have no input, except where stated. They are the contract, and weakening one is a breaking change.

- **IMDSv2 required.** `metadata_options` sets `http_endpoint = "enabled"`, `http_tokens = "required"`, `instance_metadata_tags = "disabled"`. A v1-capable instance hands its role credentials to anything that can make a plain GET, which is the SSRF case. `metadata_hop_limit` is the only tunable (1 or 2). 2 exists for containers that run on the instance, and it gives every container on the instance the role's credentials, so the role should then be minimal.
- **Encryption of declared volumes.** `encrypted = true` on the root volume and on every `ebs_volumes` entry, with no switch. This covers the volumes the module declares. A volume the AMI defines under a different device name is not covered unless account-level EBS encryption by default is on, and a wrong `root_volume.device_name` makes the module add a second volume instead of configuring the AMI's root volume. `root_volume.device_name` is the AMI's root device: `/dev/xvda` for Amazon Linux and Bottlerocket, `/dev/sda1` for Ubuntu and Debian. For a volume restored from `snapshot_id` the module requests `encrypted = true` and the key; whether AWS accepts that for an unencrypted snapshot is unverified, and a refusal would surface at launch (it fails closed).
- **No public IPv4.** The primary network interface is declared with `device_index = 0` and `associate_public_ip_address = false`, so a subnet with `map_public_ip_on_launch = true` cannot give the instances an address. IPv6 follows the subnet: a subnet that auto-assigns IPv6 addresses gives the instances a routable IPv6 address, and reachability then depends on the security group.
- **EBS optimization is the EC2 default.** The module does not set `ebs_optimized`, so the EC2 default for the instance type applies and the template does not ask for something a type may not support.
- **No key pair by default.** No `key_name` is set unless `access` is `key_pair` or `both`. The module never generates key material.
- **Trust.** The created role trusts `ec2.amazonaws.com` for `sts:AssumeRole` (`ec2.amazonaws.com.cn` in `aws-cn`), nothing else. The module attaches no wildcard policy; `iam_inline_policies` and `iam_policy_arns` are the caller's responsibility, `iam_permissions_boundary_arn` is available to bound them, and the `broad_instance_role` check warns about the obvious cases.
- **A supplied profile is never modified.** With `create_instance_profile = false` the module creates and changes no IAM resource, and rejects every role input.
- **User data is not a secret store.** It is stored in Terraform state and plan output, kept in every older launch template version, readable through the EC2 API, and readable by any local process on the instance through the metadata service. The input description says so.
- **Customer managed key advisory.** Without `kms_key_arn` the volumes use the AWS managed `aws/ebs` key, which cannot be shared across accounts or revoked, and the `volumes_use_aws_managed_key` check warns.

### Access

How an operator gets a shell is the `access` input: `ssm` (default), `key_pair`, or `both`. See [Access modes](#access-modes) for the decision. What the module does about the consequences:

- **Session Manager.** The SSM managed policy follows `access` (`iam_attach_ssm_managed_policy = null`): attached for `ssm` and `both`, not for `key_pair`, and the caller can override either way. Anyone allowed `ssm:StartSession` on an instance gets a shell as `ssm-user`, which is a sudoer, so that permission is the real access control and belongs in the caller's IAM. Sessions are not logged unless Session Manager preferences are configured, which this module does not do. Caller tags are visible metadata, not secrets.
- **Key pair.** `key_name` is set on the launch template: the existing key pair named by `key_pair_name`, or the key pair the module registers from `key_pair_public_key`, named `<name>-` plus a generated suffix (`key_name_prefix`, so that rotating the key can create the replacement before the old key pair is removed). A key pair alone opens nothing: SSH also needs an inbound port 22 rule in one of `security_group_ids`, which the module does not create (`aws.modules.security-group`, from a bastion or VPN range, never `0.0.0.0/0`).
- **Image provenance.** The AMI owner, and for `ami_ssm_parameter_name` whoever can write a private parameter, decide what boots. That is part of the trust boundary; the module does not look the image up, so it cannot check it. Restrict it with an SCP or the EC2 Allowed AMIs setting.

### KMS key policy for the Auto Scaling service-linked role

The launch template names the key, but the Auto Scaling service launches the instances. It does so as the service-linked role `AWSServiceRoleForAutoScaling` (`arn:<partition>:iam::<account>:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling`), so that role, not the instance role and not the Terraform caller, must be allowed to use the key.

Statements the key policy needs:

| Statement | Principal | Actions | Condition |
| --- | --- | --- | --- |
| Use | the service-linked role | `kms:Encrypt`, `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`, `kms:DescribeKey` | none |
| Grants | the service-linked role | `kms:CreateGrant` | `Bool` `kms:GrantIsForAWSResource` = `true` |

`aws.modules.kms` has a preset for exactly this: `service_grants = { AutoScalingEbs = { service = "autoscaling-ebs" } }` renders the two statements as `AutoScalingEbs` and `AutoScalingEbsAttachPersistentResources`. The preset first shipped in `aws.modules.kms` v2.1.0 (commit 66f78e1c4ef81a3fbf36af8133f4a632a2e80f27); KMS accepted it in the live run of 2026-10-15, after the service-linked role had been created. For an `aws.modules.kms` release before v2.1.0, `policy_statements` is the fallback and the README shows both statements. The module cannot verify the key policy, so a missing statement surfaces as failed scaling activities after apply. This is the most likely failure of a first apply and is the reason the requirement is repeated in the `kms_key_arn` input description. The service-linked role itself is a prerequisite: it did not exist in the account used for the live run and had to be created first.

The service-linked role must already exist before KMS accepts a policy that names it. AWS creates it when the account's first Auto Scaling group is created; an account that has never had one needs `aws_iam_service_linked_role` for `autoscaling.amazonaws.com` first, or the key apply fails. The module requires full KMS key ARNs (single-Region or multi-Region `mrk-`) so they can be validated at plan time; aliases and bare key IDs are not accepted for that reason.

## Lifecycle rules

- **Launch template.** `name_prefix = "<name>-"` with `create_before_destroy = true`, so a forced replacement never leaves the group without a template. `update_default_version = true`, and the group references `latest_version`: an edit creates a new template version in place, the group's `launch_template.version` changes, and `instance_refresh` rolls the fleet. `create_before_destroy` propagates to what the template depends on, which matters for the role, the profile, and the registered key pair (below).
- **Auto Scaling group.** `name` is the group's name and identity. Changing it replaces the group and terminates its instances; the old group must be destroyed first because the name is unique. The group has no `create_before_destroy`. It `depends_on` the role's policy attachments and inline policies.
- **Instance refresh.** Enabled by default as a `Rolling` refresh with `min_healthy_percentage = 90`. `max_healthy_percentage` (100-200) lets the group launch before it terminates, and Auto Scaling rejects a band wider than 100 points, so `max_healthy_percentage - min_healthy_percentage <= 100`: the documented zero-downtime single-instance setting is min 100 and max 200, and a max above 190 with the default min is rejected at plan time. Without it a one-instance group has an outage window while the replacement boots. With `protect_from_scale_in = true` the module sets `scale_in_protected_instances = "Refresh"`, otherwise the refresh would skip protected instances and leave them on the old template. `enabled = false` omits the `instance_refresh` block entirely, and a new template version then applies only to instances launched afterwards.
- **Capacity.** `desired_capacity = null` leaves the count to AWS: the group starts at `min_size` and a scaling policy or an operator owns it afterwards, so scaling is not drift. Setting it makes Terraform reset the count on every apply.
- **Image.** `ami_id` is immutable, so changing it is a reviewed template change that rolls the fleet. `ami_ssm_parameter_name` is resolved by EC2 at launch (`resolve:ssm:`); the parameter moving does not change the template, produces no plan diff, and does not roll the fleet. The `image_id` output reports which form is in use.
- **Role and profile.** Named `<name>-instance`; IAM is global, so the name is unique per account, not per Region. `name` is 1-48 characters so every derived name fits its AWS limit. Both are skipped when `create_instance_profile` is false, and the role-only inputs are then rejected rather than ignored. `iam_role_path` is part of both resources' identity: changing it replaces them under the same names, and because of the propagated `create_before_destroy` the replacement is created first, which IAM rejects. The path is therefore fixed for the life of the fleet name (rename or recreate). That ordering is inferred from Terraform's behavior and has not been observed.
- **Key pair.** The registered key pair is named with `key_name_prefix = "<name>-"` and lives in the instances' Region (`region` applies), so AWS adds a unique suffix and the `key_pair_name` output carries the real name. Changing `key_pair_public_key` replaces it; because the launch template is `create_before_destroy` and Terraform extends that to its dependencies, the replacement is created before the old key pair is deleted, which a fixed name would have made a duplicate-name error. Observed on 2026-10-15: the rotation created the new key pair, updated the launch template, deleted the old one, and rolled the fleet.
- **Tags.** `merge({ Name = var.name }, var.tags)`: caller tags win, and the module fills in `Name` only when it is absent. Tags reach the launch template, the group (without propagation), the role, the profile, the key pair, and, through `tag_specifications`, instances, volumes, and network interfaces. A tag change is a template change and therefore rolls the fleet. Provider `default_tags` apply to the resources Terraform creates but not to the instances, volumes, and network interfaces the group launches.
- **Waiting.** `wait_for_capacity_timeout` defaults to `10m`; Terraform waits for `min_size` instances to pass health checks after create or update. `0` disables waiting.

## Testing strategy

- **Contract tests** live in `tests/*.tftest.hcl` and use `mock_provider "aws"` with `aws_partition` given a `mock_data` default. They need no credentials and run in seconds. There are 97 `run` blocks in seven files: `defaults` (10: security and fleet defaults, tags, user data, image forms, refresh defaults), `iam` (8: created role, partition and trust principal, extra policies, existing profile, rejected role inputs), `keypair` (11: access modes, registered and existing key pairs, rejected combinations, private and unsupported keys), `scaling` (10: load balancer, target tracking, single-instance refresh, refresh disabled, protected instances, the 100-point band), `storage` (5: module key, per-volume override, no key, volume settings), `checks` (13: a quiet baseline and at least one run per advisory check), and `validation` (40: every variable validation and its boundary).
- Everything uses `command = plan`. Validations are tested with `expect_failures`, pointed at the object that carries the check: `[var.name]`, `[aws_launch_template.this]`, `[check.single_subnet]`. A check is a failure in `terraform test`, so `expect_failures` is how a warning is asserted.
- Baseline variables in `defaults` and `checks` set `kms_key_arn` and a blue-green `instance_refresh` so the advisory checks stay quiet in runs that are not about them.
- With a mock provider computed attributes (ARNs, IDs, `latest_version`) are unknown at plan time, so assertions use arguments the module sets and outputs derived from them.
- **Integration evidence is partial.** The module was applied live once (2026-10-15, administrator credentials, a sandbox account). Proven: the key policy statements the preset renders are sufficient for an Auto Scaling group to launch encrypted instances; `resolve:ssm:` is accepted together with the explicit network interface; a refresh with `min 100 / max 200` launches the replacement before terminating; key pair registration and rotation work; instances come up with IMDSv2 required, no public IPv4 and volumes encrypted under the customer managed key. Not proven: `encrypted = true` together with a `snapshot_id`, `protect_from_scale_in` with refresh, IPv6, arm64, a partition other than `aws`, an SSH session through a real port 22 rule, and the least-privilege CI role (the run used administrator credentials).

## Compatibility

- Terraform `>= 1.7.0, < 2.0.0`; AWS provider `>= 6.35.0, < 7.0.0`. The committed lock file resolves provider 6.69.0; tests were run with Terraform 1.7.5.
- The module is Region-agnostic. `region` is optional and pins the key pair, launch template, group, and policy at resource level; IAM is global and ignores it. The platform's US-only rule is recorded in `docs/ARCHITECTURE.md` of `devops-aws-infra` (not in ADR 0002, which is about active-active planes) and is enforced by the consumer, not by this module.
- `partition` accepts `aws`, `aws-us-gov`, and `aws-cn`. It builds the SSM managed policy ARN and picks the EC2 service principal in the trust policy (`ec2.amazonaws.com.cn` in `aws-cn`). The isolated partitions are not supported. Tests assert the default and `aws-cn`; none has been applied.
- `kms_key_arn` and the per-volume overrides accept single-Region and multi-Region (`mrk-`) key ARNs.
- Scope, deliberately excluded: security groups (including the port 22 rule), subnets, KMS keys, load balancers and target groups, spot or mixed instances, lifecycle hooks, warm pools, scheduled actions, step scaling, notifications, key material generation, Session Manager preferences, and a standalone `aws_instance`.

## Access modes

The decision recorded here replaces an earlier draft that rejected key pairs and SSH outright.

**Decision.** `access` takes `ssm` (default), `key_pair`, or `both`. Session Manager through the instance role stays the default and the platform standard. A key pair is an explicit opt-in: either an existing key pair by name (`key_pair_name`) or an OpenSSH public key the module registers as the key pair `<name>` (`key_pair_public_key`). Selecting `key_pair` alone does not attach the SSM managed policy (`iam_attach_ssm_managed_policy` can still say so), and a key pair alone opens nothing, because the inbound port 22 rule lives in a security group the caller passes in.

**Why a registered public key, and never a generated one.** The alternatives are `tls_private_key` (or any provider that generates a key) feeding `aws_key_pair`, or `aws_key_pair` without a public key. Both put a private key in Terraform state, in plan output on the machines that run the plan, and in whatever backend stores the state, where it is as widely readable as the state. A module that generates the key makes the fleet's credential a by-product of a plan. Taking only the public half keeps the private key where the operator created it, outside the module and outside state; the public key is not secret, so storing it in state is harmless. The module also rejects a private key at plan time rather than quietly passing it on.

**Why it is an opt-in departure.** The security review in ADR 0007 of the platform cites "no node SSH" among its reasons for choosing ECS Fargate for the application plane (Fargate has no node to log in to; this module serves the workloads that need EC2), and that reasoning stands: a key pair is a long-lived shared credential, SSH needs an ingress rule and a network path, and neither is attributed to a person the way an IAM-authenticated Session Manager session can be. This module departs from that only as an explicit opt-in. The default is `ssm`; a caller who sets `access` has made a visible, reviewable choice, the SSM policy is not attached for `key_pair` unless asked, the `no_way_into_the_instances` check accepts a selected key pair as a way in, and the platform default does not change. Workloads that need SSH (a vendor image, a legacy agent, a debugging path where the SSM agent is the thing that is broken) can have it without a fork of the module.

**What the module deliberately still does not do for SSH.** It creates no port 22 rule, no bastion, and no private key; it does not log SSH sessions. Those belong to `aws.modules.security-group` and to the operator.

## Alternatives considered and rejected

**An `aws_instance` fleet with `for_each`.** Rejected. A bare instance has no replacement on failure: a terminated or impaired instance stays down until Terraform runs again. It also has no rolling update, no health-based replacement, no load balancer registration, and scaling is a code change. A group of one gives replacement and refresh for free, so the single-instance case is `min_size = max_size = 1` rather than a second resource family with its own drift and its own tests.

**An Auto Scaling group without a launch template.** Rejected. Launch configurations are deprecated by AWS, and their block device mappings have no per-volume KMS key and the group has no tag specification that reaches volumes. A launch template is also what makes a configuration change a versioned, refreshable event rather than an in-place edit of a group.

**Creating the security group inside the module.** Rejected. A security group is shared with load balancers, databases, and other fleets, and has its own owner and lifecycle; creating it here ties its rules to the fleet's lifecycle and name. The module takes `security_group_ids` and `aws.modules.security-group` owns the rules, so ingress and egress are reviewed in one place. The same reasoning applies to the port 22 rule: the module will not open it.

**Generating the key pair in Terraform.** Rejected; see [Access modes](#access-modes). A private key in state is the cost, and the alternative (the operator keeps the private key and gives the module the public one) has no disadvantage that matters here.

**A boolean `enable_ssh` instead of `access`.** Rejected. The interesting question is not only "is there a key pair" but "does Session Manager still work", and a boolean cannot say `key_pair` without the SSM policy. A three-value enum states both axes in one validated input and gives the SSM policy a default that follows it.

**A mixed instances policy.** Rejected for v1. It brings an allocation strategy, spot behaviour, and several instance types, and the right values depend on the workload; a fleet that needs it is a different module with different failure modes. The single-type path keeps `instance_type` and the AMI architecture a one-to-one pair, so the architecture mismatch the module cannot check at plan time has one place to look. If a workload needs spot or mixed types, it should be added as an optional input in a minor version, not by loosening `instance_type`.
