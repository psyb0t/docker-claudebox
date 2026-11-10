# Agent surface

Prefix: AGT. The skill, the plugin manifests and the OpenClaw bridge under `.agents/` describe claudebox to other agents. They are public and published to ClawHub on every release.

- **AGT1:** A change to a mode, a wrapper flag, a tool or a setting updates `.agents/skills/claudebox/SKILL.md` and `references/setup.md` in the same change.
- **AGT2:** The MCP tool list (`run_prompt`, `list_files`, `read_file`, `write_file`, `delete_file`) appears in the skill, `.agents/plugins/claudebox/README.md`, the `description` in `.agents/plugins/claudebox/openclaw.plugin.json`, and `docs/modes/mcp.md`. It comes from aicodebox's MCP server; update all of them together.
- **AGT3:** The Codex manifest `version` in `.agents/.codex-plugin/plugin.json` is set by `make version`. The Claude manifest carries no version. The bridge `package.json`, `openclaw.plugin.json` and `server.json` stay at `0.0.0` in the repository; on a tag, the publish workflows write the tag version into `package.json` and `server.json`.
- **AGT4:** `bin/cli.js` writes nothing to stdout, because stdout is the MCP channel, and never prints the token.
- **AGT5:** The pipeline publishes the directories named in `skill_names` and `plugin_names` of the `publish-to-clawhub` job. A new skill or plugin directory is added there.
