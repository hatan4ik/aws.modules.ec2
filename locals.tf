locals {
  # How operators get in. ssm is the platform default; a key pair is opt-in.
  uses_ssm      = contains(["ssm", "both"], var.access)
  uses_key_pair = contains(["key_pair", "both"], var.access)

  # The module creates the role and instance profile unless the caller brings
  # one. create_instance_profile is its own input (not "profile name is null")
  # so the count stays known when the profile name is computed in the same
  # apply.
  create_instance_profile = var.create_instance_profile

  # Read whenever the caller does not supply it, even with a brought profile:
  # locals are always evaluated, and indexing an empty data source would fail
  # the plan.
  partition = var.partition != null ? var.partition : data.aws_partition.current[0].partition

  # AmazonSSMManagedInstanceCore follows the access choice unless the caller
  # decides explicitly.
  attach_ssm_policy = var.iam_attach_ssm_managed_policy != null ? var.iam_attach_ssm_managed_policy : local.uses_ssm

  # The EC2 service principal differs in the China partition. An unknown
  # partition falls back to the commercial principal.
  ec2_service_principal = lookup({
    aws        = "ec2.amazonaws.com"
    aws-us-gov = "ec2.amazonaws.com"
    aws-cn     = "ec2.amazonaws.com.cn"
  }, local.partition, "ec2.amazonaws.com")

  instance_profile_name = local.create_instance_profile ? aws_iam_instance_profile.this[0].name : var.iam_instance_profile_name

  # A key pair is registered from a public key; an existing one is referenced
  # by name. The module never generates key material, so no private key can
  # reach state. Counts depend only on nullness of the public key.
  create_key_pair = local.uses_key_pair && var.key_pair_public_key != null
  key_name        = local.create_key_pair ? aws_key_pair.this[0].key_name : (local.uses_key_pair ? var.key_pair_name : null)

  # Caller tags win; the module only fills in Name when it is absent.
  tags = merge({ Name = var.name }, var.tags)

  # Per-volume key, else the module-level key, else null (AWS managed aws/ebs).
  root_kms_key_arn = var.root_volume.kms_key_arn != null ? var.root_volume.kms_key_arn : var.kms_key_arn
  volume_kms_key_arns = {
    for name, volume in var.ebs_volumes : name => volume.kms_key_arn != null ? volume.kms_key_arn : var.kms_key_arn
  }

  # EC2 resolves the resolve:ssm: prefix when an instance launches. When both
  # inputs are null this is null and the launch template precondition reports
  # it, instead of an interpolation error hiding the real message.
  image_id = var.ami_id != null ? var.ami_id : (var.ami_ssm_parameter_name != null ? "resolve:ssm:${var.ami_ssm_parameter_name}" : null)

  # Inputs that only have meaning when the module creates the role.
  iam_create_inputs_set = (
    var.iam_attach_ssm_managed_policy != null ||
    length(var.iam_policy_arns) > 0 ||
    length(var.iam_inline_policies) > 0 ||
    var.iam_permissions_boundary_arn != null ||
    var.iam_role_path != "/"
  )
}
