# Contributing

Thank you for improving `aws.modules.ec2`. This guide covers the toolchain, the integration suites, the local quality gate, how features are tested and where they belong, commit and pull request conventions, and how releases are cut.

## Development setup

The module targets Terraform `>= 1.7.0, < 2.0.0` and is developed against 1.7.5, the version the consuming platform pins. Install the toolchain:

| Tool | Purpose | Install |
| --- | --- | --- |
| [tfenv](https://github.com/tfutils/tfenv) | Pin the Terraform version | `tfenv install 1.7.5 && tfenv use 1.7.5` |
| [tflint](https://github.com/terraform-linters/tflint) | Lint with the Terraform and AWS rulesets configured in `.tflint.hcl` | `brew install tflint && tflint --init` |
| [terraform-docs](https://terraform-docs.io) v0.20.0 | Generate the inputs and outputs tables in the README. Pinned to the version bundled by the CI docs action; newer releases change table formatting and fail the drift check (`make docs` refuses other versions). | Download the v0.20.0 binary from the [releases page](https://github.com/terraform-docs/terraform-docs/releases/tag/v0.20.0) |
| [checkov](https://www.checkov.io) | Static security policy | `pip install checkov` |
| [trivy](https://trivy.dev) | Misconfiguration scanning | `brew install trivy` |
| [pre-commit](https://pre-commit.com) | Run the gate on every commit | `pip install pre-commit && pre-commit install` |

Clone, initialise without a backend, and run the gate once to confirm the setup:

```sh
terraform init -backend=false -input=false
make check
```

The module has a single root and no submodules, so `ROOT_DIRS` in the `Makefile` is `.` only. Directories under `examples/` that contain Terraform and the fixture directories `tests/integration/setup` and `tests/integration/inspect` (`FIXTURE_DIRS`) are validated and linted too, but only the root has tests. `tests/integration/inspect` is a fixture directory, not a module consumers use: a read-only helper that reads back from AWS what the integration suite built. Both fixture directories are excluded from the Checkov and Trivy scans in `.checkov.yml` and `trivy.yaml`.

## Integration suites

`tests/integration/` is for a credential-driven suite that applies the module for real in your own account and destroys everything afterwards. It is never part of `make check` or the quality pipeline. The module was applied once, on 2026-10-15, with administrator credentials (see the Live evidence section of `tests/integration/README.md`); a run under the least-privilege CI role is still outstanding. The suite does not create its own KMS key: an administrator pre-creates one disposable, tagged volume key once (see the prerequisites in `tests/integration/README.md`) and you export its ARN as `AWS_INTEGRATION_KMS_KEY_ARN`, which the `make` target requires. Run it against an account you control, never one that holds production:

```bash
export AWS_PROFILE=<profile> AWS_REGION=<region>
make integration-smoke
```

Add a suite when a feature's correctness depends on the EC2, Auto Scaling, or IAM APIs rather than on rendering (for example a new volume attribute or the first `max_healthy_percentage = 200` refresh). Keep fixtures in `tests/integration/setup` and read-backs in `tests/integration/inspect`, derive every value from the environment or the fixtures, and never reference a real account, principal, or key. A key pair needs a public key only: generate a throwaway key outside Terraform and pass the `.pub` half; the suite must never create a private key through a provider.

## The local gate

`make check` is the default target and the same gate CI runs. It stops at the first failing target and must pass before you open a pull request.

| Target | What it runs |
| --- | --- |
| `make fmt` | `terraform fmt -check -recursive -diff` from the repository root. `make fmt-fix` rewrites the files instead. |
| `make validate` | `make init` (`terraform init -backend=false`) followed by `terraform validate` in the root, every example directory that contains Terraform, and the integration fixture directories. |
| `make lint` | `tflint --init` and then `tflint` in the same directories with the root `.tflint.hcl`: documented and typed variables, documented outputs, snake_case naming, no unused declarations, pinned required versions and providers. |
| `make test` | `terraform test` in the root. The tests use `mock_provider`, so no credentials are needed. |
| `make lock` | Refresh the committed root `.terraform.lock.hcl` with hashes for linux and macOS on amd64 and arm64 after changing the provider constraint. CI runs `terraform init` before the docs drift check, so a lock file missing the Linux hash gets rewritten and fails that check. |
| `make docs` | `terraform-docs -c .terraform-docs.yml` in every directory, regenerating the tables between the `BEGIN_TF_DOCS` and `END_TF_DOCS` markers. Run it after touching any variable or output. |
| `make docs-check` | The same in `--output-check` mode: fails when a README is out of date. This is the variant `make check` and CI run. |
| `make security` | `checkov -d . --framework terraform`, and `trivy config --severity HIGH,CRITICAL` when trivy is on the PATH. A skip needs an inline `checkov:skip=` comment with a reason; the only excluded paths are the integration fixture directories, justified in `.checkov.yml` and `trivy.yaml`. |
| `make integration-smoke` | Not part of `make check`. Applies the module for real; see below. |
| `make check` | `fmt`, `validate`, `lint`, `test`, `docs-check`, `security`, in that order. |

## Test-first workflow

Every behaviour in this module is pinned by a test before it is implemented. Write the failing `run` block first, then the code, then run `make test`.

- Tests live in `tests/*.tftest.hcl`: `defaults`, `iam`, `keypair`, `scaling`, `storage`, `checks`, and `validation` (97 `run` blocks at the time of writing). Each file starts with `mock_provider "aws"` (with `mock_data "aws_partition"` defaults) and a `variables` block holding a valid baseline, which sets `kms_key_arn` and a blue-green `instance_refresh` so the advisory checks stay quiet in runs that are not about them.
- Use `command = plan`. Nothing here talks to AWS, so tests run in seconds and in CI without credentials.
- Validations are tested with `expect_failures`. Point it at the object that carries the check: `[var.subnet_ids]` for a variable validation, `[aws_launch_template.this]` or `[aws_autoscaling_group.this]` for a resource precondition, `[check.single_subnet]` for a `check` block (a failing check is a failure in `terraform test`, which is how a warning is asserted). A run with `expect_failures` passes only if exactly those objects fail; add a positive run alongside so the happy path is covered too.
- Assertions must not depend on unknown values. With a mock provider, computed attributes such as ARNs, IDs, and `latest_version` are unknown at plan time, so assert on arguments you set and on outputs derived from them.
- `||` and `&&` do not short-circuit in Terraform 1.7. Both operands are always evaluated, so `var.x == null || var.x.field > 0` fails when `x` is null. Guard with a conditional instead: `var.x == null ? true : var.x.field > 0`. This applies to validations, preconditions, and test assertions alike.
- Terraform 1.7 variable validations cannot reference other variables. A rule that compares two inputs is a `lifecycle.precondition` on the launch template or the group.
- Keep assertion `error_message` text a statement of the guaranteed behaviour. It becomes the documentation of the contract when a test fails.

## Where to add a feature

| Concern | Lives in |
| --- | --- |
| Instance and image arguments, IMDS options, key pair name, volumes, network interface, tag specifications | `aws_launch_template.this` in `main.tf`, with its inputs in `variables.tf`. Anything that should be part of the template's version history goes here. |
| Access (`access`, `key_pair_name`, `key_pair_public_key`) | `aws_key_pair.this` and the launch template's `key_name` in `main.tf`, with `uses_ssm`, `uses_key_pair`, and `key_name` in `locals.tf`. A key pair is registered from a public key only; do not add a resource that generates key material. |
| Group arguments: sizes, health checks, refresh, scaling policy | `aws_autoscaling_group.this` and `aws_autoscaling_policy.cpu` in `main.tf`. |
| The instance role, profile, and their policies | `iam.tf`. Create-only inputs must be added to `local.iam_create_inputs_set` so a supplied profile (`create_instance_profile = false`) rejects them. Existence must depend on values known at plan time: a map keyed by a static label, never a set of ARNs. |
| Cross-input validation the provider would only reject at apply time | A `lifecycle.precondition` on the resource it protects. |
| A valid but usually unintended configuration | A `check` block in `checks.tf`, with a test that fires it. |
| Derived values (image, tags, per-volume key, profile name) | `locals.tf`. |
| A new output | `outputs.tf`, with a description. |

Rules that apply everywhere: derive from inputs (`aws_partition` is the only lookup), every variable has a description, a type, and a validation where a wrong value would otherwise fail at apply time, every output has a description, defaults are the secure choice, and the security defaults (IMDSv2, encryption of declared volumes, no public IPv4) never become inputs: relaxing one is a breaking change that needs a major release and a design note. Session Manager stays the default `access`; a key pair is an opt-in that must keep working without any private key reaching state.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). The scope is the file or area the change touches.

```text
feat(launch-template): add a placement group input
fix(iam): reject a role path that does not end in a slash
docs: describe the key policy the Auto Scaling role needs
test: cover an io2 root volume with explicit iops
feat!: require ami_id instead of ami_ssm_parameter_name
```

Append `!` after the type or scope for a breaking change and add a `BREAKING CHANGE:` footer explaining what consumers must do. Breaking changes ship only in a major release with an entry in the upgrade guide.

## Pull request checklist

- [ ] `make check` passes locally.
- [ ] New behaviour has a test; changed validations have both a passing and an `expect_failures` run.
- [ ] Variables and outputs have descriptions; `make docs` regenerated the README tables.
- [ ] `CHANGELOG.md` has an entry under `## [Unreleased]` in the right category.
- [ ] Breaking changes carry `!`, a `BREAKING CHANGE:` footer, and an upgrade guide under `docs/UPGRADE-<major>.md`.
- [ ] Examples still initialise and validate; a new feature worth showing has an example.
- [ ] No new data sources, no hard-coded account, Region, or partition, no real identifiers, and no new default that weakens a security default (IMDSv2, encryption, no public IPv4, `access = "ssm"`).
- [ ] A claim in the README or `docs/DESIGN.md` that depends on AWS behaviour says whether it has been applied for real.

## Release process

Releases are cut by maintainers.

1. Move the `## [Unreleased]` entries in `CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD` heading, add its compare link, and merge that change to `main`.
2. Create a signed annotated tag on the merge commit. The signing key must be registered with GitHub so the tag shows as Verified:

   ```sh
   git tag -s vX.Y.Z -m "aws.modules.ec2 vX.Y.Z"
   git push origin vX.Y.Z
   ```

3. Dispatch the `module-release` workflow (`.github/workflows/module-release.yml`) from the tag with `release_tag = vX.Y.Z`: `gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z`. It verifies that the signed tag points at the checked-out revision, then formatting, validation, tests, and generated docs, and publishes the GitHub release. Never dispatch it from `main`: a maintenance release of an older line is cut from that line's commit.
4. Announce the release with the commit SHA. Consumers pin that SHA, not the tag:

   ```hcl
   source = "git::https://github.com/hatan4ik/aws.modules.ec2.git?ref=<commit-sha>" # vX.Y.Z
   ```

Tags are never moved or deleted once published. A bad release is followed by a new patch release. `v0.1.0` is the first release and is explicitly pre-1.0. `v1.0.0` additionally waits for a real apply of the module (see Integration suites).
