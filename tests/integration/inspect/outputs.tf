output "group" {
  description = "The Auto Scaling group as the Auto Scaling API reports it: sizes, health check type, launch template, and the subnets it spans."
  value = {
    min_size            = data.aws_autoscaling_group.this.min_size
    max_size            = data.aws_autoscaling_group.this.max_size
    desired_capacity    = data.aws_autoscaling_group.this.desired_capacity
    health_check_type   = data.aws_autoscaling_group.this.health_check_type
    launch_template_id  = one(data.aws_autoscaling_group.this.launch_template).id
    vpc_zone_identifier = sort(split(",", data.aws_autoscaling_group.this.vpc_zone_identifier))
  }
}

output "instance_ids" {
  description = "IDs of the running instances in the group."
  value       = sort(data.aws_instances.fleet.ids)
}

output "instances" {
  description = "Per instance, keyed by instance ID: what EC2 reports for the metadata options, network placement, instance profile, key pair, tags, and the encryption and tags of the root volume."
  value = {
    for id, instance in data.aws_instance.this : id => {
      instance_state              = instance.instance_state
      ebs_optimized               = instance.ebs_optimized
      http_endpoint               = one(instance.metadata_options).http_endpoint
      http_tokens                 = one(instance.metadata_options).http_tokens
      http_put_response_hop_limit = one(instance.metadata_options).http_put_response_hop_limit
      instance_metadata_tags      = one(instance.metadata_options).instance_metadata_tags
      public_ip                   = instance.public_ip
      associate_public_ip_address = instance.associate_public_ip_address
      key_name                    = instance.key_name
      iam_instance_profile        = instance.iam_instance_profile
      subnet_id                   = instance.subnet_id
      vpc_security_group_ids      = sort(tolist(instance.vpc_security_group_ids))
      tags                        = instance.tags
      extra_ebs_volume_count      = length(instance.ebs_block_device)
      root_device_name            = one(instance.root_block_device).device_name
      root_encrypted              = one(instance.root_block_device).encrypted
      root_kms_key_id             = one(instance.root_block_device).kms_key_id
      root_volume_type            = one(instance.root_block_device).volume_type
      root_volume_size            = one(instance.root_block_device).volume_size
      root_delete_on_termination  = one(instance.root_block_device).delete_on_termination
      root_volume_tags            = data.aws_ebs_volume.root[id].tags
      root_volume_encrypted       = data.aws_ebs_volume.root[id].encrypted
      root_volume_kms_key_id      = data.aws_ebs_volume.root[id].kms_key_id
    }
  }
}

output "ssm_online_instance_ids" {
  description = "IDs of the group's instances that Systems Manager reports as Online after ssm_registration_wait: the proof that Session Manager can reach them."
  value       = tolist(flatten([for online in data.aws_ssm_instances.online : sort(tolist(online.ids))]))
}
