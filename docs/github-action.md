# GitHub Action

[Back to README](../README.md)

[`action.yml`](../action.yml) runs claudebox one-shot in a workflow job, through this repo's own `wrapper.sh`. A context directory is mounted read-only at `/context`, and Claude writes into one output directory, which is its workspace.

```yaml
jobs:
  summarize:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v6
        with:
          persist-credentials: false
      - id: claude
        uses: psyb0t/docker-claudebox@master
        with:
          prompt: "Summarize /context/CHANGELOG.md into summary.md."
          context-path: .
          claude-code-oauth-token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
      - run: cat "${{ steps.claude.outputs.output-path }}/summary.md"
```

| Input | Default | Description |
| --- | --- | --- |
| `prompt` / `prompt-file` | | Prompt text, or a file relative to the workspace. Set exactly one. |
| `context-path` | `.` | Directory mounted read-only at `/context`. |
| `output-path` | `$RUNNER_TEMP/claudebox-output` | Writable output directory. Must not overlap `context-path`. |
| `anthropic-api-key` / `claude-code-oauth-token` | | Set one or both. The action fails without either, masks both and forwards them as `CLAUDEBOX_ENV_*`. |
| `image` | `psyb0t/claudebox:latest` | Image. The default follows the latest minimal release. Pin a tag or digest to freeze it. |
| `model`, `effort` | | Passed as `--model` and `--effort`. |
| `stream` | `true` | With `output-format: json`, print Claude's messages, tool calls and tool results to the job log as they happen. The `result` output is unchanged. |
| `output-format` | `json` | `json`, `text` or `stream-json`. |

Outputs are `result` and `output-path`. With `output-format: json`, `result` contains Claude's final text. With `text` or `stream-json`, it contains raw stdout. Set `timeout-minutes` on the job, because a composite action cannot. The action fails when claudebox exits non-zero, JSON output is invalid, or its `is_error` field is not `false`.

A fixed preamble tells Claude to treat `/context` as untrusted data, write only requested output files, use the network only for package and image downloads, never send context or credentials elsewhere, and never push. These are model instructions, not network or filesystem enforcement. `~/.claude` and the SSH directory are empty job-local directories, and `SSH_AUTH_SOCK` is unset.

**Use it only on ephemeral runners.** The wrapper always mounts `/var/run/docker.sock` and uses host networking, so Claude can drive the runner's Docker daemon, which is root on the runner. A runner may also hold checked-out files, job tokens, and state from earlier steps. Do not give this job unrelated credentials or sensitive workloads. Give the job `contents: read`, pass no other secret, and treat everything in the output directory as untrusted.
