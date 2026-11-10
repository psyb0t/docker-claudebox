# Bash code

Prefix: SH. Applies to every tracked `.sh` file: the wrapper, installer, entrypoint, launcher, init scripts and tests.

- **SH1:** `make lint` must pass. It runs shellcheck at warning level and `shfmt -i 4 -ci -d` on every tracked `.sh` file. `make format` applies the shfmt layout. A `# shellcheck disable=` needs a reason on the same or the previous line, as in `tests/common.sh` and `tests/test_entrypoint.sh`.
- **SH2:** Executable scripts start with a shebang and `set -euo pipefail`. Two exceptions: the `tests/test_*.sh` files that `test.sh` sources, which inherit its options, and `wrapper.sh`, which reads a failed `docker` call's status into `prog_rc` after the call. `set -e` would exit before that line, so do not add it to `wrapper.sh` without reworking those paths.
- **SH3:** Pass argument lists as arrays (`DOCKER_ARGS`, `PASS_ARGS`, `flags`, `args`) and expand them quoted. Never build a command line in a string and `eval` it. Expand an array that may be empty as `${args[@]+"${args[@]}"}`, as `claudebox-agent.sh` does.
- **SH4:** `install.sh` rewrites the wrapper through a temporary file instead of `sed -i`, because `sed -i` differs between GNU and BSD. Keep that pattern, and do not add other GNU-only flags to the files that run on users' hosts (`wrapper.sh`, `install.sh`).
- **SH5:** Error messages a user can hit are part of the contract. The troubleshooting page (`docs/troubleshooting.md`) quotes them, so change it in the same change when a message changes.
- **SH6:** Debug output goes to stderr and only when `DEBUG=true` (`dbg` in `wrapper.sh` and `claudebox-agent.sh`). Never print a credential, even in debug output; log whether it is set, as the wrapper does.
- **SH7:** Successful first-start installation must not write to stdout or stderr. Programmatic callers parse stdout, and `tests/programmatic/check-install-output.sh` enforces it.
