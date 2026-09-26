# Notes for working on this repository

Self-hosted Zotero sync server: upstream dataserver, stream-server and web-library in Docker Compose,
plus our own portal, migrations and scripts. README.md describes the stack, README-upgrade.md the history.

## Upstream code

- Never edit the submodules under `src/server/`. Dataserver changes are patch files in
  `src/patches/dataserver/`, applied at image build time. To change one, work on the `selfhost` branch in
  `src/server/dataserver` and regenerate with `git format-patch -o ../../patches/dataserver origin/master`.
- Versions are pinned in `versions.lock` and the submodule pointers. Change them only with
  `utils/update.sh <name> <ref>`; it checks the patches and keeps `WEB_LIBRARY_COMMIT` in `.env` and
  `.env.example` in sync.

## Database

- `config/dataserver-scripts/migrate.sh` (service `db-migrate`) is the only way schema changes reach existing
  databases. Every step has a `check_` function that inspects the database, so steps must stay idempotent and
  work from any older state. When upstream adds a directory under `misc/db-updates/`, add a matching step.
- `init-mysql.sh` only creates new databases. It must produce the same schema that `migrate.sh` reaches.
- Our own tables live in `zotero_selfhost` (`migrations`, `settings`). The shared group's ID is in
  `zotero_selfhost.settings` (`sharedGroupID`); don't assume group 1.
- The dataserver caches group data, including the owner, in memcached (`<API URL>groupData_<id>`). Code that
  changes groups with plain SQL, like the portal, must delete that key. Prefer the dataserver's PHP API
  (`Zotero_Groups`) in scripts that run in the dataserver image.
- Values interpolated into SQL in shell scripts must be validated first (see `create-user.sh`).

## portal

- Login modes: OIDC only, password only (`OIDC_ISSUER` empty), or both (`PASSWORD_LOGIN=true`). Test all
  three when touching login code.
- Super-user calls to the dataserver go over the internal `backend` network (10.203.77.0/28); the dataserver
  accepts super-user requests only from private addresses.
- Texts are English and go through `t()`; `lang/de.php` translates them, keyed by the English text. Add every
  new text there too.

## Testing

- After changes, rebuild the affected images and run `utils/smoke-test.py` (and `--public` behind a proxy).
  It needs Docker access (often `sudo`). Environment variables override `.env`, e.g. to check a second portal:
  `docker compose run -d -e OIDC_ISSUER= -p 127.0.0.1:8194:80 portal`, then
  `PORTAL_PORT=8194 OIDC_ISSUER= utils/smoke-test.py`.
- Migration changes: test against an old database, not only the current one (see README-upgrade.md).

## Git

- Work on the `steps` branch. `pr/upstream` holds the same changes without merge commits, for a pull request
  to foxsen/zotero-selfhost; cherry-pick new commits there. The final tree of both must stay identical
  (`git diff steps pr/upstream` empty).
- Check the current branch before committing.
- Commit messages explain what changes and why, in some detail.
- Keep the repository deployment-neutral: no host names, identity providers or site-specific docs. Those stay
  in `.env` or untracked files.
- `.env` and `data/` are never committed.
