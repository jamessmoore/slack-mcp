import json
from unittest.mock import MagicMock, patch

import pytest
from slack_tools import CHUNK_SIZE, SlackToolError, post_file_to_slack, post_to_slack


def _ok_response(payload: dict) -> MagicMock:
    response = MagicMock()
    response.read.return_value = json.dumps(payload).encode("utf-8")
    response.__enter__.return_value = response
    return response


@patch("slack_tools.urllib.request.urlopen")
def test_post_to_slack_success(mock_urlopen):
    mock_urlopen.return_value = _ok_response({"ok": True})

    result = post_to_slack("xoxb-token", "hello world", "#general")

    assert result == "Posted to #general successfully."
    request = mock_urlopen.call_args[0][0]
    assert request.full_url == "https://slack.com/api/chat.postMessage"
    assert request.get_header("Authorization") == "Bearer xoxb-token"
    body = json.loads(request.data)
    assert body == {"channel": "#general", "text": "hello world"}


@patch("slack_tools.urllib.request.urlopen")
def test_post_to_slack_raises_on_slack_api_error(mock_urlopen):
    mock_urlopen.return_value = _ok_response({"ok": False, "error": "channel_not_found"})

    with pytest.raises(SlackToolError, match="channel_not_found"):
        post_to_slack("xoxb-token", "hello", "#nope")


def test_post_file_to_slack_missing_file_raises():
    with pytest.raises(SlackToolError, match="Could not read file"):
        post_file_to_slack("xoxb-token", "/nonexistent/path.md", "#general")


@patch("slack_tools.urllib.request.urlopen")
def test_post_file_to_slack_single_chunk(mock_urlopen, tmp_path):
    mock_urlopen.return_value = _ok_response({"ok": True})
    file_path = tmp_path / "brief.md"
    file_path.write_text("short content")

    result = post_file_to_slack(
        "xoxb-token", str(file_path), "#daily-brief", header="Today's Brief"
    )

    assert result == "File posted to #daily-brief (1 message(s))."
    assert mock_urlopen.call_count == 1
    body = json.loads(mock_urlopen.call_args[0][0].data)
    assert body["text"] == "Today's Brief\n\nshort content"


@patch("slack_tools.urllib.request.urlopen")
def test_post_file_to_slack_chunks_long_content(mock_urlopen, tmp_path):
    mock_urlopen.return_value = _ok_response({"ok": True})
    file_path = tmp_path / "brief.md"
    file_path.write_text("x" * (CHUNK_SIZE * 2 + 100))

    result = post_file_to_slack("xoxb-token", str(file_path), "#daily-brief")

    assert result == "File posted to #daily-brief (3 message(s))."
    assert mock_urlopen.call_count == 3


@patch("slack_tools.urllib.request.urlopen")
def test_post_file_to_slack_no_header_posts_raw_content(mock_urlopen, tmp_path):
    mock_urlopen.return_value = _ok_response({"ok": True})
    file_path = tmp_path / "brief.md"
    file_path.write_text("no header here")

    post_file_to_slack("xoxb-token", str(file_path), "#daily-brief")

    body = json.loads(mock_urlopen.call_args[0][0].data)
    assert body["text"] == "no header here"
