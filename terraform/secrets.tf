# Reuses the Slack bot token daily-tech-brief-bedrock already has in
# Secrets Manager, rather than provisioning a second copy of the same
# credential that could drift out of sync. This Lambda only needs read
# access, granted in lambda.tf.
data "aws_secretsmanager_secret" "slack_bot_token" {
  name = var.slack_secret_name
}
