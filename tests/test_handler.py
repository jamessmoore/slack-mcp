
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


def test_lambda_handler_is_a_mangum_asgi_wrapper():
    import handler
    from mangum import Mangum

    assert isinstance(handler.lambda_handler, Mangum)
