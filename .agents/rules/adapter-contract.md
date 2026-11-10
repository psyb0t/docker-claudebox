# Adapter contract

Prefix: ADP. `ClaudecodeAdapter` in `claudebox/claudebox/adapter.py` implements the aicodebox `AgentAdapter` base class. The API, MCP, Telegram and cron servers call it for every run.

- **ADP1:** The base class in the aicodebox repository (`aicodebox/adapters/base.py`) is the contract. Read it before changing a method signature or a `RunRequest` or `RunResult` field, and keep this adapter in step with the base version the Dockerfiles build on.
- **ADP2:** `build_argv` always produces `claude -p --output-format stream-json --verbose --permission-mode bypassPermissions` plus `FULL_EVENT_ARGS`. The parsers and `eventMode: full` depend on the complete native stream, so do not drop any of these.
- **ADP3:** The append-system-prompt order is system hint, then always-skills in sorted path order, then the caller's `append_system_prompt` (`_compose_append_system_prompt`). `claudebox-agent.sh` builds the same hint and skills block for the CLI path. Change both together, and keep the `[Skill file: <path>]` header format.
- **ADP4:** Session handling: `resume` wins, then `no_continue` leaves `--continue` out, otherwise `--continue` is added. Tools: `no_tools` sends `--disallowedTools '*'`, otherwise `tools_allowlist` becomes `--allowedTools`. `extra_args` go last.
- **ADP5:** `CLAUDE_MODELS` and `CLAUDE_THINKING_LEVELS` are what the servers advertise. Effort levels must stay ones `claude --effort` accepts. A change updates `docs/modes/api.md`, `docs/modes/telegram.md` and the skill.
- **ADP6:** `parse_events` returns native records unchanged through `parse_native_event_lines`. Never filter, rename or truncate fields there; the API's full event mode promises the original records.
- **ADP7:** Every behavior change in `build_argv` or a parser gets a test in `claudebox/tests/test_adapter.py`.
