# Testing

Prefix: TEST. How to run each suite is in `AGENTS.md` and `docs/development.md`.

- **TEST1:** `make test-ci` is what CI runs and must stay credential-free and runnable with only Docker on the host. It needs no image build and no network beyond pulling images and packages.
- **TEST2:** A new test that needs no credentials and no built image is added to `make test-ci`. Hermetic shell tests fake `docker`, `claude`, `sudo` or `curl` on `PATH`, like `tests/test_image_select.sh`. Tests that run containers use the published base image and `--network none` where they can, like `tests/programmatic/check-install-output.sh`.
- **TEST3:** The suites run by `./test.sh` call real Claude Code and need `tests/.env`. They are never added to CI.
- **TEST4:** Adapter changes are covered in `claudebox/tests/test_adapter.py`, wrapper changes in the hermetic wrapper tests, entrypoint changes in `tests/test_entrypoint_aliases.sh` or `tests/test_entrypoint_identity.sh`, and launcher changes in `tests/test_agent_launcher.sh`.
- **TEST5:** Tests write only to temporary directories. The CI targets mount the repository read-only, so a test that writes into the checkout fails there.
