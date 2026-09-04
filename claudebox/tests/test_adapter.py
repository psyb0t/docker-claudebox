"""Unit tests for ClaudecodeAdapter.

Plan: `.testing/2026-07-04/claudebox-adapter.md`.

Runs in-process against the aicodebox AgentAdapter base contract. No docker,
no real claude binary. Covers:
  - build_argv: default flags, permission-mode presence, RunRequest field
    translation, .always-skills injection, system-hint compose order.
  - parse_output: stream-json → text + session + usage.
  - parse_events: complete native stream-json records.
  - parse_stream_event: session / delta / stop line handling.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from aicodebox.adapters.base import RunRequest

from claudebox.adapter import (
    DEFAULT_PERMISSION_MODE,
    FULL_EVENT_ARGS,
    ClaudecodeAdapter,
    _read_always_skills,
    _read_system_hint,
)


@pytest.fixture
def adapter() -> ClaudecodeAdapter:
    return ClaudecodeAdapter()


@pytest.fixture(autouse=True)
def _isolated_skills_and_hint(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Point the adapter at empty scratch skills dir + hint file per test."""
    skills_dir = tmp_path / "always-skills"
    hint_file = tmp_path / "system-hint.txt"
    monkeypatch.setenv("CLAUDEBOX_ALWAYS_SKILLS_DIR", str(skills_dir))
    monkeypatch.setenv("CLAUDEBOX_SYSTEM_HINT_FILE", str(hint_file))


# ── build_argv ───────────────────────────────────────────────────────────────


def test_build_argv_seeds_defaults(adapter: ClaudecodeAdapter) -> None:
    argv = adapter.build_argv(RunRequest(prompt="hi"))

    assert argv[0] == "claude"
    assert "-p" in argv
    fmt_idx = argv.index("--output-format")
    assert argv[fmt_idx + 1] == "stream-json"
    assert "--verbose" in argv
    pm_idx = argv.index("--permission-mode")
    assert argv[pm_idx + 1] == DEFAULT_PERMISSION_MODE


def test_build_argv_continue_default(adapter: ClaudecodeAdapter) -> None:
    argv = adapter.build_argv(RunRequest(prompt="hi"))
    assert "--continue" in argv


def test_build_argv_no_continue_drops_flag(adapter: ClaudecodeAdapter) -> None:
    argv = adapter.build_argv(RunRequest(prompt="hi", no_continue=True))
    assert "--continue" not in argv
    assert "--resume" not in argv


def test_build_argv_resume_wins_over_continue(adapter: ClaudecodeAdapter) -> None:
    argv = adapter.build_argv(RunRequest(prompt="hi", resume="sess-123"))
    assert "--resume" in argv
    r_idx = argv.index("--resume")
    assert argv[r_idx + 1] == "sess-123"
    assert "--continue" not in argv


def test_build_argv_model_flag(adapter: ClaudecodeAdapter) -> None:
    argv = adapter.build_argv(RunRequest(prompt="hi", model="opus"))
    m_idx = argv.index("--model")
    assert argv[m_idx + 1] == "opus"


def test_build_argv_tools_allowlist(adapter: ClaudecodeAdapter) -> None:
    argv = adapter.build_argv(
        RunRequest(prompt="hi", tools_allowlist=["Bash", "Edit"]),
    )
    idx = argv.index("--allowedTools")
    assert argv[idx + 1] == "Bash,Edit"


def test_build_argv_no_tools(adapter: ClaudecodeAdapter) -> None:
    argv = adapter.build_argv(RunRequest(prompt="hi", no_tools=True))
    idx = argv.index("--disallowedTools")
    assert argv[idx + 1] == "*"


def test_build_argv_system_prompt(adapter: ClaudecodeAdapter) -> None:
    argv = adapter.build_argv(
        RunRequest(prompt="hi", system_prompt="you are a bot"),
    )
    idx = argv.index("--system-prompt")
    assert argv[idx + 1] == "you are a bot"


def test_build_argv_extra_args_appended_last(adapter: ClaudecodeAdapter) -> None:
    argv = adapter.build_argv(
        RunRequest(prompt="hi", extra_args=["--foo", "bar"]),
    )
    assert argv[-2:] == ["--foo", "bar"]


def test_build_argv_json_schema_uses_native_flag(
    adapter: ClaudecodeAdapter,
) -> None:
    schema = {"type": "object", "required": ["name"]}
    argv = adapter.build_argv(RunRequest(prompt="hi", json_schema=schema))

    schema_idx = argv.index("--json-schema")
    assert json.loads(argv[schema_idx + 1]) == schema


def test_build_argv_full_event_mode_enables_complete_stream(
    adapter: ClaudecodeAdapter,
) -> None:
    argv = adapter.build_argv(RunRequest(prompt="hi", event_mode="full"))

    for arg in FULL_EVENT_ARGS:
        assert arg in argv


