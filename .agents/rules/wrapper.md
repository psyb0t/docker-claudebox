# Wrapper and installer

Prefix: WRP. Applies to `wrapper.sh`, `install.sh` and `action.yml`.

- **WRP1:** `install.sh` and `wrapper.sh` must resolve the same image for the same environment. `tests/test_image_select.sh` checks it; extend that test when image selection changes.
- **WRP2:** The `CLAUDEBOX_INSTALLED_VARIANT="minimal"` line near the top of `wrapper.sh` is rewritten by `install.sh`. Keep its exact form.
- **WRP3:** The wrapper passes native CLI output through byte for byte. Do not post-process `json` or `stream-json` output. `tests/programmatic/check-contract.sh` checks it.
- **WRP4:** The wrapper accepts only the flags in its own allowlist. A new flag is added to the parser, to the `Unknown flag` message, to `docs/modes/programmatic.md`, and to the skill.
- **WRP5:** `AICODEBOX_LAUNCH_CONTEXT_VERSION` and `AICODEBOX_HOST_*` are the nested-launch contract shared with codexbox and pibox. Version `1` is the only accepted value; a breaking change needs a new version in every box.
- **WRP6:** `CLAUDE_*` host names stay accepted as fallbacks for their `CLAUDEBOX_*` names. `docs/upgrading.md` lists them.
- **WRP7:** `CLAUDEBOX_RELEASE_REF` in `install.sh` is set by `make version`. Do not edit it by hand.
