# Dedicated deploy IAM identity for this project, scoped to exactly the
# permissions this stack needs -- replaces the shared admin-group
# `flintstone` user for local applies, and backs the GitHub OIDC role for
# CI. Same shape as daily-tech-brief-bedrock/terraform/deploy_policy.tf:
# one managed policy, attached to both a local deploy user and a CI role,
# so permissions don't drift between manual and automated deploys.
#
# The GitHub OIDC role itself (slack-mcp-github-deploy) is deliberately
# NOT created here -- same reasoning as the sibling repo: Terraform run by
# that role shouldn't be able to modify its own trust policy, so the role
# and its trust policy are bootstrapped once by hand (see README) and only
# the policy *attachment* is managed here.

resource "aws_iam_policy" "deploy" {
  name = "${var.project_name}-deploy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "EcrRepo"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:DeleteRepository",
          "ecr:DescribeRepositories",
          "ecr:PutImageScanningConfiguration",
          "ecr:SetRepositoryPolicy",
          "ecr:GetRepositoryPolicy",
          "ecr:TagResource",
          "ecr:ListTagsForResource",
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:ListImages",
          "ecr:DescribeImages",
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project_name}"
      },
      {
        Sid    = "IamRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:PutRolePolicy",
          "iam:GetRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies",
          "iam:TagRole",
          "iam:ListInstanceProfilesForRole",
        ]
        Resource = [
          aws_iam_role.lambda.arn,
          aws_iam_role.agentcore_gateway.arn,
        ]
      },
      {
        Sid    = "IamPassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          aws_iam_role.lambda.arn,
          aws_iam_role.agentcore_gateway.arn,
        ]
      },
      {
        Sid    = "Lambda"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:ListVersionsByFunction",
          "lambda:TagResource",
          "lambda:ListTags",
          "lambda:GetPolicy",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:InvokeFunction",
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}"
      },
      {
        Sid      = "LogsDescribe"
        Effect   = "Allow"
        Action   = "logs:DescribeLogGroups"
        Resource = "*"
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:TagResource",
          "logs:ListTagsForResource",
          "logs:FilterLogEvents",
          "logs:GetLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}*"
      },
      {
        # Read-only -- this project reuses daily-tech-brief-bedrock's Slack
        # bot token secret rather than owning one (see secrets.tf), so no
        # Create/Delete/Put permissions are needed here.
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetResourcePolicy",
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:daily-tech-brief-bedrock/slack-bot-token-*"
      },
      {
        Sid    = "TerraformStateBucket"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:PutBucketVersioning",
          "s3:GetBucketVersioning",
          "s3:PutEncryptionConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketPublicAccessBlock",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}/*",
        ]
      },
      {
        # API Gateway v2 resource ARNs are path-based and the api-id isn't
        # known before CreateApi runs, so this is scoped to the /apis
        # collection rather than a single api-id -- still account+region
        # scoped, not a blanket allow.
        Sid    = "ApiGatewayV2"
        Effect = "Allow"
        Action = "apigateway:*"
        Resource = [
          "arn:aws:apigateway:${var.aws_region}::/apis",
          "arn:aws:apigateway:${var.aws_region}::/apis/*",
        ]
      },
      {
        # Same reasoning as ApiGatewayV2 above -- gateway-id is generated
        # at create time, so this is scoped to the gateway resource type
        # rather than a specific not-yet-existent ID.
        Sid    = "AgentCoreGateway"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:CreateGateway",
          "bedrock-agentcore:DeleteGateway",
          "bedrock-agentcore:GetGateway",
          "bedrock-agentcore:UpdateGateway",
          "bedrock-agentcore:ListGateways",
          "bedrock-agentcore:TagResource",
          "bedrock-agentcore:UntagResource",
          "bedrock-agentcore:ListTagsForResource",
          "bedrock-agentcore:CreateGatewayTarget",
          "bedrock-agentcore:DeleteGatewayTarget",
          "bedrock-agentcore:GetGatewayTarget",
          "bedrock-agentcore:UpdateGatewayTarget",
          "bedrock-agentcore:ListGatewayTargets",
          # Gateway creation implicitly provisions a workload identity under
          # the account's shared default directory -- discovered when the
          # first CreateGateway call failed on this exact permission.
          "bedrock-agentcore:CreateWorkloadIdentity",
          "bedrock-agentcore:GetWorkloadIdentity",
          "bedrock-agentcore:UpdateWorkloadIdentity",
          "bedrock-agentcore:DeleteWorkloadIdentity",
          "bedrock-agentcore:ListWorkloadIdentities",
        ]
        Resource = "*"
      },
      {
        # Lets Terraform (run either by CI or locally by the deploy user)
        # manage this policy's own versions going forward, instead of
        # falling back to a manual `aws iam create-policy-version` every
        # time a new permission gap turns up.
        Sid    = "SelfPolicyManagement"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project_name}-deploy"
      },
      {
        # GetUser is here (not just on the deploy_self_read inline policy
        # below) because Terraform's state refresh reads back
        # aws_iam_user.deploy regardless of which identity is running it --
        # the CI role only holds this managed policy, not the deploy user's
        # own inline policy, so without this the GitHub Actions apply 403s
        # on iam:GetUser even though local applies (as the deploy user
        # itself) work fine. Confirmed via a real CI run, 2026-07-16.
        Sid    = "SelfPolicyAttachment"
        Effect = "Allow"
        Action = [
          "iam:AttachUserPolicy",
          "iam:DetachUserPolicy",
          "iam:ListAttachedUserPolicies",
          "iam:PutUserPolicy",
          "iam:GetUserPolicy",
          "iam:DeleteUserPolicy",
          "iam:ListUserPolicies",
          "iam:GetUser",
        ]
        Resource = aws_iam_user.deploy.arn
      },
      {
        Sid    = "CiRolePolicyAttachment"
        Effect = "Allow"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-github-deploy"
      },
    ]
  })
}

# Dedicated local-deploy user for this project, scoped to exactly the
# permissions in aws_iam_policy.deploy -- replaces flintstone for slack-mcp
# applies.
resource "aws_iam_user" "deploy" {
  name = "${var.project_name}-deploy"
}

resource "aws_iam_user_policy" "deploy_self_read" {
  name = "${var.project_name}-deploy-self-read"
  user = aws_iam_user.deploy.name

  # Terraform's own state refresh reads back the user it manages -- without
  # this, every plan/apply fails on iam:GetUser against itself.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SelfRead"
      Effect   = "Allow"
      Action   = "iam:GetUser"
      Resource = aws_iam_user.deploy.arn
    }]
  })
}

resource "aws_iam_user_policy_attachment" "deploy_user" {
  user       = aws_iam_user.deploy.name
  policy_arn = aws_iam_policy.deploy.arn
}

resource "aws_iam_role_policy_attachment" "github_deploy" {
  role       = "${var.project_name}-github-deploy"
  policy_arn = aws_iam_policy.deploy.arn
}
