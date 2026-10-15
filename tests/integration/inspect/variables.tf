variable "autoscaling_group_name" {
  description = "Name of the Auto Scaling group under test (the module's autoscaling_group_name output). Its instances are found through the aws:autoscaling:groupName tag EC2 adds to every instance a group launches."
  type        = string
}

variable "ssm_registration_wait" {
  description = "How long to wait before asking Systems Manager which instances are registered. The agent registers a few minutes after boot, and Auto Scaling reports InService without waiting for it."
  type        = string
  default     = "240s"
}
