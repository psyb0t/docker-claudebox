# Docs and releases

Prefix: DOC. Applies to `README.md`, `docs/`, `CHANGELOG.md` and the release flow.

- **DOC1:** `README.md` is the front door: what it is, install, first run, variants, the mode table, and the Documentation section. Reference material lives in `docs/`. README links to the site use full `https://psyb0t.github.io/docker-claudebox/` URLs, because the README is mirrored to Docker Hub and other forges.
- **DOC2:** Every page in `docs/` has front matter with a unique `title` and a `description` of 50 to 170 characters, and one `#` heading. Pages under `docs/modes/` set `parent: "Modes"`.
- **DOC3:** Page-to-page links use the relative `.md` path. A file outside `docs/` is linked with its full `https://github.com/psyb0t/docker-claudebox/blob/master/...` URL.
- **DOC4:** A code block containing `{{` or `{%` is wrapped in `<!-- {% raw %} -->` and `<!-- {% endraw %} -->`, or Jekyll renders it empty.
- **DOC5:** After a docs change, `make docs` must build and the site checker must report no problems. A behavior, flag or setting change updates its page in the same change.
- **DOC6:** Features the aicodebox base owns may link to the aicodebox site, but these pages still document the `CLAUDEBOX_*` names, defaults and claudebox differences.
- **DOC7:** Prose: no em dashes, "directory" not "folder", plain words, first person singular where a person speaks. Keep each paragraph on one source line.
- **DOC8:** Version numbers move only through `make version V=X.Y.Z`, at release time, together with the CHANGELOG entry. A tag `vX.Y.Z` on a `master` commit whose pipeline passed triggers promotion, the GitHub release and the ClawHub and MCP registry publishing.
