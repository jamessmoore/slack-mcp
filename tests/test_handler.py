
import pytest


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    monkeypatch.delenv("SLACK_BOT_TOKEN", raising=False)
    monkeypatch.delenv("SLACK_SECRET_ARN", raising=False)


def test_tool_names_are_wire_compatible_with_the_vendored_js_server():
    import handler

    names = {tool.name for tool in handler.mcp._tool_manager.list_tools()}
    assert names == {"post_to_slack", "post_file_to_slack"}


def test_require_token_raises_without_token_or_secret_arn():
    import handler

    handler._secrets_loaded = False
    with pytest.raises(handler.SlackToolError, match="SLACK_BOT_TOKEN"):
        handler._require_token()


def test_require_token_reads_from_env_directly(monkeypatch):
    import handler

    monkeypatch.setenv("SLACK_BOT_TOKEN", "xoxb-from-env")
    handler._secrets_loaded = False
    assert handler._require_token() == "xoxb-from-env"


def test_lambda_handler_builds_a_fresh_asgi_app_and_session_manager_each_call():
    """Regression test for a real Lambda bug (2026-07-16): a module-level
    Mangum(asgi_app) singleton works on cold start, then 500s on the next
    warm invocation because FastMCP's cached StreamableHTTPSessionManager
    refuses to have .run() entered twice. lambda_handler must rebuild the
    session manager per call, and must survive being called more than
    once in the same process to prove it."""
    import handler

    event = {
        "version": "2.0",
        "routeKey": "$default",
        "rawPath": "/mcp",
        "rawQueryString": "",
        "headers": {
            "content-type": "application/json",
            "accept": "application/json, text/event-stream",
        },
        "requestContext": {"http": {"method": "POST", "path": "/mcp", "sourceIp": "127.0.0.1"}},
        "body": (
            '{"jsonrpc":"2.0","id":1,"method":"initialize",'
            '"params":{"protocolVersion":"2025-06-18","capabilities":{},'
            '"clientInfo":{"name":"test","version":"0"}}}'
        ),
        "isBase64Encoded": False,
    }

    for _ in range(2):
        response = handler.lambda_handler(event, None)
        assert response["statusCode"] == 200
        assert '"serverInfo"' in response["body"]
