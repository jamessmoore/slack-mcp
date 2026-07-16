"""Slack posting logic, ported from daily-tech-brief-bedrock's vendored
Node.js `slack-poster` MCP server (`app/slack_mcp_server/index.js`). Same
two behaviors, same chunking constant -- kept as a faithful port, not a
rewrite, so this stays a drop-in replacement over the wire.

Pure functions only (no MCP/Lambda framing here) so this module is testable
without spinning up FastMCP or mocking Lambda -- see tests/test_slack_tools.py.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request

SLACK_POST_MESSAGE_URL = "https://slack.com/api/chat.postMessage"

# Slack has a 4000 char limit per message -- chunk if needed. Matches the
# vendored JS server's chunk size exactly.
CHUNK_SIZE = 3900


class SlackToolError(RuntimeError):
    """Raised for any failure a caller should see as an MCP tool error."""


def _post_message(token: str, channel: str, text: str) -> None:
    body = json.dumps({"channel": channel, "text": text}).encode("utf-8")
    request = urllib.request.Request(
        SLACK_POST_MESSAGE_URL,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise SlackToolError(f"Request to Slack API failed: {exc}") from exc

    if not payload.get("ok"):
        raise SlackToolError(f"Slack API error: {payload.get('error')}")


def post_to_slack(token: str, message: str, channel: str = "#daily-brief") -> str:
    """Post a plain text message. Returns a human-readable confirmation."""
    _post_message(token, channel, message)
    return f"Posted to {channel} successfully."


def post_file_to_slack(
    token: str,
    filepath: str,
    channel: str = "#daily-brief",
    header: str | None = None,
) -> str:
    """Read a markdown file and post its contents to Slack, chunked at
    CHUNK_SIZE chars per message. Returns a human-readable confirmation."""
    try:
        with open(filepath, encoding="utf-8") as f:
            content = f.read()
    except OSError as exc:
        raise SlackToolError(f"Could not read file at {filepath}: {exc}") from exc

    message = f"{header}\n\n{content}" if header else content

    chunks = [message[i : i + CHUNK_SIZE] for i in range(0, len(message), CHUNK_SIZE)]
    for chunk in chunks:
        _post_message(token, channel, chunk)

    return f"File posted to {channel} ({len(chunks)} message(s))."
