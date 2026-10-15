# The instance role. Session Manager is the default way in, so the role exists
# mainly to let SSM reach the instances; with access = key_pair it carries no
# SSM policy unless the caller asks. Skipped entirely when
# create_instance_profile is false.

resource "aws_iam_role" "this" {
  count = local.create_instance_profile ? 1 : 0

  name                 = "${var.name}-instance"
  path                 = var.iam_role_path
  permissions_boundary = var.iam_permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EC2AssumeRole"
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = local.ec2_service_principal }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count = local.create_instance_profile && local.attach_ssm_policy ? 1 : 0

  role       = aws_iam_role.this[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Keyed by the caller's static labels: existence never depends on a value that
# may be computed in the same apply.
resource "aws_iam_role_policy_attachment" "additional" {
  for_each = local.create_instance_profile ? var.iam_policy_arns : {}

  role       = aws_iam_role.this[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  for_each = local.create_instance_profile ? var.iam_inline_policies : {}

  name   = each.key
  role   = aws_iam_role.this[0].id
  policy = each.value
}

resource "aws_iam_instance_profile" "this" {
  count = local.create_instance_profile ? 1 : 0

  name = "${var.name}-instance"
  path = var.iam_role_path
  role = aws_iam_role.this[0].name
  tags = local.tags
}
