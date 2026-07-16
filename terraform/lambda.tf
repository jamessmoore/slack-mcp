# --- ECR ---------------------------------------------------------------

resource "aws_ecr_repository" "this" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Resource-based policy on the repo itself -- without this, Lambda's service
# principal can't pull the image at all, regardless of what the execution
# role grants. Same requirement daily-tech-brief-bedrock's main.tf hit.
resource "aws_ecr_repository_policy" "lambda_pull" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "LambdaECRImageRetrievalPolicy"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
      ]
      Condition = {
        StringEquals = {
          "aws:sourceArn" = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}"
        }
      }
    }]
  })
}

# --- IAM: Lambda execution role -----------------------------------------

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_secrets" {
  name = "${var.project_name}-secrets"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SecretsRead"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [data.aws_secretsmanager_secret.slack_bot_token.arn]
    }]
  })
}

# --- Lambda ---------------------------------------------------------------

resource "aws_lambda_function" "this" {
  function_name = var.project_name
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.this.repository_url}:latest"
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  environment {
    variables = {
      SLACK_CHANNEL    = var.slack_channel
      SLACK_SECRET_ARN = data.aws_secretsmanager_secret.slack_bot_token.arn
    }
  }

  lifecycle {
    # CI pushes new images and calls `aws lambda update-function-code`
    # directly; terraform should not fight that by reverting image_uri.
    # Same pattern as daily-tech-brief-bedrock's main.tf.
    ignore_changes = [image_uri]
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}"
  retention_in_days = 14
}
