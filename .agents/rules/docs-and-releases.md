# Docs and releases

Prefix: DOC. Applies to `README.md`, `docs/`, `CHANGELOG.md` and the release flow.

- **DOC1:** `README.md` is the front door: what it is, install, first run, variants, the mode table, and the Documentation section. Reference material lives in `docs/`. README links to the site use full `https://psyb0t.github.io/docker-claudebox/` URLs, because the README is mirrored to Docker Hub and other forges.
- **DOC2:** Page order and nesting live in `website/sidebars.mjs`. Pages under `docs/modes/` belong to the Modes category.
- **DOC4:** `website/static/llms.txt` lists every page with its title and description. A new or renamed page changes it in the same change.
- **DOC5:** After a docs change, `make docs` must build with no broken link or anchor.
- **DOC6:** Features the aicodebox base owns may link to the aicodebox site, but these pages still document the `CLAUDEBOX_*` names, defaults and claudebox differences.
- **DOC8:** Version numbers move only through `make version V=X.Y.Z`. A tag `vX.Y.Z` on a `master` commit whose pipeline passed triggers promotion, the GitHub release and the ClawHub and MCP registry publishing.
