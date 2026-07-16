variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Name prefix used for the ECR repo, Lambda function, Gateway, and related resources."
  type        = string
  default     = "slack-mcp"
}

variable "slack_channel" {
  description = "Default Slack channel posted to when a caller doesn't specify one."
  type        = string
  default     = "#daily-brief"
}

variable "slack_secret_name" {
  description = "Name of the existing Secrets Manager secret holding the Slack bot token (chat:write scope). Reused from daily-tech-brief-bedrock rather than duplicated."
  type        = string
  default     = "daily-tech-brief-bedrock/slack-bot-token"
}

variable "lambda_memory_size" {
  description = "Lambda memory in MB. A single HTTP POST to Slack needs minimal headroom."
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 15
}
