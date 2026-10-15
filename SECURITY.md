# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| Unreleased `main` | The only line. No release has been tagged yet, and `main` is not yet supported for production use. |

The first release will be `v1.0.0`; this table is updated when it is cut. `aws.modules.ec2` has never been applied against a real AWS account, so treat every finding in this policy as a contribution to that first release, not as a regression.

## Reporting a vulnerability

Use GitHub private vulnerability reporting for this repository: <https://github.com/hatan4ik/aws.modules.ec2/security/advisories/new>. Do not open a public issue, pull request, or discussion for a security problem.

Include the commit SHA, the inputs that reproduce the problem (redact account IDs, ARNs, and key material), the resulting plan, and the impact you see.

## What counts

- A weakened default: IMDSv2 no longer required or the metadata options relaxed, volumes the module declares rendered unencrypted, a public IPv4 address associated, or a volume encrypted with a different key than the one selected.
- A key pair registered, or `key_name` set, when `access` says otherwise (`access = "ssm"` must set no key pair), a private key accepted by `key_pair_public_key` or surfaced in state or outputs, or the SSM managed policy attached or withheld contrary to `access` and `iam_attach_ssm_managed_policy`.
- A validation bypass: an input the module claims to reject at plan time (a wrong access combination, a malformed key, a refresh band AWS rejects, an invalid ARN) that reaches the provider.
- IAM over-permission in the created role: a statement or policy the caller did not declare, a trust policy that any principal other than the EC2 service can assume, a policy attached that `iam_policy_arns` and `iam_inline_policies` do not list, or a permissions boundary that is dropped.
- A caller-supplied instance profile, key pair, security group, or KMS key that the module modifies (with `create_instance_profile = false` the module must create and change no IAM resource).
- A dependency problem in the release pipeline that could publish unverified code.

Out of scope here: configuration you wrote (an `Action: "*"` inline policy, a port 22 rule open to `0.0.0.0/0`, an AMI from an owner you did not vet, secrets in `user_data`), the `broad_instance_role` advisory check being a text match rather than a policy analyser, and findings in AWS services themselves, which go to AWS.

## Response

We acknowledge a report within 5 business days and keep you informed while we confirm, fix, and release. A fix ships with a `CHANGELOG.md` entry that credits the reporter unless they ask otherwise. Please give us a reasonable window before disclosing publicly.

## Security design

What the module does, each enforced by a validation, a precondition, a `check` block, or a `terraform test` case rather than by documentation alone:

- IMDSv2 only (`http_tokens = "required"`, metadata tags off), with a hop limit of 1 unless raised to 2, and no input that relaxes the token requirement.
- Encryption (`encrypted = true`) on the root volume and every `ebs_volumes` entry the module declares, with the key you choose or the AWS managed `aws/ebs` key and an advisory check. Full KMS key ARNs (including multi-Region `mrk-` keys) are required so they can be validated at plan time.
- No public IPv4: an explicit primary network interface with `associate_public_ip_address = false`.
- No key pair by default. `access` is `ssm` unless you opt in to `key_pair` or `both`; a key pair is an existing one or a registered public key, the module never generates key material, and a private key is rejected by validation, so none reaches state.
- Session Manager as the default way in. The created role carries `AmazonSSMManagedInstanceCore` only when `access` includes `ssm` or you ask for it.
- A role that trusts the EC2 service only (`ec2.amazonaws.com`, `ec2.amazonaws.com.cn` in `aws-cn`), no policy beyond what you declare, an optional permissions boundary, and an advisory `broad_instance_role` check for administrator-class policies and an inline `Action: "*"`.
- A caller-supplied profile is never modified, and role inputs are rejected when one is supplied.

What it does not do, and what you own:

- It cannot see the key policy, the security group rules (a key pair alone opens nothing; port 22 needs a rule you create, from a bastion or VPN range), or whether the AMI exists, who owns it, or what other volumes it defines. Volumes the AMI defines under another device name are not covered by the module's encryption unless account-level EBS encryption by default is on.
- Anyone with `ssm:StartSession` gets a shell as `ssm-user`, a sudoer, and sessions are not logged unless Session Manager preferences are configured; with a key pair the private key is a shared, long-lived credential.
- `user_data` is stored in state and plan output, kept in old launch template versions, and readable by local processes through the metadata service. Tags are readable metadata. With `metadata_hop_limit = 2` every container on the instance receives the role's credentials.
- Provider `default_tags` do not reach instances, volumes, or network interfaces; only the module's `tags` do.

Nothing here has been applied to a real AWS account. The full description is in the [Security model](README.md#security-model) section of the README, and the reasoning in [docs/DESIGN.md](docs/DESIGN.md).
