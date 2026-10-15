# Integration suites

The suites in this directory apply the module for real in **your** AWS account
and destroy everything afterwards. They complement the contract tests in
`tests/`, which run with `mock_provider`, need no credentials, and use the AWS
documentation placeholder account `123456789012` and fake resource IDs on
purpose: they prove the module's interface and rendering, not that AWS accepts
it. These suites prove the latter.

> **Status: never run.** `aws.modules.ec2` has not been applied against a real
> AWS account, and neither has this suite. The fixture and the inspector
> validate (`terraform fmt`, `init`, `validate`), and the test file's wiring
> and assertion expressions were exercised only against mocked providers or
> not at all. The permissions policy was written from the provider's API calls
> and AWS's documented condition keys and has never been tried; expect the
> first real run to need adjustments, most likely to
> [`iam/integration-permissions-policy.json`](iam/integration-permissions-policy.json).
> Treat a green first run as the first evidence, not a formality.

Nothing here is tied to an account, region, or landing zone. Credentials and
the region come from the environment, and the volume key is a variable. Every
other prerequisite is a disposable fixture created by [`setup/`](setup/) with a
random suffix, so concurrent runs never collide. Two things are created once by
an administrator, because the integration role is deliberately unable to create
them: the Auto Scaling service-linked role and a tagged volume key (see
[Prerequisites](#prerequisites-an-administrator-creates-once)).

| Suite | What it proves | Needs | Typical time |
| --- | --- | --- | --- |
| `smoke.tftest.hcl` | Two one-instance fleets, launched from the Amazon Linux 2023 SSM parameter in two private subnets, reach InService. The first uses the default `access = "ssm"`: no key pair, IMDSv2 required, no public IPv4 address, an encrypted root volume under the customer managed key (so the key policy for the Auto Scaling service-linked role works), tags on the instance and its volume, and an Online Systems Manager registration through interface endpoints (no NAT). The second uses `access = "both"` with a key pair the fixture registered from a throwaway public key: the launch template and the instance carry that key name, the instance still has no public IPv4 address, and it still registers with Systems Manager. | credentials, region, the Auto Scaling service-linked role, a tagged volume key | about 30-40 minutes |

The second fleet **replaces** the first (the run changes the fleet name, and
both runs share the root module's state), so the suite proves what AWS reports
for each configuration. It does not exercise an in-place launch template roll,
and it does not exercise the module registering the key pair itself
(`key_pair_public_key`); that path is covered only by the mocked contract
tests in `tests/`.

## What it creates

| Where | Resource | Notes |
| --- | --- | --- |
| `setup/` | VPC (`10.98.0.0/16`), two private subnets in different zones | No internet gateway, no NAT gateway, no route out of the VPC. |
| `setup/` | Interface endpoints `ssm`, `ssmmessages`, `ec2messages` in both subnets | The only way the instance reaches AWS. This is what the cost estimate below is mostly made of. |
| `setup/` | Security group for the instances | No inbound rules; egress 443 to the endpoint security group only. |
| `setup/` | Security group for the endpoints | Inbound 443 from the instance security group only. |
| `setup/` | EC2 key pair | Registered from a throwaway ed25519 public key; the private half does not exist, so it cannot be used to log in. |
| module | Launch template, Auto Scaling group, instance role and profile (per fleet, so twice) | One `t3.micro`, `min_size = max_size = 1`, `instance_refresh` set to launch before terminate, role and profile under the `/ec2-it/` path. |
| module (via Auto Scaling) | One EC2 instance, one 30 GiB gp3 root volume, one network interface per fleet | Created and terminated by the group, not by Terraform. |
| not created | The volume key and the Auto Scaling service-linked role | Pre-created by an administrator; the suite only reads them. |
| `inspect/` | A local timer only | Reads everything else. See [`inspect/README.md`](inspect/README.md). |

Everything the suite creates carries `Disposable=true` and
`IntegrationTest=aws.modules.ec2`, and names start with `ec2-it-` followed by a
random suffix (the second fleet appends `-kp`). Provider `default_tags` do not
reach the instances, volumes, or network interfaces; only the tags the module
applies do, which is why the fleet's tags come from the fixture's `tags`
output.

## What it costs

Estimate, not a quote, from public on-demand prices at the time of writing and
not checked against the current price list: a run of 30-40 minutes costs a few
cents. Almost all of it is the three interface endpoints in two zones (six
endpoint-hours per hour, plus a small per-GB charge) and the instance
(`t3.micro`, one at a time). The 30 GiB volume is billed pro rata. The
pre-created key is billed monthly for as long as it exists, whether or not a
run is in progress. If a run is interrupted and leaves the endpoints behind,
they keep billing hourly until deleted; see
[What is left behind](#what-is-left-behind).

## Prerequisites an administrator creates once

The integration role holds neither `kms:CreateKey` nor `kms:TagResource` nor
`iam:CreateServiceLinkedRole`, so these two things exist before the first run.
The full procedure, with the Terraform for both, is in
[`setup/README.md`](setup/README.md#prerequisites-an-administrator-creates-once).

1. **The Auto Scaling service-linked role**, `AWSServiceRoleForAutoScaling`.
   AWS creates it with the first Auto Scaling group in an account, so an
   account that has never had one needs it created, for example with
   `aws iam create-service-linked-role --aws-service-name autoscaling.amazonaws.com`
   or an `aws_iam_service_linked_role` resource. KMS rejects a key policy that
   names a principal that does not exist, so it comes before the key. The suite
   does not create it: the role is account-wide and a disposable run must not
   own or delete it.
2. **One disposable volume key**, tagged `IntegrationTest=aws.modules.ec2` and
   `Disposable=true`, whose key policy allows that service-linked role to use
   the key and to create grants for AWS resources. Its ARN is the
   `volume_key_arn` variable of the suite. The earlier design had the suite
   create the key, which needed `kms:TagResource` on `*` and so would have let
   the role tag, and then manage, any key in the account; a key the role can
   use but not create, tag, re-policy, or delete removes that path.

## Run it in your account

```bash
export AWS_PROFILE=<your profile>   # or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
export AWS_REGION=<region>
export AWS_INTEGRATION_KMS_KEY_ARN=<ARN of the pre-created, tagged volume key, in that region>
make integration-smoke              # terraform init -test-directory=tests/integration && terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl -var 'volume_key_arn="..."'
```

Without `make`, pass the key quoted, as the Makefile and the workflow do; the
test file trims the quotes, because how `terraform test` parses a `-var` for a
name the root module does not declare (as an HCL expression or as a plain
string) was seen to depend on whether a run's module declares it:

```bash
terraform test -test-directory=tests/integration \
  -filter=tests/integration/smoke.tftest.hcl \
  -var 'volume_key_arn="arn:aws:kms:<region>:<account>:key/<key-id>"'
```

The credentials need the permissions in
[`iam/integration-permissions-policy.json`](iam/integration-permissions-policy.json)
(replace `<ACCOUNT_ID>`, `<REGION>`, and `<KEY_ID>`). Where the API allows it,
the policy is scoped by resource tag (`IntegrationTest=aws.modules.ec2`, which
the fixtures and the fleet carry), by name prefix, or by path:

- IAM roles and instance profiles are scoped to the `/ec2-it/` path and the
  `ec2-it-*` name prefix (the suite passes `iam_role_path = "/ec2-it/"`),
  `iam:AttachRolePolicy` is allowed only for `AmazonSSMManagedInstanceCore`, and
  `iam:PassRole` only to `ec2.amazonaws.com`. `iam:UpdateAssumeRolePolicy` and
  `iam:ListRoles` are not granted: the suite reads the service-linked role with
  `iam:GetRole` on its one ARN. IAM offers no condition key that constrains the
  trust document at `iam:CreateRole` as far as this policy's author knows
  (unverified), so a role created under the path could carry any trust; what
  bounds it is that the only policy it can be given is the SSM one. Requiring a
  permissions boundary on `iam:CreateRole` (`iam:PermissionsBoundary`) is the
  stronger control and needs a boundary policy to exist; the policy does not
  require one because that would add a third administrator prerequisite.
- `ec2:RunInstances` is split by resource type so each carries only the
  condition keys that apply to it: instances need the request tag,
  `ec2:InstanceType` in `t3.micro`, `t3.small`, `t4g.micro`,
  `ec2:MetadataHttpTokens = required`, and a hop limit of at most 1; volumes
  must be encrypted and at most 100 GiB; network interfaces must not associate
  a public IPv4 address; images must be Amazon-owned machine images (an AMI
  cannot be pinned by ID because the suite resolves a public SSM parameter);
  subnets, security groups, key pairs, and the launch template need the
  `IntegrationTest` resource tag. This bounds what the role can launch for real
  to what the module's own defaults produce.
- KMS: `DescribeKey`, `Decrypt`, `GenerateDataKeyWithoutPlaintext`,
  `ListResourceTags`, and `CreateGrant` (only for AWS resources) on one key ARN
  that must also carry the `IntegrationTest` tag. No key is created, tagged,
  re-policied, or deleted by the role.
- Not scopable: the `Describe*` calls.

Some statements are best guesses to confirm on the first run:

- `ec2:RunInstances` and the `ec2:CreateTags` for `RunInstances`: Auto
  Scaling validates the launch template with the caller's permissions when the
  group is created. The extra condition keys (`ec2:Encrypted`,
  `ec2:VolumeSize`, `ec2:AssociatePublicIpAddress`,
  `ec2:MetadataHttpPutResponseHopLimit`, `ec2:ImageType`) were chosen from the
  documented condition keys and may need adjusting if the validation call
  does not populate them the way this policy assumes.
- `ec2:ImportKeyPair`, `ec2:DeleteKeyPair`, and tagging on `key-pair/*` for the
  fixture's key pair.
- `kms:CreateGrant`, `Decrypt`, and `GenerateDataKeyWithoutPlaintext` for the
  caller: instances launched by the group use the service-linked role, so
  these may turn out to be unnecessary and can then be removed.
- `ssm:GetParameters` on the public Amazon Linux parameter path, for the
  `resolve:ssm:` AMI reference.

`terraform init -test-directory=tests/integration` also installs the `random`
and `time` providers of the fixture and the inspector and records them in your
local `.terraform.lock.hcl`. Do not commit that change: the committed lock lists
only the module's own provider (for all four platforms, from `make lock`), and
a plain `terraform init` (what CI runs) prunes the entries again.

`terraform test` runs `tests/` only by default, so these suites never run in
the credential-free quality pipeline. The two helper modules, `setup/` and
`inspect/`, are formatted, validated, linted, and doc-checked like any module
(`FIXTURE_DIRS` in the Makefile and the `terraform-quality` matrix) and are
excluded from the Checkov and Trivy scans (`.checkov.yml`, `trivy.yaml`)
because they are short-lived test infrastructure and a read-only inspector,
not deployable patterns.

## How InService is asserted

Terraform's AWS provider returns from creating the group only when
`min_size` instances are `InService` and `Healthy`, and fails the apply at
`wait_for_capacity_timeout` (10 minutes here). A passing `smoke` run is
therefore the InService proof. The `inspect` run cross-checks it from the
other side: the Auto Scaling API reports the expected sizes and launch
template, and exactly one `running` instance carries the group's
`aws:autoscaling:groupName` tag. The Systems Manager assertion waits four
minutes after that for the agent to register (again for the second fleet); if
the suite fails only that assertion, raise `ssm_registration_wait` in
`inspect/variables.tf` before suspecting the endpoints.

The key-pair fleet adds two assertions about EC2's own view: the instance's
`key_name` is the fixture's key pair, and the instance has no public IPv4
address (attaching a key pair must not change that). The suite does not try to
open an SSH session: the key pair's private half does not exist and the
instance security group has no inbound rule, which is the point.

## What is left behind

A run that finishes leaves nothing behind except what the administrator
created on purpose: the volume key and, if it was needed, the service-linked
role. Both are shared and are never deleted by the suite. The key is billed
for as long as it exists; schedule it for deletion with
`aws kms schedule-key-deletion --pending-window-in-days 7` when the suite is
retired.

If a run is killed midway (a cancelled workflow, a lost laptop), list what
remains by tag and delete it, instance group first, then the endpoints, key
pair, security groups, subnets, and VPC:

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=IntegrationTest,Values=aws.modules.ec2 Key=Disposable,Values=true \
  --query 'ResourceTagMappingList[].ResourceARN'
```

The pre-created key carries the same tags and appears in that list; do not
delete it. Auto Scaling groups appear there because the module tags the group
itself. Delete the group with `aws autoscaling delete-auto-scaling-group
--force-delete` so it terminates its instance. A killed run can leave both
fleets' roles and profiles under `/ec2-it/`; delete them by that path.

## Run it from GitHub Actions (owner lane)

The `integration` workflow (`.github/workflows/integration.yml`) is dispatch-only
and assumes a role through GitHub OIDC. It reads everything account-specific
from the protected `integration` environment of the repository, so the code
stays universal:

| Environment variable | Meaning |
| --- | --- |
| `AWS_INTEGRATION_ROLE_ARN` | Role the workflow assumes. Trust policy: [`iam/github-oidc-trust-policy.json`](iam/github-oidc-trust-policy.json) with `<OWNER>/<REPO>` set to this repository; permissions: the policy above. |
| `AWS_INTEGRATION_REGION` | Region for the disposable fixtures. The volume key must be in this Region. |
| `AWS_INTEGRATION_KMS_KEY_ARN` | ARN of the pre-created, tagged, disposable volume key (see [Prerequisites](#prerequisites-an-administrator-creates-once)). |

Dispatch with `gh workflow run integration.yml -f suite=smoke`. Protect the
environment with required reviewers so a run cannot be started from a pull
request by anyone with write access. The workflow has a 60-minute timeout and
does not cancel a run in progress, so a second dispatch queues behind the
first instead of killing it halfway through a destroy.

For this repository's owner the environment still has to be prepared: no role
or key exists yet for this repository, and the module has never been applied in
any account. Create the role through the platform's delivery IAM module with the
trust policy above and the subject
`repo:hatan4ik/aws.modules.ec2:environment:integration`.
