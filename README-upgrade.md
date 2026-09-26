# Upgrade notes: 2021 → 2026

This document describes how this package was brought from its 2021 state
(fork of [foxsen/zotero-selfhost](https://github.com/foxsen/zotero-selfhost), commit `09bf387`)
to current upstream versions. It covers the component versions before and after,
what was changed and why, which parts of the previous [README](README.md) are
obsolete, and what is still open. Day-to-day usage is described in [README.md](README.md).

## Summary

- All server components run current upstream code on a supported stack (PHP 8.4, MySQL 8.4, Node 22/24).
- **No AWS services.** S3 is provided by [Garage](https://garagehq.deuxfleurs.fr/). SNS, SQS, DynamoDB and Elasticsearch are no longer required.
- **No custom client build.** The official Zotero desktop client syncs against the server after setting two preferences.
- One container per service. Upstream sources stay untouched as submodules, and changes are applied as patch files at image build time.
- New, optional **portal** service: OpenID Connect login (e.g. Keycloak), automatic user provisioning, a per-user web-library, and the desktop client's browser-based login.

## Versions

### Upstream sources (git submodules)

| Component | Before (commit, date) | After (commit, date) | Behind |
| --- | --- | --- | --- |
| [dataserver](https://github.com/zotero/dataserver) | `3190eb1`, 2021-01-16 | `6e09185`, 2026-09-19 | 338 commits |
| [web-library](https://github.com/zotero/web-library) | `db6d03a`, 2021-02-26 | `9f6cf79`, 2026-09-11 (v1.8.2) | 944 commits |
| [stream-server](https://github.com/zotero/stream-server) | `7e2e57d`, 2020-04-25 | `9dc1725`, 2026-09-02 | 22 commits |
| [tinymce-clean-server](https://github.com/zotero/tinymce-clean-server) | `5be2a0d`, 2017-06-29 | unchanged (no upstream activity since 2017) | – |
| [zotero](https://github.com/zotero/zotero) (client) | `2cea1a5`, 2021-03-03 (5.0.96.1) | removed | 5516 commits |
| [zotero-build](https://github.com/zotero/zotero-build) | `468b2a1`, 2020-04-17 | removed | – |
| [zotero-standalone-build](https://github.com/zotero/zotero-standalone-build) | `9d00c5c`, 2021-03-02 | removed (merged into `zotero/app/` upstream) | – |

The pins are recorded in `versions.lock` (path, ref, commit) and in the submodule pointers.
web-library is pinned to its release tag. dataserver, stream-server and tinymce-clean-server have no release tags
upstream, so they are pinned to a master commit, named `master@<commit date>`. `utils/update.sh` shows what upstream
offers and moves one submodule to a given tag or commit.

The dataserver's `htdocs/zotero-schema` submodule is at `62e983a` (2026-03). After initialization the
database schema version is **42**.

Server-side API compatibility was verified for the Zotero client at `zotero/zotero@cc951f991`
(2026-09-24, main after the 10.0 release, Firefox 153.3.0esr). An end-to-end sync with that client is still to be done.

### Runtime

| Component | Before | After |
| --- | --- | --- |
| Base image (dataserver) | `ubuntu:18.04` | `php:8.4-apache` (PHP 8.4.26, Apache 2.4.68) |
| PHP | 7.2 | 8.4 |
| Zend Framework 1 | 1.12.20, bundled as `Zend.tar.gz` | [`shardj/zf1-future`](https://github.com/Shardj/zf1-future) 1.25.2 via Composer |
| AWS SDK for PHP | from 2021 | 3.369 (from upstream `composer.lock`) |
| MySQL | 5.7 | 8.4 LTS (8.4.11) |
| S3 storage | MinIO (`minio/minio`, no longer on Docker Hub) | Garage `dxflrs/garage:v2.4.0` |
| Redis | `redis:5.0` | Valkey `valkey/valkey:8-alpine` (8.1) |
| Memcached | 1.5 | 1.6 (1.6.45) |
| Elasticsearch | 5.3.0 | removed (optional, see below) |
| LocalStack (SNS/SQS) | `atlassianlabs/localstack` | removed |
| phpMyAdmin | included | removed |
| stream-server, tinymce-clean | Node from Ubuntu 18.04 | `node:22-alpine` (22.23) |
| web-library | built manually | Node 24 build stage, served by `nginx:1-alpine` |
| portal (new) | – | `php:8.4-apache`, [`jumbojett/openid-connect-php`](https://github.com/jumbojett/OpenID-Connect-PHP) 1.0.2 |

## What changed

### Repository layout

- `src/server/*`: upstream submodules. **Nothing is modified inside them.** The `.gitmodules` entries still use the old names (`server/…`, `client/web-library`).
- `src/patches/dataserver/`: patch files, applied in `docker/dataserver/Dockerfile`.
- `docker/<service>/`: one Dockerfile per service. The old top-level `Dockerfile` is removed.
- `config/`: dataserver, Apache, PHP, MySQL, Garage and stream-server configuration.
- `config/dataserver-scripts/`: database setup and user management, copied into the dataserver image.
- `bin/`, `utils/`: operations, setup, updates and the smoke test.
- `data/`: persistent data as bind mounts (`data/mysql` owned by 999:999, `data/garage` by root, `data/dataserver-errors` by 33:33). Excluded from git and the Docker build context. Replaces the named volumes, so host-side backups can read the files directly. The one-shot `init-data` service (`docker/init-data/init-data.sh`) runs before every other service on each `docker compose up`: it creates missing directories and fixes owners and modes, e.g. after a restore.
- Removed:
  - `src/client/*`
  - `src/patches/web-library/`, `src/patches/zotero-client/`
  - `src/patches/dataserver/Zend.tar.gz`
  - `config/entrypoint.sh`, `config/default.js`
  - `utils/build.sh`

### dataserver patches

| Patch | Purpose |
| --- | --- |
| `0001` | Higher API rate limit (kept from the previous package) |
| `0002` | Debug output on S3 errors (kept) |
| `0003` | Self-hosted S3 with separate endpoints: `S3_ENDPOINT` for server-side calls, `S3_PUBLIC_URL` for upload URLs and presigned download URLs. Replaces the old patches `0002`/`0004` and the rinetd port forward. |
| `0004` | DynamoDB and Elasticsearch optional: skipped when `FULLTEXT_INDEXING_TABLE` or `SEARCH_HOSTS` is empty |
| `0005` | Integer values for `content-length-range` in the S3 POST policy. Garage rejects strings, AWS accepts both. |
| `0007` | Zero-padded hour (`H` instead of `G`) in the S3 POST policy expiration. Before 10:00 UTC upstream produces `T7:15:49Z`, which Garage rejects as invalid. |
| `0006` | File viewing (`/file/view`, `/file/view/url`) returns a presigned S3 URL when `ATTACHMENT_PROXY_URL` is empty. zotero.org uses an attachment proxy that isn't public. Without the patch the URL is relative, and the web-library's PDF viewer gets HTML (`Invalid PDF structure`). |

`utils/patch.sh --check` tests whether the patches still apply. `utils/update.sh` runs it after moving the submodules.

### AWS services

| zotero.org uses | Here |
| --- | --- |
| Amazon S3 | Garage. Any S3-compatible store with SigV4 presigned URLs and POST policy uploads should work. |
| DynamoDB | Not used (patch `0004`). It only tracks the state of zotero.org's full-text indexer. |
| Elasticsearch + indexer Lambda | Not used (patch `0004`). Upstream fills the index with an external Lambda that isn't open source. The previous package ran Elasticsearch, but its index was never filled. |
| SNS | Not used (`SNS_ALERT_TOPIC` empty) |
| SQS | Not used (`REINDEX_QUEUE_URL` empty) |

### Configuration

- **`.env`:** created by `utils/setup-env.sh` with random secrets. Compose passes the values to the containers, and `config.inc.php`/`dbconnect.inc.php` read them with `getenv()`. Credentials are no longer hardcoded (the old default was `zotero`/`zoterodocker`/`admin`).
- **`BASE_URI`:** now fixed to `http://zotero.org/`. It is the object URI namespace, not a URL, and must match `ZOTERO_CONFIG.BASE_URI` in the client. The previous value `http://localhost:8080` (no trailing slash) produced URIs like `http://localhost:8080users/1`.
- **Ports:** configurable, bound to `BIND_ADDRESS` (default `127.0.0.1`). Defaults changed from 8080–8083 to 8180–8184.
- **MySQL:** configured after upstream's `misc/mysql_parameters`, with `sql_mode = STRICT_ALL_TABLES` and utf8mb4. The previous `sql_mode = ''` workaround and `innodb_large_prefix` (removed in MySQL 8) are gone.
- **Apache in the dataserver:** `include_path` must contain `include/` and `auto_prepend_file` must point to `include/header.inc.php`. Without them every API request fails.
- **Shared group:** only with `SHARED_GROUP_OWNER=<email>`. Then a group named `DEFAULT_GROUP_NAME` is created once (or an existing one of that name adopted), read-only for members and owned by the user with that email; if they don't exist yet, the portal hands the group over on their first login. New users join it as members. Afterwards it's managed like any other group (`bin/set-group-role.sh`); its ID is kept in `zotero_selfhost.settings`.
- **Storage quota:** new users get `ZOTERO_STORAGE_QUOTA_MB` (default unlimited) instead of the dataserver default of 300 MB.

### Database setup

`config/dataserver-scripts/init-mysql.sh` is rewritten:

- **Explicit column lists.** The positional inserts broke with the current schema, e.g. `users` now has 3 columns instead of 5.
- **More SQL files.** It also loads `events.sql` and creates two shards.
- **`admin/schema_update` at the end.** Without it every item type except notes fails with `Field '…' from schema 0 not found`.

`www.sql` is fixed:

- The password column fits bcrypt hashes.
- It adds the missing `users_email.validated` column, which the quota queries need.
- `domainBlacklist` gets a default.

New users get bcrypt passwords instead of MD5.

### Database migrations and legacy import

Two one-shot services run before the dataserver, next to the `init-data` provisioner:

- **`db-migrate`** (dataserver image, `config/dataserver-scripts/migrate.sh`), after MySQL is healthy:
  1. **Legacy import:** if `data/legacy/legacy.sql.gz` exists and hasn't been imported, it backs up the current
     databases and replaces them with the dump. MySQL 5.7 modes that 8.4 rejects are removed on the fly.
  2. **Migrations:** each step checks the database itself (columns, indexes, tables) and only runs when something
     is missing. That makes it work from any older state. Tested: a 2021 database (dataserver `3190eb1`) on
     MySQL 5.7, exported, imported into 8.4 and migrated. The result matches a fresh schema in columns, foreign keys,
     triggers and events. The only differences are where upstream's `master.sql` lags behind its own `db-updates`.
  3. **Backup first:** before the first change, a full dump goes to `data/backups/zotero-before-migration-<time>.sql.gz`.
     Without pending steps nothing is dumped.
  4. Applied steps are logged in `zotero_selfhost.migrations`. Triggers and events are re-applied when the upstream
     files change (their hash is part of the step ID). Finally `admin/schema_update` runs if the zotero-schema is newer.
  5. A failure stops the start: the dataserver and portal depend on `db-migrate` completing successfully.
- **`s3-import`** (aws-cli): uploads `data/legacy/s3/<bucket>/` into Garage once. `bin/init.sh` runs it again
  after creating the buckets.

The steps cover upstream `misc/db-updates/` from 2020-08-31 to 2026-04-08, this package's `www.sql` changes, and
latin1 → utf8mb4 for databases created on MySQL 5.7. Not included is the data cleanup
`2026-07-21/stripStoredFileAttachmentPaths`; it can be run by hand (dry run without arguments, `apply` to write).

**Upgrading an installation of the previous package** (in the same checkout, old stack still there):

```sh
git pull
git submodule sync && git submodule update --init --recursive
utils/setup-env.sh <public-host>   # new .env; the old stack had no .env
sudo legacy/export.sh              # old DB and files -> data/legacy/
sudo docker compose up -d --build  # db-migrate imports and migrates the database
sudo bin/init.sh                   # Garage setup, s3-import uploads the files
sudo utils/smoke-test.py
```

- **Why an export and not just the old data paths:** the old stack kept MySQL and MinIO data in anonymous
  volumes of its containers, not in paths of the checkout, and MySQL 8.4 can't open a 5.7 data directory.
  `legacy/export.sh` finds the old containers by their Compose labels (starting them if stopped), dumps all
  `zotero_*` databases and copies the bucket files. The old `docker-compose.yml` is not needed any more.
- **Old and new stack don't collide:** the new stack has its own project name (`zotero`) and ports (8180–8184),
  so the old containers can keep running until the export is done. Afterwards stop them
  (`docker stop` on the old containers). Their volumes stay as a fallback until the old containers are removed.
- The old MySQL password was `zotero`; `OLD_MYSQL_PASSWORD=... legacy/export.sh` if it was changed.
- Old MinIO versions store objects as plain files. If the export finds MinIO's newer format, it stops;
  copy the buckets with an S3 client into `data/legacy/s3/<bucket>/` instead.
- Old accounts keep their passwords (MD5 is still accepted). On the first Keycloak login, the portal links the
  Keycloak account to the old Zotero user with the same email address. Without a matching email it creates a new,
  empty account, so check the emails of old users (`bin/list-user.sh`) before the first login.

**Restore a backup:** `zcat data/backups/<file>.sql.gz | docker compose exec -T mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'`.

### tinymce-clean

The current dataserver still calls this service (`HTMLCLEAN_SERVER_URL`, `model/Notes.inc.php`).
The cleaning logic (`lib/utils.js`, `tinymce.html` 4.5.2) is reused unchanged, so stored notes look
the same as before. Only the Koa 1 server is replaced by Node's built-in `http` module
(`docker/tinymce-clean/server.js`). The original tests run during the image build.

### stream-server

Uses upstream's `config/default.js`, with only local overrides in `config/stream-server.js`.
Upstream switched to `redis` v4, which needs a `redis.url` setting.

### web-library

- **No code patches.** Everything is set through the JSON config (API host and scheme, website URL, streaming URL, API key).
- The previous patch rewriting `zotero.org` in relation URIs is wrong once `BASE_URI` is correct, so it was dropped.
- **Built from a git clone of the submodule's commit** (`WEB_LIBRARY_COMMIT`), because its build script needs the submodules' git metadata.
- The build downloads fonts, style lists and prebuilt reader and note-editor modules from zotero.org and GitHub.

### Desktop client

The client now runs on Firefox ESR instead of XULRunner. The build steps in the previous README
(`fetch_xulrunner.sh`, `dir_build`, editing `zotero.jar`) no longer apply.

The official client works if two preferences are set:

- `extensions.zotero.api.url`
- `extensions.zotero.streaming.url`

Login, sync and streaming read these preferences in place of the hardcoded values. The previous
`zfs.js` patch for file uploads isn't needed any more, because the dataserver now hands out
`S3_PUBLIC_URL` itself. If a custom build is ever needed, use `npm run build` and `app/scripts/dir_build`
in the client repository.

### portal (optional, new)

Current clients log in through the browser:

1. `POST /keys/sessions` returns a `loginURL`.
2. The client opens it in the browser and waits.
3. The website completes the session through the super-user endpoint `/keys/sessions/complete`.

On zotero.org, zotero.org itself is that website. Here the `portal` service takes that role:

- **Login:** OpenID Connect against any provider (`OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`).
- **User provisioning:** a Zotero user is created on first login and linked through the OIDC `sub` in `zotero_www.users_meta`. An unlinked local account with the same email is taken over.
- **web-library:** served per user with an API key of their own.
- **Desktop login:**
  - The user has to confirm explicitly on the `/login?session=…` page, which carries a CSRF token.
  - A session tied to another account is rejected.
- **Several logins at once** (tabs, reloads) keep their own `state` and `nonce` and don't interfere.
- **Private network for super-user calls:** the dataserver only accepts super-user requests from private addresses. portal and dataserver therefore share an internal network with an RFC 1918 subnet (`10.203.77.0/28`). If the default Docker network is private too, requests coming in through a reverse proxy on the host would also count as private. Check this for your Docker address pools.

### Scripts

| Script | Purpose |
| --- | --- |
| `utils/setup-env.sh [host]` | Create `.env` with random secrets |
| `bin/init.sh` | One-time Garage setup (layout, key, buckets) and database initialization |
| `bin/create-user.sh`, `bin/create-group.sh`, `bin/list-user.sh` | Manage users and groups by hand |
| `bin/delete-user.sh` | Delete a user with library data, API keys and OIDC link |
| `bin/set-group-role.sh` | Make a group member `admin` (can write in read-only groups) or `member` |
| `bin/create-api-key.sh` | Create an API key with username and password |
| `utils/update.sh [name ref \| --verify]` | Show pinned and upstream versions, pin a submodule to a tag or commit (checks patches, updates `versions.lock` and `WEB_LIBRARY_COMMIT`) |
| `utils/patch.sh [--check]` | Test the patches or apply them to the dataserver submodule |
| `utils/smoke-test.py [--public]` | End-to-end check with 21 checks, `--public` goes through the client-facing URLs |

## Previous README: what still applies

| Section of the previous README | Status |
| --- | --- |
| "the Zotero eco-system", "important concepts" | Still accurate as background. Removed from README.md for brevity. |
| MySQL 5.7 and `sql_mode` workaround | Replaced by MySQL 8.4 with upstream's parameters |
| Ubuntu 18.04 base image, packages from the distribution | Replaced by official `php`, `node` and `nginx` images |
| `git clone --recursive`, then `./utils/patch.sh` | Clone recursively. Patches are now applied at build time, and `utils/patch.sh` is only for development. |
| `./bin/init.sh` after `docker-compose up` | Still the flow. It now sets up Garage instead of MinIO and LocalStack. |
| Endpoints 8080–8083, default logins `admin`/`admin`, `zotero`/`zoterodocker`, `root`/`zotero` | Replaced by ports 8180–8184 and random secrets in `.env` |
| "Client installation": patching `resource/config.js` and `zfs.js`, XULRunner build | Obsolete. Use the official client with two preferences. |
| "deployment": reverse proxy for internet use | Still recommended. The S3 host must be proxied with the `Host` header preserved and the path unchanged, because it is part of the signatures. |
| "server management": `create-user.sh {UID} {username} {password}` | Replaced by `bin/create-user.sh <username> <password> <email>` (automatic IDs, bcrypt) and the portal |
| TODO: web-library and user management | Done through the portal |

## Issues found during the upgrade

| Symptom | Cause | Fix |
| --- | --- | --- |
| `git submodule update` hangs | GitHub turned off `git://` in 2022, and nested submodules still use it | `git config --global url."https://github.com/".insteadOf git://github.com/` |
| `pull access denied for minio/minio` | MinIO no longer publishes community images | Garage |
| S3 upload: `Invalid policy item` | `content-length-range` sent as strings | Patch `0005` |
| Creating items returns 500: `Field 'eventPlace' from schema 0 not found` | Field tables not updated to the current schema | `schema_update` in `init-mysql.sh` |
| `mysql`: `TLS/SSL error: self-signed certificate` | The MariaDB client verifies MySQL 8.4's auto-generated certificate | `skip-ssl-verify-server-cert` for the internal network. The connection stays encrypted. |
| Every request: `Failed opening required 'config/routes.inc.php'` | `include_path` not set | Apache vhost config |
| Every request: `Undefined constant "Z_ENV_CONTROLLER_PATH"` | `auto_prepend_file` not set | Apache vhost config |
| Super-user requests from a container get 401 | The Docker address pool isn't RFC 1918 | Internal network with a private subnet |
| web-library: `Invalid configuration` | Neither `userId` nor libraries configured | Configured by the portal |
| OIDC: `Unable to determine state` | The library keeps one pending login per session | The portal tracks several pending logins |
| web-library PDF viewer: `Invalid PDF structure` | View URL points to the missing attachment proxy | Patch `0006` |
| web-library PDF viewer: module blocked, MIME type `application/octet-stream` | nginx's default `mime.types` lacks `.mjs` | `.mjs` and `.wasm` types in `docker/web-library/nginx.conf` |
| Attachments don't load in the web-library | No CORS on the S3 bucket | `bin/init.sh` sets bucket CORS for `WEB_LIBRARY_URL` |
| After updates the web-library behaves oddly | The browser caches `zotero-web-library.js` (fixed file name) | Clear the browser cache. Cache headers are still open. |

## Tests

`utils/smoke-test.py` passes all 21 checks, both locally and through a TLS reverse proxy (`--public`):

- Schema, login (including a wrong password)
- Items, notes (tinymce-clean), group library
- File upload to S3, registration, presigned download, byte comparison
- Full text
- Streaming push after a change
- Deletion
- web-library assets

The portal's provisioning and the desktop login session were tested directly against the API.
The OIDC login and the web-library were tested in a browser.

## Outlook

### Next

1. **End-to-end test with the desktop client:** browser login, sync, attachments, a second device.
2. ~~CORS on the S3 bucket~~: done, set by `bin/init.sh`.
3. **Cache headers** for web-library assets (`Cache-Control: no-cache` with ETag).
4. **Extend the smoke test to the portal:** OIDC redirect, confirmation page.
5. **Update README.md** for the portal: the web-library and desktop client sections still describe the fixed-key and password login.

### Operations

6. **Backups:** dump all Zotero databases and back up the Garage volume, then test a restore.
7. **Updates:** `utils/update.sh <name> <ref>`, `docker compose up -d --build`, `utils/smoke-test.py`.
   - `db-migrate` applies the known schema changes with a backup first. New files in
     `src/server/dataserver/misc/db-updates/` still need a new step in `migrate.sh`.
   - The Garage image is pinned and needs to be bumped by hand.
8. **Tidy up the submodule names in `.gitmodules`** (they still carry the old `server/…`/`client/…` names).

### Contributing back as a pull request

Not done yet. The aim is to prepare this work so it continues the original repository
([foxsen/zotero-selfhost](https://github.com/foxsen/zotero-selfhost)) as a clean pull request,
instead of living on as a diverging fork.

- **Split into reviewable commits**, for example:
  1. submodule updates and removal of the client submodules
  2. dataserver patches
  3. Docker restructuring (one image per service, Garage, Valkey, MySQL 8.4)
  4. configuration via `.env`
  5. database setup and scripts
  6. tinymce-clean replacement
  7. smoke test
  8. portal (optional, possibly a separate PR)
  9. documentation
- **Keep it deployment-neutral:**
  - no host names, no identity provider and no reverse proxy config of a specific site
  - a `.env.example` next to `utils/setup-env.sh`
  - the portal behind a Compose profile, so the base stack runs without an OIDC provider
- **Automatic database migrations:** done (`db-migrate`, see above). For the PR, a check in CI that every
  upstream `db-updates` directory has a matching step would keep it from falling behind.
- **Migration path for existing installations of the previous package:** done (`legacy/export.sh`,
  legacy import in `db-migrate`, `s3-import`).
- **CI:** build all images and run `utils/smoke-test.py` against a fresh stack, and ideally against a migrated 2021 database.
- **Release notes:** this document, shortened for the PR description.

### Optional

9. **Server-side full-text search:** an indexer that copies full text from S3/MySQL to Elasticsearch or OpenSearch, then enable `SEARCH_HOSTS`.
10. **Translation server** ([zotero/translation-server](https://github.com/zotero/translation-server)) for adding items by identifier in the web-library.
11. **Map OIDC roles or groups** to Zotero groups instead of adding every new user to group 1.
12. **Propose patch `0005`** (integer policy values) upstream, since it's valid for AWS as well.

## Known limitations

- No server-side full-text search. Full text is stored and synced, and clients search their local index.
- Client texts and links ("Sync with zotero.org", "Create group", "View online") still point to zotero.org. Groups are created with `bin/create-group.sh`.
- The web-library build pulls assets from zotero.org, and at runtime it loads citation styles from zotero.org.
- The server preferences have to be set in every client by hand.
