# AWS Config: what Security Hub CSPM evaluates. Records all supported types,
# including global IAM resources (record global types in ONE region only).
resource "aws_iam_service_linked_role" "config" {
  aws_service_name = "config.amazonaws.com"
  tags             = { Name = "AWSServiceRoleForConfig" }
}

resource "aws_config_configuration_recorder" "this" {
  name     = local.recorder_name
  role_arn = aws_iam_service_linked_role.config.arn # Config.1 expects the service-linked role

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  recording_mode {
    recording_frequency = "CONTINUOUS"
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = local.channel_name
  s3_bucket_name = aws_s3_bucket.config.bucket

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.this, aws_s3_bucket_policy.config]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.this]
}