# ── always-skills injection ──────────────────────────────────────────────────


def test_build_argv_injects_skills(
    adapter: ClaudecodeAdapter,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    skills_dir = tmp_path / "skills"
    (skills_dir / "wf-a").mkdir(parents=True)
    (skills_dir / "wf-a" / "SKILL.md").write_text("skill-a-body")
    (skills_dir / "wf-b").mkdir(parents=True)
    (skills_dir / "wf-b" / "SKILL.md").write_text("skill-b-body")
    monkeypatch.setenv("CLAUDEBOX_ALWAYS_SKILLS_DIR", str(skills_dir))

    argv = adapter.build_argv(RunRequest(prompt="hi"))
    idx = argv.index("--append-system-prompt")
    payload = argv[idx + 1]
    assert "[Skill file:" in payload
    assert "skill-a-body" in payload
    assert "skill-b-body" in payload


def test_build_argv_skills_sorted(
    adapter: ClaudecodeAdapter,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    skills_dir = tmp_path / "skills"
    for name in ("z-last", "a-first", "m-middle"):
        subdir = skills_dir / name
        subdir.mkdir(parents=True)
        (subdir / "SKILL.md").write_text(f"{name}-body")
    monkeypatch.setenv("CLAUDEBOX_ALWAYS_SKILLS_DIR", str(skills_dir))

    argv = adapter.build_argv(RunRequest(prompt="hi"))
    payload = argv[argv.index("--append-system-prompt") + 1]
    assert payload.index("a-first-body") < payload.index("m-middle-body")
    assert payload.index("m-middle-body") < payload.index("z-last-body")


def test_build_argv_no_skills_dir(
    adapter: ClaudecodeAdapter,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv(
        "CLAUDEBOX_ALWAYS_SKILLS_DIR",
        str(tmp_path / "nonexistent"),
    )
    argv = adapter.build_argv(RunRequest(prompt="hi"))
    assert "--append-system-prompt" not in argv


def test_build_argv_system_hint_prepended(
    adapter: ClaudecodeAdapter,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    hint = tmp_path / "system-hint.txt"
    hint.write_text("hint-body")
    monkeypatch.setenv("CLAUDEBOX_SYSTEM_HINT_FILE", str(hint))

    argv = adapter.build_argv(RunRequest(prompt="hi"))
    idx = argv.index("--append-system-prompt")
    payload = argv[idx + 1]
    assert payload.startswith("hint-body")


def test_build_argv_caller_append_composed_last(
    adapter: ClaudecodeAdapter,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    hint = tmp_path / "system-hint.txt"
    hint.write_text("HINT")
    skill_subdir = tmp_path / "skills" / "s"
    skill_subdir.mkdir(parents=True)
    (skill_subdir / "SKILL.md").write_text("SKILL")
    monkeypatch.setenv("CLAUDEBOX_SYSTEM_HINT_FILE", str(hint))
    monkeypatch.setenv(
        "CLAUDEBOX_ALWAYS_SKILLS_DIR",
        str(tmp_path / "skills"),
    )

    argv = adapter.build_argv(
        RunRequest(prompt="hi", append_system_prompt="CALLER"),
    )
    payload = argv[argv.index("--append-system-prompt") + 1]
    assert payload.index("HINT") < payload.index("SKILL") < payload.index("CALLER")


# ── parse_output ─────────────────────────────────────────────────────────────


def _stream_json_fixture() -> str:
    events = [
        {
            "type": "system",
            "subtype": "init",
            "session_id": "sess-abc",
            "model": "claude-opus",
            "cwd": "/workspace",
            "tools": ["Bash", "Edit"],
        },
        {
            "type": "assistant",
            "message": {
                "role": "assistant",
                "content": [
                    {"type": "text", "text": "Sure, "},
                    {
                        "type": "tool_use",
                        "id": "toolu_1",
                        "name": "Bash",
                        "input": {"command": "ls"},
                    },
                ],
            },
        },
        {
            "type": "user",
            "message": {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_1",
                        "content": "file.txt\n",
                        "is_error": False,
                    },
                ],
            },
        },
        {
            "type": "assistant",
            "message": {
                "role": "assistant",
                "content": [{"type": "text", "text": "here it is."}],
            },
        },
        {
            "type": "result",
            "subtype": "success",
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 5},
            "result": "Sure, here it is.",
        },
    ]
    return "\n".join(json.dumps(e) for e in events)


def test_parse_output_assembles_text(adapter: ClaudecodeAdapter) -> None:
    result = adapter.parse_output(_stream_json_fixture(), RunRequest())
    assert result.text == "Sure, here it is."
    assert result.session_id == "sess-abc"
    assert result.usage is not None
    assert result.usage["input_tokens"] == 10
    assert result.usage["output_tokens"] == 5


def test_parse_output_handles_malformed_lines(adapter: ClaudecodeAdapter) -> None:
    stdout = "not-json\n" + _stream_json_fixture() + "\nalso-not-json"
    result = adapter.parse_output(stdout, RunRequest())
    assert result.text == "Sure, here it is."


def test_parse_output_empty_stdout(adapter: ClaudecodeAdapter) -> None:
    result = adapter.parse_output("", RunRequest())
    assert result.text == ""
    assert result.session_id == ""
    assert result.usage is None


# ── parse_events ─────────────────────────────────────────────────────────────


def test_parse_events_preserves_complete_native_stream(adapter: ClaudecodeAdapter) -> None:
    events = adapter.parse_events(_stream_json_fixture(), RunRequest())

    types = [e.get("type") for e in events]
    assert types[0] == "system"
    assert "assistant" in types
    assert "user" in types
    assert types[-1] == "result"
    tool_result = events[2]["message"]["content"][0]
    assert tool_result["type"] == "tool_result"
    assert tool_result["content"] == "file.txt\n"


def test_parse_events_preserves_large_tool_result(
    adapter: ClaudecodeAdapter,
) -> None:
    big_output = "x" * 2500
    events = [
        {
            "type": "user",
            "message": {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "tid",
                        "content": big_output,
                    },
                ],
            },
        },
    ]
    stdout = "\n".join(json.dumps(e) for e in events)
    parsed = adapter.parse_events(stdout, RunRequest())
    tool_result = parsed[0]["message"]["content"][0]
    assert tool_result["content"] == big_output


