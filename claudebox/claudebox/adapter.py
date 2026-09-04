"""ClaudecodeAdapter — wires the aicodebox AgentAdapter contract to claude-code.

claude CLI surface used here:
  -p / --print                       non-interactive
  --output-format stream-json        NDJSON event stream w/ session/usage/text
  --verbose                          required by stream-json to include tool_result blocks
  --permission-mode bypassPermissions  bypass every permission prompt (non-TTY)
  --model <id>                       model override
  --system-prompt <text>             replace default system prompt
  --append-system-prompt <text>      append (repeatable)
  --continue                         resume most recent session in cwd
  --resume <id>                      resume a specific session id
  --allowedTools <csv>               allowlist
  --disallowedTools <csv>            denylist
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any, ClassVar

from aicodebox.adapters.base import (
    AgentAdapter,
    RunRequest,
    RunResult,
    StreamEvent,
)

logger = logging.getLogger(__name__)

DEFAULT_PERMISSION_MODE = "bypassPermissions"
SKILLS_DIR_DEFAULT = "/home/aicode/.claude/.always-skills"
SYSTEM_HINT_FILE_DEFAULT = "/home/aicode/.claude/system-hint.txt"

CLAUDE_MODELS = ["haiku", "sonnet", "opus", "opusplan"]
CLAUDE_THINKING_LEVELS = ["off", "low", "medium", "high", "xhigh", "max"]

VALID_STOP_REASONS = {"end_turn", "stop_sequence", "max_tokens", "tool_use", "error"}

FULL_EVENT_ARGS = (
    "--include-partial-messages",
    "--forward-subagent-text",
    "--include-hook-events",
)


def _truncate(value: Any, limit: int = 80) -> str:
    if value is None:
        return ""
    s = str(value)
    if len(s) <= limit:
        return s
    return s[:limit] + "..."


def _read_always_skills(skills_dir: str) -> str:
    """Concat every SKILL.md under skills_dir as `[Skill file: path]\n\n<content>` blocks.

    Matches the shape from the pre-migration entrypoint.sh (skill_block format,
    sorted by path). Empty return when the dir is missing or has no SKILL.md files.
    """
    skills_path = Path(skills_dir)
    if not skills_path.is_dir():
        logger.debug(
            "always-skills dir missing",
            extra={"skills_dir": skills_dir},
        )
        return ""

    skill_files = sorted(skills_path.rglob("SKILL.md"))
    if not skill_files:
        logger.debug(
            "always-skills dir has no SKILL.md files",
            extra={"skills_dir": skills_dir},
        )
        return ""

    blocks: list[str] = []
    for skill_file in skill_files:
        try:
            content = skill_file.read_text(encoding="utf-8", errors="replace")
        except OSError as err:
            logger.warning(
                "always-skill unreadable, skipping",
                extra={"path": str(skill_file), "err": str(err)},
            )
            continue
        if not content.strip():
            continue
        blocks.append(f"[Skill file: {skill_file}]\n\n{content}")

    logger.debug(
        "always-skills scanned",
        extra={"skills_dir": skills_dir, "count": len(blocks)},
    )
    return "\n\n".join(blocks)


def _read_system_hint(hint_file: str) -> str:
    hint_path = Path(hint_file)
    if not hint_path.is_file():
        return ""
    try:
        return hint_path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError as err:
        logger.warning(
            "system-hint unreadable, skipping",
            extra={"path": hint_file, "err": str(err)},
        )
        return ""


def _compose_append_system_prompt(caller_value: str | None) -> str | None:
    """Build the combined --append-system-prompt payload.

    Order matches the pre-migration entrypoint: system-hint first, then
    always-skills concatenated, then caller's own append_system_prompt at the
    end. Returns None if nothing to append.
    """
    skills_dir = os.environ.get("CLAUDEBOX_ALWAYS_SKILLS_DIR", SKILLS_DIR_DEFAULT)
    hint_file = os.environ.get("CLAUDEBOX_SYSTEM_HINT_FILE", SYSTEM_HINT_FILE_DEFAULT)

    parts: list[str] = []
    hint = _read_system_hint(hint_file)
    if hint:
        parts.append(hint)
    skills = _read_always_skills(skills_dir)
    if skills:
        parts.append(skills)
    if caller_value:
        parts.append(caller_value)

    if not parts:
        return None
    return "\n\n".join(parts)


class ClaudecodeAdapter(AgentAdapter):
    name: ClassVar[str] = "claude"
    binary: ClassVar[str] = "claude"
    available_models: ClassVar[list[str]] = CLAUDE_MODELS
    available_thinking_levels: ClassVar[list[str]] = CLAUDE_THINKING_LEVELS

    def build_argv(self, req: RunRequest) -> list[str]:
        argv: list[str] = [
            self.binary,
            "-p",
            "--output-format",
            "stream-json",
            "--verbose",
            "--permission-mode",
            DEFAULT_PERMISSION_MODE,
        ]

        if req.model:
            argv += ["--model", req.model]

        if req.event_mode == "full":
            argv += list(FULL_EVENT_ARGS)

        combined_append = _compose_append_system_prompt(req.append_system_prompt)
        if combined_append:
            argv += ["--append-system-prompt", combined_append]

        if req.system_prompt:
            argv += ["--system-prompt", req.system_prompt]

        if req.json_schema:
            argv += ["--json-schema", json.dumps(req.json_schema)]

        session_choice: str
        if req.resume:
            argv += ["--resume", req.resume]
            session_choice = "resume"
        elif req.no_continue:
            session_choice = "no-continue"
        else:
            argv += ["--continue"]
            session_choice = "continue"

        tools_choice: str
        if req.no_tools:
            argv += ["--disallowedTools", "*"]
            tools_choice = "none"
        elif req.tools_allowlist:
            argv += ["--allowedTools", ",".join(req.tools_allowlist)]
            tools_choice = "allowlist"
        else:
            tools_choice = "default"

        if req.extra_args:
            argv += list(req.extra_args)

        logger.debug(
            "build_argv done",
            extra={
                "model": req.model or "(default)",
                "session": session_choice,
                "tools": tools_choice,
                "has_schema": req.json_schema is not None,
                "argc": len(argv),
            },
        )
        return argv

    def translate_auth(self, env: dict[str, str]) -> dict[str, str]:
        del env
        return {}

    def parse_output(self, stdout: str, req: RunRequest) -> RunResult:
        """Walk claude's stream-json output and reassemble text + session + usage.

        Semantics ported from the pre-migration jsonpipe.py: system.subtype=init
        → session_id; assistant.message.content[type=text] → text; final
        `result` event → stop_reason + usage; tool_result blocks truncated at
        STREAM_TOOL_RESULT_TRUNCATE w/ sha256 (for parse_events, not text).
        """
        del req
        session_id = ""
        text_parts: list[str] = []
        usage: dict[str, Any] | None = None
        stop_reason = ""
        line_count = 0
        decode_errors = 0

        for raw_line in stdout.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            line_count += 1
            try:
                event = json.loads(line)
            except json.JSONDecodeError as err:
                decode_errors += 1
                logger.warning(
                    "parse_output: malformed stream-json line",
                    extra={"err": err.msg, "sample": _truncate(line, 80)},
                )
                continue

            etype = event.get("type", "")

            if etype == "system" and event.get("subtype") == "init":
                sid = event.get("session_id", "")
                if isinstance(sid, str):
                    session_id = sid
                continue

            if etype == "assistant":
                msg = event.get("message", {})
                if not isinstance(msg, dict):
                    continue
                content = msg.get("content", [])
                if not isinstance(content, list):
                    continue
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "text":
                        block_text = block.get("text", "")
                        if isinstance(block_text, str) and block_text:
                            text_parts.append(block_text)
                continue

            if etype == "result":
                result_usage = event.get("usage")
                if isinstance(result_usage, dict):
                    usage = dict(result_usage)
                sr = event.get("stop_reason", "")
                if isinstance(sr, str):
                    stop_reason = sr

        text = "".join(text_parts).strip()
        if usage:
            if "input_tokens" not in usage and "input" in usage:
                usage["input_tokens"] = usage["input"]
            if "output_tokens" not in usage and "output" in usage:
                usage["output_tokens"] = usage["output"]

        logger.info(
            "parse_output done",
            extra={
                "text_len": len(text),
                "session_id": session_id or "(none)",
                "lines": line_count,
                "decode_errors": decode_errors,
                "stop_reason": stop_reason,
                "usage_keys": sorted(usage.keys()) if usage else [],
            },
        )

        return RunResult(
            text=text,
            raw_stdout=stdout,
            raw_stderr="",
            exit_code=0,
            session_id=session_id,
            usage=usage,
        )

    def parse_events(self, stdout: str, req: RunRequest) -> list[dict[str, Any]]:
        """Return every native Claude stream-json record without collapsing it."""
        del req
        events: list[dict[str, Any]] = []

        for raw_line in stdout.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError as err:
                logger.warning(
                    "parse_events: malformed stream-json line",
                    extra={"err": err.msg, "sample": _truncate(line, 80)},
                )
                continue
            if isinstance(event, dict):
                events.append(event)
        return events

    def parse_stream_event(self, line: str, req: RunRequest) -> StreamEvent | None:
        del req
        if not line:
            return None
        try:
            event = json.loads(line)
        except json.JSONDecodeError as err:
            logger.warning(
                "parse_stream_event: malformed line",
                extra={"err": err.msg, "sample": _truncate(line, 80)},
            )
            return None

        etype = event.get("type", "")

        if etype == "system" and event.get("subtype") == "init":
            sid = event.get("session_id", "")
            if isinstance(sid, str) and sid:
                return StreamEvent(type="session", data={"id": sid})
            return None

        if etype == "assistant":
            msg = event.get("message", {})
            content = msg.get("content", []) if isinstance(msg, dict) else []
            if not isinstance(content, list):
                return None
            delta_parts: list[str] = []
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    text = block.get("text", "")
                    if isinstance(text, str) and text:
                        delta_parts.append(text)
            if delta_parts:
                return StreamEvent(type="delta", text="".join(delta_parts))
            return None

        if etype == "result":
            data: dict[str, Any] = {}
            usage = event.get("usage")
            if isinstance(usage, dict):
                norm = dict(usage)
                if "input_tokens" not in norm and "input" in norm:
                    norm["input_tokens"] = norm["input"]
                if "output_tokens" not in norm and "output" in norm:
                    norm["output_tokens"] = norm["output"]
                data["usage"] = norm
            reason = event.get("stop_reason", "stop")
            if isinstance(reason, str) and reason in VALID_STOP_REASONS:
                data["reason"] = reason
            else:
                data["reason"] = "stop"
            return StreamEvent(type="stop", data=data)

        return None

    def interactive_argv(self, workspace: str) -> list[str]:
        del workspace
        return [self.binary]

    def passthrough_argv(self, args: list[str]) -> list[str]:
        return [self.binary, *args]

    def auth_paths(self) -> list[str]:
        home = os.environ.get("HOME", "/home/aicode")
        # Claude Code keeps .claude.json under CLAUDE_CONFIG_DIR when that's
        # set (the image sets it to the bind-mounted ~/.claude so config +
        # login persist); otherwise it's the $HOME/.claude.json default.
        config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
        claude_json = f"{config_dir}/.claude.json" if config_dir else f"{home}/.claude.json"
        return [
            f"{home}/.claude/.credentials.json",
            claude_json,
        ]
