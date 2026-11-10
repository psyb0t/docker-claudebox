# Bash code

Prefix: SH. Applies to every tracked `.sh` file: the wrapper, installer, entrypoint, launcher, init scripts and tests.

- **SH1:** `make lint` runs shellcheck at warning level and `shfmt -i 4 -ci -d` on every tracked `.sh` file. `make format` applies the shfmt layout.
- **SH2:** Exceptions to `set -euo pipefail`: the `tests/test_*.sh` files that `test.sh` sources, which inherit its options, and `wrapper.sh`, which reads a failed `docker` call's status into `prog_rc` after the call. `set -e` would exit before that line, so do not add it to `wrapper.sh` without reworking those paths.
- **SH4:** `install.sh` rewrites the wrapper through a temporary file instead of `sed -i`, because `sed -i` differs between GNU and BSD. Keep that pattern, and do not add other GNU-only flags to the files that run on users' hosts (`wrapper.sh`, `install.sh`).
- **SH5:** Error messages a user can hit are part of the contract. The troubleshooting page (`docs/troubleshooting.md`) quotes them, so change it in the same change when a message changes.
- **SH6:** Debug output goes to stderr and only when `DEBUG=true` (`dbg` in `wrapper.sh` and `claudebox-agent.sh`).
- **SH7:** Successful first-start installation must not write to stdout or stderr. Programmatic callers parse stdout, and `tests/programmatic/check-install-output.sh` enforces it.
