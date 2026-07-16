# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

An AWS-native MCP server exposing `post_to_slack`/`post_file_to_slack`,
reachable via an Amazon Bedrock AgentCore Gateway (`AWS_IAM` authorizer) so
AWS-internal AI callers can post to Slack mid-reasoning without each project
vendoring its own copy of the Slack integration. Backend is a Lambda
(container image, Python 3.13) running a FastMCP streamable-HTTP server
wrapped for Lambda via Mangum, fronted directly by an API Gateway HTTP API
(`AWS_PROXY` integration — no VPC Link/ALB/ECS hop). See `README.md` for
the full architecture diagram and rationale.

This is a re-hosting of tool logic that already exists and is already
proven in the sibling repo `daily-tech-brief-bedrock`
(`app/slack_mcp_server/index.js`, a vendored Node.js MCP server called over
stdio) — `server/slack_tools.py` is a faithful Python port of that logic,
not a rewrite, kept wire-compatible (same tool names, same chunking
constant) so migrating callers is a drop-in swap. The AgentCore
Gateway/Lambda/API Gateway pattern itself is copied from `CoreSample`,
which deployed and verified the identical shape end-to-end in production
before being torn down (see `CoreSample/CLAUDE.md`).

**Deliberately scoped to one AI caller for now** (`daily-tech-brief-bedrock`),
not a shared multi-project server. A separate project, `webtechhq-site`,
also posts to Slack but via a raw incoming webhook with no LLM in the
trigger path — that's a packaged automation, not a tool-use decision, so it
has no reason to go through MCP and is explicitly out of scope here (see
the vault's `PROJECTS/slack-mcp.md` 2026-07-15 scope decision).

## Current status — read before assuming anything is stale

As of this writing: **scaffolded, not deployed.** Server code and Terraform
exist and pass local verification (pytest, ruff, mypy, `terraform fmt`/
`validate` with `-backend=false`). No GitHub repo has been created, no ECR
image has been built or pushed, no `terraform apply` has run against real
AWS, and the Terraform S3 state bucket (`slack-mcp-tfstate-<account-id>`)
has not been bootstrapped. Don't assume any AWS resource in `terraform/`
exists yet — check `aws bedrockagentcore-control list-gateways` /
`aws lambda get-function --function-name slack-mcp` etc. to confirm current
reality before making a claim about what's live.

`daily-tech-brief-bedrock` has **not** been migrated onto this Gateway yet
— it still uses its own vendored `app/slack_mcp_server/` and
`app/mcp_client.py`. That migration (retiring the vendored server, calling
this Gateway instead via `mcp-proxy-for-aws`'s `aws_iam_streamablehttp_client`,
same client pattern as `CoreSample/agent/strands_agent.py`) is tracked as
future work, not done.

## Required workflow — once a GitHub repo exists

Follow the same pattern as `CoreSample`/`daily-tech-brief-bedrock`: no
direct commits or pushes to `main`, feature branch + PR + passing `test`
CI check before merge. Treat any *manual* `terraform apply`, image push, or
`aws lambda invoke` outside the normal PR flow as needing an explicit
go-ahead in the current request — this is a new repo and a first-ever
deploy would create real AWS resources (ECR repo, Lambda, API Gateway,
AgentCore Gateway, Secrets Manager entry, IAM roles), not something to do
opportunistically.

## Local verification before opening/updating a PR

Mirrors `.github/workflows/test.yml`. None of it touches AWS or Slack —
config/logic-correctness only.

```bash
pip install -r server/requirements.txt -r requirements-dev.txt
ruff check server tests
mypy server
pytest

cd terraform && terraform fmt -check -recursive . && terraform init -backend=false && terraform validate
```

## Project structure

```
server/
  handler.py        Lambda entrypoint: FastMCP app + Mangum wrapper, Secrets
                     Manager cold-start caching (same pattern as
                     daily-tech-brief-bedrock/app/handler.py's _load_secrets)
  slack_tools.py     Pure post_to_slack/post_file_to_slack logic, ported
                      from the vendored Node.js server -- no MCP/Lambda
                      framing, unit-testable on its own
  Dockerfile          Single-stage (public.ecr.aws/lambda/python:3.13) --
                      no Node stage needed, unlike daily-tech-brief-bedrock's
                      dual-runtime image
  requirements.txt
terraform/
  lambda.tf            ECR repo + policy, Lambda execution IAM role, Lambda
                        function (package_type = Image)
  secrets.tf           Looks up the existing daily-tech-brief-bedrock Slack
                        bot token secret (reused, not duplicated)
  api_gateway.tf        HTTP API, AWS_PROXY Lambda integration, $default
                        route with authorization_type = AWS_IAM
  agentcore_gateway.tf  AgentCore Gateway (AWS_IAM authorizer) + target
                        pointing at the API Gateway invoke URL
  versions.tf / variables.tf / outputs.tf / terraform.tfvars.example
tests/                pytest: mocked Slack HTTP calls (slack_tools), tool
                       registration + Mangum wiring smoke tests (handler)
.github/workflows/test.yml   CI gate: ruff/mypy/pytest + terraform fmt/validate
```

## Secrets

- `.env`, `terraform/*.tfvars`, `terraform/*.auto.tfvars` are gitignored —
  never commit them, print their contents, or paste real values into
  commits, PRs, or commit messages.
- `.env.example` and `terraform/terraform.tfvars.example` document required
  variables with placeholders only.
- The real Slack bot token lives in AWS Secrets Manager / GitHub Actions
  secrets, not in this repo.

## Commit messages

Short, imperative, capitalized summary line. No conventional-commit
prefixes (`feat:`, `fix:`, etc.) — matches `CoreSample`/`daily-tech-brief-bedrock`.

## Notes

- `server/slack_tools.py` is a deliberate faithful port of
  `daily-tech-brief-bedrock/app/slack_mcp_server/index.js`. Don't diverge
  its logic (chunking size, message shape, error handling) without a
  reason — if it needs a fix, consider whether the fix belongs in the
  original vendored server too, until that server is retired.
- Lambda Python runtime gotcha (already hit once in `CoreSample`'s Security
  Hub exporter): `logging.basicConfig()` no-ops under Lambda's runtime,
  which pre-attaches its own root handler at `WARNING`. `server/handler.py`
  calls `logger.setLevel()` on the named logger directly instead — don't
  "simplify" this back to `basicConfig()`.
- When in doubt about an AgentCore/Bedrock/API Gateway Terraform resource's
  exact schema, check the installed provider's real schema
  (`terraform providers schema -json`) rather than guessing from docs —
  several `CoreSample` mistakes were caught this way and this repo's
  Terraform was written by copying that repo's already-verified shapes.
