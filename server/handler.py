"""Lambda entrypoint: a FastMCP streamable-HTTP server exposing
`post_to_slack`/`post_file_to_slack`, wrapped for Lambda via Mangum.

AgentCore Gateway calls MCP targets over HTTP, not stdio -- same reasoning
as CoreSample's ec2-audit-mcp/main.py. Here the HTTP hop is API Gateway ->
Lambda directly (AWS_PROXY integration, no VPC Link/ALB/ECS -- see
terraform/api_gateway.tf) rather than API Gateway -> VPC Link -> ALB ->
Fargate, since a plain Lambda doesn't need that extra hop.
"""

from __future__ import annotations

import logging
import os

import boto3
from mangum import Mangum
from mcp.server.fastmcp import FastMCP
from slack_tools import SlackToolError, post_file_to_slack, post_to_slack
from starlette.requests import Request
from starlette.responses import PlainTextResponse

logger = logging.getLogger(__name__)
# logging.basicConfig() no-ops under the Lambda Python runtime -- it
# pre-attaches its own handler to the root logger before this module loads,
# and that root logger defaults to WARNING. setLevel on the named logger
# directly, not basicConfig on root. (Same gotcha CoreSample's Security Hub
# exporter hit -- see its CLAUDE.md "Current status".)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

SLACK_SECRET_ARN = os.environ.get("SLACK_SECRET_ARN")
DEFAULT_CHANNEL = os.environ.get("SLACK_CHANNEL", "#daily-brief")

_secrets_loaded = False


def _load_secrets() -> None:
    """Pull the Slack bot token from Secrets Manager into the process
    environment once per cold start. Subsequent warm invocations skip the
    Secrets Manager round trip entirely."""
    global _secrets_loaded
    if _secrets_loaded:
        return
    if SLACK_SECRET_ARN and "SLACK_BOT_TOKEN" not in os.environ:
        client = boto3.client("secretsmanager")
        os.environ["SLACK_BOT_TOKEN"] = client.get_secret_value(SecretId=SLACK_SECRET_ARN)[
            "SecretString"
        ]
    _secrets_loaded = True


def _require_token() -> str:
    _load_secrets()
    token = os.environ.get("SLACK_BOT_TOKEN")
    if not token:
        raise SlackToolError("SLACK_BOT_TOKEN not set in environment")
    return token


mcp = FastMCP(
    "slack-mcp",
    host="0.0.0.0",
    port=int(os.environ.get("PORT", "8000")),
    streamable_http_path="/mcp",
)


@mcp.custom_route("/health", methods=["GET"])
async def health(_request: Request) -> PlainTextResponse:
    return PlainTextResponse("ok")


# Explicit name= on both tools -- this is a wire-compatible drop-in for the
# tool names daily-tech-brief-bedrock's SYSTEM_PROMPT and future callers
# already expect (post_to_slack/post_file_to_slack), independent of the
# Python function names below.
@mcp.tool(name="post_to_slack")
def _post_to_slack(message: str, channel: str = DEFAULT_CHANNEL) -> str:
    """Post a plain text message to a Slack channel.

    Args:
        message: The message text to post.
        channel: Slack channel name (e.g. "#daily-brief").
    """
    try:
        return post_to_slack(_require_token(), message, channel)
    except SlackToolError as exc:
        logger.error("post_to_slack failed: %s", exc)
        raise


@mcp.tool(name="post_file_to_slack")
def _post_file_to_slack(
    filepath: str, channel: str = DEFAULT_CHANNEL, header: str | None = None
) -> str:
    """Read a markdown file and post its contents to a Slack channel,
    chunked to fit Slack's per-message character limit.

    Args:
        filepath: Absolute path to the markdown file to post.
        channel: Slack channel name (e.g. "#daily-brief").
        header: Optional header line prepended to the post.
    """
    try:
        return post_file_to_slack(_require_token(), filepath, channel, header)
    except SlackToolError as exc:
        logger.error("post_file_to_slack failed: %s", exc)
        raise

asgi_app = mcp.streamable_http_app()
lambda_handler = Mangum(asgi_app, lifespan="off")
