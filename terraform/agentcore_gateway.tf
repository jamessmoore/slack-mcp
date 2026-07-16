# AgentCore Gateway: exposes the Slack-poster Lambda as MCP-callable tools
# for AWS-internal AI callers (today: daily-tech-brief-bedrock's Bedrock
# Converse tool-use loop -- see the 2026-07-15 scope decision in the
# project's vault note; this is a single-caller Gateway, not a shared
# multi-project one). Near copy-paste of CoreSample's proven
# agentcore_gateway.tf, confirmed against the installed hashicorp/aws
# provider schema there via `terraform providers schema -json`.

resource "aws_iam_role" "agentcore_gateway" {
  name = "${var.project_name}-agentcore-gateway"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock-agentcore.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "agentcore_gateway_invoke_target" {
  name = "${var.project_name}-agentcore-gateway-invoke-target"
  role = aws_iam_role.agentcore_gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeApiGatewayTarget"
      Effect   = "Allow"
      Action   = "execute-api:Invoke"
      Resource = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.mcp.id}/*"
    }]
  })
}

resource "aws_bedrockagentcore_gateway" "this" {
  name            = var.project_name
  description     = "Exposes post_to_slack/post_file_to_slack as Bedrock-callable tools"
  role_arn        = aws_iam_role.agentcore_gateway.arn
  authorizer_type = "AWS_IAM" # caller must hold bedrock-agentcore:InvokeGateway on this gateway's ARN
  protocol_type   = "MCP"

  protocol_configuration {
    mcp {
      supported_versions = ["2025-06-18", "2025-03-26", "2025-11-25"]
    }
  }
}

resource "aws_bedrockagentcore_gateway_target" "slack_mcp" {
  gateway_identifier = aws_bedrockagentcore_gateway.this.gateway_id
  name               = "slack-mcp"
  description        = "post_to_slack / post_file_to_slack"

  target_configuration {
    mcp {
      mcp_server {
        endpoint = "${aws_apigatewayv2_stage.default.invoke_url}mcp"
      }
    }
  }

  # The Gateway signs outbound requests with its own role_arn's SigV4
  # credentials, scoped to the "execute-api" service so API Gateway
  # accepts the signature -- same shape as CoreSample's targets.
  credential_provider_configuration {
    gateway_iam_role {
      service = "execute-api"
    }
  }
}