# ── parse_stream_event ───────────────────────────────────────────────────────


def test_parse_stream_event_session(adapter: ClaudecodeAdapter) -> None:
    line = json.dumps(
        {"type": "system", "subtype": "init", "session_id": "sess-xyz"},
    )
    evt = adapter.parse_stream_event(line, RunRequest())
    assert evt is not None
    assert evt.type == "session"
    assert evt.data == {"id": "sess-xyz"}


def test_parse_stream_event_delta(adapter: ClaudecodeAdapter) -> None:
    line = json.dumps(
        {
            "type": "assistant",
            "message": {
                "role": "assistant",
                "content": [{"type": "text", "text": "hello"}],
            },
        },
    )
    evt = adapter.parse_stream_event(line, RunRequest())
    assert evt is not None
    assert evt.type == "delta"
    assert evt.text == "hello"


def test_parse_stream_event_stop(adapter: ClaudecodeAdapter) -> None:
    line = json.dumps(
        {
            "type": "result",
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 3, "output_tokens": 1},
        },
    )
    evt = adapter.parse_stream_event(line, RunRequest())
    assert evt is not None
    assert evt.type == "stop"
    assert evt.data is not None
    assert evt.data["reason"] == "end_turn"
    assert evt.data["usage"]["input_tokens"] == 3


def test_parse_stream_event_ignores_unknown(adapter: ClaudecodeAdapter) -> None:
    line = json.dumps({"type": "heartbeat", "ts": 12345})
    assert adapter.parse_stream_event(line, RunRequest()) is None


def test_parse_stream_event_malformed_returns_none(
    adapter: ClaudecodeAdapter,
) -> None:
    assert adapter.parse_stream_event("not-json", RunRequest()) is None
    assert adapter.parse_stream_event("", RunRequest()) is None


# ── misc surface ─────────────────────────────────────────────────────────────


def test_interactive_and_passthrough(adapter: ClaudecodeAdapter) -> None:
    assert adapter.interactive_argv("/workspace") == ["claude"]
    assert adapter.passthrough_argv(["--version"]) == ["claude", "--version"]


def test_auth_paths_uses_home(
    adapter: ClaudecodeAdapter,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("HOME", "/home/alt")
    monkeypatch.delenv("CLAUDE_CONFIG_DIR", raising=False)
    paths = adapter.auth_paths()
    assert "/home/alt/.claude/.credentials.json" in paths
    assert "/home/alt/.claude.json" in paths


def test_auth_paths_honors_config_dir(
    adapter: ClaudecodeAdapter,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # With CLAUDE_CONFIG_DIR set (as the image does — to the bind-mounted
    # ~/.claude), .claude.json lives inside it so it persists across runs.
    monkeypatch.setenv("HOME", "/home/alt")
    monkeypatch.setenv("CLAUDE_CONFIG_DIR", "/home/alt/.claude")
    paths = adapter.auth_paths()
    assert "/home/alt/.claude/.credentials.json" in paths
    assert "/home/alt/.claude/.claude.json" in paths
    assert "/home/alt/.claude.json" not in paths


# ── helpers ──────────────────────────────────────────────────────────────────


def test_read_always_skills_missing_dir(tmp_path: Path) -> None:
    assert _read_always_skills(str(tmp_path / "nope")) == ""


def test_read_system_hint_missing_file(tmp_path: Path) -> None:
    assert _read_system_hint(str(tmp_path / "nope.txt")) == ""
