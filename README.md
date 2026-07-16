# slack-mcp

An AWS-native MCP server that posts to Slack (`post_to_slack`,
`post_file_to_slack`), reachable via an Amazon Bedrock AgentCore Gateway.

Today's one caller: [`daily-tech-brief-bedrock`](https://github.com/jamessmoore/daily-tech-brief-bedrock)'s
Bedrock Converse API tool-use loop, replacing its vendored, stdio-spawned
copy of a Node.js `slack-poster` MCP server. This is deliberately scoped to
AI callers that decide mid-reasoning to invoke a tool — a packaged
automation with no LLM in its trigger path (e.g. a website's deploy/signup
notifications) has no use for MCP here and should keep calling a plain
Slack incoming webhook instead. See the tool logic's origin and the scope
decision in the project's own history for the full reasoning.

## Architecture

```
AWS-internal AI caller (Bedrock Converse tool-use loop, SigV4-signed via
IAM — e.g. mcp-proxy-for-aws's aws_iam_streamablehttp_client)
        |
        v
AgentCore Gateway (authorizer_type = AWS_IAM, protocol_type = MCP)
        |
        v
API Gateway HTTP API (route auth = AWS_IAM, AWS_PROXY integration)
        |
        v
Lambda (container image, Python 3.13) -- FastMCP streamable-HTTP server
wrapped for Lambda via Mangum
        |
        v
Slack Web API (chat.postMessage, using a Bot Token from Secrets Manager)
```

No VPC Link, ALB, or ECS hop, unlike the sibling `CoreSample` repo's
`ec2-audit-mcp` (which runs on Fargate) — API Gateway integrates with a
Lambda directly, and this tool's actual workload (one outbound HTTPS POST
to Slack) doesn't need a always-on container.

## Repository layout

```
server/
  handler.py       Lambda entrypoint: FastMCP app (post_to_slack,
                    post_file_to_slack tools) wrapped for Lambda via Mangum
  slack_tools.py    Pure Slack-posting logic, ported from
                    daily-tech-brief-bedrock's vendored slack_mcp_server/index.js
  Dockerfile
  requirements.txt
terraform/
  lambda.tf           ECR repo, Lambda (container image), IAM execution role
  secrets.tf          Looks up the existing daily-tech-brief-bedrock Slack
                       bot token secret (reused, not duplicated)
  api_gateway.tf       HTTP API, AWS_PROXY integration, AWS_IAM route auth
  agentcore_gateway.tf AgentCore Gateway + target
  deploy_policy.tf     Dedicated deploy IAM user + managed policy, shared
                        by CI's OIDC role (see "Deploy identity" below)
  versions.tf / variables.tf / outputs.tf
tests/               pytest unit tests (mocked Slack API calls, no network)
.github/workflows/test.yml     CI gate: ruff/mypy/pytest + terraform fmt/validate
.github/workflows/deploy.yml   Auto-triggered on push to main
```

## Current status

**Live and deployed.** Full CI/CD path proven end-to-end: feature branch →
PR → passing `test` CI → merge to `main` → auto-triggered `deploy.yml` via
GitHub OIDC → `terraform apply` → image build/push → Lambda update.

- Lambda: `slack-mcp` (container image, Python 3.13)
- API Gateway HTTP API: `https://8gr00zm4d9.execute-api.us-west-2.amazonaws.com/`
- AgentCore Gateway: `arn:aws:bedrock-agentcore:us-west-2:293528978619:gateway/slack-mcp-cp2plvgahi`,
  target status `READY`

See `CLAUDE.md` for the required PR workflow and the deploy-identity/RBAC
setup, and the project's vault note for the architecture decisions this was
built against (validated directly against `CoreSample`'s
deployed-and-verified AgentCore Gateway pattern, not guessed from docs).

## Local verification

```bash
pip install -r server/requirements.txt -r requirements-dev.txt
ruff check server tests
mypy server
pytest

cd terraform && terraform fmt -check -recursive . && terraform init -backend=false && terraform validate
```

## One-time setup (already done for this stack; kept for reference/re-bootstrap)

1. Bootstrap the Terraform state bucket (`slack-mcp-tfstate-<account-id>`),
   same out-of-band process as `CoreSample`/`daily-tech-brief-bedrock`.
2. No token setup needed — this stack reads the existing
   `daily-tech-brief-bedrock/slack-bot-token` Secrets Manager secret rather
   than provisioning its own.
3. Bootstrap the deploy identities by hand (deliberately outside Terraform
   for the OIDC role — see `CLAUDE.md` "Deploy identity / RBAC"):
   - Create the `slack-mcp-deploy` IAM user.
   - Create the `slack-mcp-github-deploy` IAM role with a trust policy
     scoped to this repo via GitHub's OIDC provider (`repository_id`
     condition + wildcard `sub` match, not a literal repo-name string —
     see `CLAUDE.md` for why).
   - Set the `AWS_DEPLOY_ROLE_ARN` GitHub Actions repo secret to that
     role's ARN.
4. `terraform init && terraform apply` (as the `slack-mcp-deploy` user) to
   create the ECR repo and everything else, including
   `aws_iam_policy.deploy` and its attachment to both identities from step
   3, then build and push the Lambda image (`docker build -f
   server/Dockerfile -t <ecr-repo>:latest . && docker push ...`), then
   `terraform apply` again so the Lambda's `image_uri` resolves. From then
   on, every merge to `main` re-runs this automatically via
   `.github/workflows/deploy.yml`.
5. Grant the calling project's execution role `bedrock-agentcore:InvokeGateway`
   on this stack's `agentcore_gateway_arn` output.
