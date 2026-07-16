# HTTPS + SigV4-verifying front door for the Lambda, sitting between it and
# the AgentCore Gateway target (agentcore_gateway.tf). Unlike CoreSample's
# ec2-audit-mcp (ECS Fargate behind a VPC Link + internal ALB), a Lambda
# integrates with API Gateway directly (AWS_PROXY) -- no VPC Link, no ALB,
# no ECS hop needed.

resource "aws_apigatewayv2_api" "mcp" {
  name          = "${var.project_name}-mcp"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.mcp.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.this.invoke_arn
  payload_format_version = "2.0"
}

# A single catch-all route rather than one route per FastMCP path
# (/mcp, /health) -- the Lambda's own ASGI app (ecosystem: Starlette,
# see server/handler.py) does the real path routing. AWS_IAM here is what
# makes this endpoint SigV4-verifiable -- required for the AgentCore
# Gateway target's IAM/SigV4 outbound auth to work (same requirement as
# CoreSample's api_gateway.tf routes).
resource "aws_apigatewayv2_route" "default" {
  api_id             = aws_apigatewayv2_api.mcp.id
  route_key          = "$default"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "AWS_IAM"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.mcp.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.mcp.execution_arn}/*/*"
}
