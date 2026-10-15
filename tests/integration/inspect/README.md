# Integration inspector

Read-only helper for `smoke.tftest.hcl`. Given the name of the Auto Scaling
group under test, it reads back from the EC2, Auto Scaling, and Systems
Manager APIs what AWS actually built: the group's sizes and launch template,
the running instances found through the `aws:autoscaling:groupName` tag, each
instance's metadata options, network placement, instance profile, key pair,
tags, and root volume (encryption, key, tags), and which instances Systems
Manager reports `Online`.

The module's own outputs are what Terraform believes; this module is what AWS
reports. It creates nothing in AWS. Its one resource is a local timer
(`time_sleep`) that waits `ssm_registration_wait` (default 240s) before the
Systems Manager lookup, because Auto Scaling reports an instance `InService`
before its agent has registered.

It is not a deployable pattern and is not part of the module's interface.
Inputs and outputs are documented in `variables.tf` and `outputs.tf`.

The timer is re-created, and so waits again, whenever
`autoscaling_group_name` changes: the smoke suite inspects a second fleet
(`access = "both"`) after the first fleet has been replaced.

Like `setup/`, it is validated and linted by `make validate`, `make lint`, and
`make docs-check` and excluded from the Checkov and Trivy scans (`.checkov.yml`,
`trivy.yaml`). It has never run against a real account.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.12.0, < 1.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |
| <a name="provider_time"></a> [time](#provider\_time) | >= 0.12.0, < 1.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [time_sleep.ssm_registration](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [aws_autoscaling_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/autoscaling_group) | data source |
| [aws_ebs_volume.root](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ebs_volume) | data source |
| [aws_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/instance) | data source |
| [aws_instances.fleet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/instances) | data source |
| [aws_ssm_instances.online](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_instances) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_autoscaling_group_name"></a> [autoscaling\_group\_name](#input\_autoscaling\_group\_name) | Name of the Auto Scaling group under test (the module's autoscaling\_group\_name output). Its instances are found through the aws:autoscaling:groupName tag EC2 adds to every instance a group launches. | `string` | n/a | yes |
| <a name="input_ssm_registration_wait"></a> [ssm\_registration\_wait](#input\_ssm\_registration\_wait) | How long to wait before asking Systems Manager which instances are registered. The agent registers a few minutes after boot, and Auto Scaling reports InService without waiting for it. | `string` | `"240s"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_group"></a> [group](#output\_group) | The Auto Scaling group as the Auto Scaling API reports it: sizes, health check type, launch template, and the subnets it spans. |
| <a name="output_instance_ids"></a> [instance\_ids](#output\_instance\_ids) | IDs of the running instances in the group. |
| <a name="output_instances"></a> [instances](#output\_instances) | Per instance, keyed by instance ID: what EC2 reports for the metadata options, network placement, instance profile, key pair, tags, and the encryption and tags of the root volume. |
| <a name="output_ssm_online_instance_ids"></a> [ssm\_online\_instance\_ids](#output\_ssm\_online\_instance\_ids) | IDs of the group's instances that Systems Manager reports as Online after ssm\_registration\_wait: the proof that Session Manager can reach them. |
<!-- END_TF_DOCS -->
