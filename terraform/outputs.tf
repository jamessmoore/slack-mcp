output "ecr_repository_url" {
  value = aws_ecr_repository.this.repository_url
}

output "lambda_function_name" {
  value = aws_lambda_function.this.function_name
}

output "api_gateway_invoke_url" {
  value = aws_apigatewayv2_stage.default.invoke_url
}

output "agentcore_gateway_url" {
  value = aws_bedrockagentcore_gateway.this.gateway_url
}

output "agentcore_gateway_arn" {
  description = "Grant a caller's execution role bedrock-agentcore:InvokeGateway on this ARN to let it call post_to_slack/post_file_to_slack."
  value       = aws_bedrockagentcore_gateway.this.gateway_arn
}
