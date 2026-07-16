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

As of this writing: **live and deployed.** Real AWS resources exist and the
full CI/CD path (feature branch → PR → passing `test` CI → merge to `main`
→ auto-triggered `.github/workflows/deploy.yml` via GitHub OIDC →
`terraform apply` → image build/push → `aws lambda update-function-code`)
has been proven end-to-end more than once. Current shape:

- Lambda: `slack-mcp` (container image, Python 3.13)
- API Gateway HTTP API: `https://8gr00zm4d9.execute-api.us-west-2.amazonaws.com/`
- AgentCore Gateway: `arn:aws:bedrock-agentcore:us-west-2:293528978619:gateway/slack-mcp-cp2plvgahi`,
  target status `READY`
- Deploy identities: local applies run as the `slack-mcp-deploy` IAM user,
  CI runs as the `slack-mcp-github-deploy` OIDC role — see "Deploy identity
  / RBAC" below.

Don't assume this is stale, but also don't assume it's frozen — confirm
current reality with `aws bedrockagentcore-control get-gateway-target` /
`aws lambda get-function --function-name slack-mcp` etc. before making a
claim about what's live, same as always.

`daily-tech-brief-bedrock` has **not** been migrated onto this Gateway yet
— it still uses its own vendored `app/slack_mcp_server/` and
`app/mcp_client.py`. That migration (retiring the vendored server, calling
this Gateway instead via `mcp-proxy-for-aws`'s `aws_iam_streamablehttp_client`,
same client pattern as `CoreSample/agent/strands_agent.py`) is tracked as
future work, not done.

## Required workflow

Follow the same pattern as `CoreSample`/`daily-tech-brief-bedrock`: no
direct commits or pushes to `main`, feature branch + PR + passing `test`
CI check before merge. Merging to `main` auto-triggers `deploy.yml`, which
applies Terraform and pushes a new Lambda image for real — treat any
*manual* `terraform apply`, image push, or `aws lambda invoke` outside the
normal PR flow as needing an explicit go-ahead in the current request, same
as any other real-AWS-mutating action.

## Deploy identity / RBAC

Local applies and CI both run under a dedicated deploy identity scoped to
exactly this stack's permissions — never the shared `flintstone` admin
user. See `terraform/deploy_policy.tf` for the full policy and its header
comment for the reasoning; the short version:

- `aws_iam_policy.deploy` — one Terraform-managed managed policy, the
  single source of truth for what either identity can do.
- `aws_iam_user.deploy` (`slack-mcp-deploy`) — for local/manual applies,
  policy attached by Terraform.
- `slack-mcp-github-deploy` — GitHub OIDC role assumed by
  `.github/workflows/deploy.yml`. The role and its trust policy are
  **deliberately bootstrapped by hand, outside Terraform** — CI shouldn't
  be able to widen its own trust boundary — but the policy *attachment* to
  this same managed policy is Terraform-managed, so permissions can't drift
  between the two identities. (They did once — `iam:GetUser` was briefly
  only on the user's inline policy; see the `SelfPolicyAttachment`
  statement's comment.)
- The OIDC trust policy matches on `repository_id` (immutable numeric
  GitHub repo ID) ANDed with a wildcard `sub` match, not a literal
  `repo:org/repo:ref:...` string — GitHub now embeds immutable
  account/repo IDs into `sub`, so a literal match breaks silently on the
  platform's own schedule, not just on a repo rename.
- This is the standard for bootstrapping *any* new project going forward,
  not specific to slack-mcp: dedicated deploy user + scoped policy + OIDC
  role sharing that same policy.

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
  deploy_policy.tf      Dedicated deploy IAM user + managed policy, shared
                        by CI's OIDC role -- see "Deploy identity / RBAC"
  versions.tf / variables.tf / outputs.tf / terraform.tfvars.example
tests/                pytest: mocked Slack HTTP calls (slack_tools), tool
                       registration + Lambda-handler smoke tests (handler)
.github/workflows/test.yml     CI gate: ruff/mypy/pytest + terraform fmt/validate
.github/workflows/deploy.yml   Auto-triggered on push to main: terraform
                                apply, image build/push, Lambda update
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
- `server/handler.py`'s `lambda_handler` rebuilds the FastMCP ASGI app and
  wraps it in a fresh `Mangum(..., lifespan="auto")` on *every* invocation —
  don't "simplify" this back to a module-level `Mangum(asgi_app)` singleton.
  It looks redundant but isn't: FastMCP's `streamable_http_app()` memoizes a
  single `StreamableHTTPSessionManager` whose `.run()` can only be entered
  once per instance, while Mangum enters a fresh lifespan cycle on every
  call — a singleton wrapper works on cold start and then 500s on the very
  next warm invocation in the same container with
  `StreamableHTTPSessionManager .run() can only be called once per
  instance`. Confirmed against a real deployment 2026-07-16; regression test
  is `tests/test_handler.py::test_lambda_handler_builds_a_fresh_asgi_app_and_session_manager_each_call`,
  which calls `lambda_handler` twice in a row specifically to catch this.
