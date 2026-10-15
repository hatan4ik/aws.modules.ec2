# Changelog

All notable changes to this module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Consumers pin the commit SHA of a release tag; see [Versioning and releases](README.md#versioning-and-releases).

## [Unreleased]

### Added

- First content of the module, not yet released and never applied against a real AWS account: the 97 contract tests in `tests/` run against a mock provider and prove the rendered configuration and the validations only.
- One private EC2 fleet per call: an `aws_launch_template` and an `aws_autoscaling_group` that runs the template's latest version, with a rolling `instance_refresh` that replaces instances when the template changes. A single instance is `min_size = max_size = 1`; there is no separate single-instance mode.
- **EC2 key pair option and a choice between Session Manager and a key pair.** `access` is `ssm` (default, the platform standard), `key_pair`, or `both`. A key pair is either an existing one (`key_pair_name`) or an OpenSSH public key the module registers as the key pair `<name>` (`key_pair_public_key`); the module never generates key material, so no private key reaches Terraform state. A key pair alone opens nothing: SSH also needs an inbound port 22 rule in one of `security_group_ids`, which the module does not create. With `access = "key_pair"` the SSM managed policy is not attached unless `iam_attach_ssm_managed_policy = true`. Outputs `access` and `key_pair_name`. See [Choosing how to get in](README.md#choosing-how-to-get-in) and [docs/DESIGN.md](docs/DESIGN.md#access-modes).
- Security defaults that are not inputs: IMDSv2 required (`http_tokens = "required"`, `instance_metadata_tags = "disabled"`), every root and additional volume the module declares encrypted, and no public IPv4 address (an explicit primary network interface with `associate_public_ip_address = false`; IPv6 follows the subnet). There is no key pair unless `access` asks for one. `ebs_optimized` is not set, so the EC2 default for the instance type applies.
- Image selection with exactly one of `ami_id` (pinned; a change rolls the fleet) and `ami_ssm_parameter_name` (resolved by EC2 at launch through `resolve:ssm:`; the parameter moving does not roll the fleet).
- Storage: `root_volume`, `ebs_volumes` keyed by a stable name, `kms_key_arn` with per-volume overrides (single-Region and multi-Region `mrk-` key ARNs), snapshot restore, and `delete_on_termination` for additional volumes. Volume `iops`, `throughput`, and size are validated per type.
- Instance profile: a role and instance profile named `<name>-instance` trusting `ec2.amazonaws.com` (`ec2.amazonaws.com.cn` in `aws-cn`), with `AmazonSSMManagedInstanceCore` attached when `access` includes `ssm`, extendable with `iam_policy_arns` (a map keyed by a static label), `iam_inline_policies` (a map keyed by policy name), `iam_permissions_boundary_arn`, and `iam_role_path`, or replaced entirely by an existing profile with `create_instance_profile = false` and `iam_instance_profile_name`. The group depends on the role's policy attachments.
- Auto Scaling: `min_size`, `max_size`, `desired_capacity` (null leaves the count to AWS), `health_check_type` and `health_check_grace_period`, `target_group_arns`, `termination_policies`, `protect_from_scale_in` (the refresh also rolls protected instances), `instance_refresh` (including `max_healthy_percentage`, at most 100 points above `min_healthy_percentage`, so a one-instance group can launch the replacement first with min 100 and max 200), `target_tracking_cpu_percent`, and `wait_for_capacity_timeout`.
- `region` and `partition` inputs (`aws`, `aws-us-gov`, `aws-cn`). `aws_partition` is the only data source and makes no API call.
- Plan-time validation of identifier shapes, ranges, and combinations; preconditions for the image inputs, the profile and role inputs, the key pair inputs against `access`, and the size range; and seven advisory checks: `volumes_use_aws_managed_key`, `single_subnet`, `elb_health_check_without_target_groups`, `no_way_into_the_instances` (a selected key pair counts as a way in), `target_tracking_cannot_scale`, `single_instance_refresh_has_downtime`, and `broad_instance_role`.
- Outputs: `autoscaling_group_name`, `autoscaling_group_arn`, `launch_template_id`, `launch_template_arn`, `launch_template_latest_version`, `image_id`, `instance_profile_name`, `instance_profile_arn`, `iam_role_arn`, `iam_role_name`, `scaling_policy_arn`, `access`, and `key_pair_name`.
- README, `docs/DESIGN.md`, `CONTRIBUTING.md`, `SECURITY.md`, examples (`minimal`, `single-instance`, `complete`, `ssh-key-pair`), an integration suite that has never been run, and the shared quality, release, and security boilerplate used by the other `aws.modules.*` repositories.

### Known limitations

- A customer managed key must allow the `AWSServiceRoleForAutoScaling` service-linked role (use, and `kms:CreateGrant` under `kms:GrantIsForAWSResource`), and the role must exist before KMS accepts a policy that names it. `aws.modules.kms` has the `autoscaling-ebs` `service_grants` preset for it; the preset is merged to its `main` (a0e0070) but not in a tagged release yet. `policy_statements` is the fallback. See [docs/DESIGN.md](docs/DESIGN.md#kms-key-policy-for-the-auto-scaling-service-linked-role).
- Encryption covers the volumes the module declares (root and `ebs_volumes`). A volume the AMI defines under another device name is not covered unless account-level EBS encryption by default is on.
- Whether AWS accepts `encrypted = true` together with an unencrypted `snapshot_id` is unverified; a refusal would fail at launch.
- `iam_role_path` and, for a registered key pair, `key_pair_public_key` changes replace resources under unchanged names while the launch template is `create_before_destroy`; both are expected to be rejected by AWS and neither has been observed. See [Failure modes](README.md#failure-modes).
- `single_instance_refresh_has_downtime` considers `max_size = 1` only; `broad_instance_role` is a text match, not a policy analyser.
- Not provided: security groups (including the port 22 rule), subnets, KMS keys, load balancers, spot or mixed instances, lifecycle hooks, warm pools, scheduled actions, step scaling, notifications, key material generation, Session Manager preferences, and a standalone `aws_instance`.

[Unreleased]: https://github.com/hatan4ik/aws.modules.ec2/commits/main
