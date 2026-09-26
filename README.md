# Zotero Selfhost

A self-hosted Zotero sync server: the official [dataserver](https://github.com/zotero/dataserver),
[stream-server](https://github.com/zotero/stream-server) and [web-library](https://github.com/zotero/web-library),
packaged with Docker Compose and without any AWS dependency. The official Zotero desktop client
syncs against it after changing two settings, so no custom client build is needed. Login for the
web-library and the desktop client goes through any OpenID Connect provider (e.g. Keycloak).

Originally based on [zotero-prime](https://github.com/SamuelHassine/zotero-prime) and
[foxsen/zotero-selfhost](https://github.com/foxsen/zotero-selfhost). Coming from an installation of the
previous package: see [Upgrading from the 2021 package](#upgrading-from-the-2021-package) and
[README-upgrade.md](README-upgrade.md) for all changes.

## Services

| Service | Image | Purpose |
| --- | --- | --- |
| `dataserver` | built, PHP 8.4 + Apache | Zotero API (sync, login, files) |
| `stream-server` | built, Node 22 | WebSocket push notifications |
| `web-library` | built, nginx | Static files of the browser UI |
| `portal` | built, PHP 8.4 | OIDC login, per-user web-library page, desktop client browser login |
| `tinymce-clean` | built, Node 22 | Sanitizes note HTML for the dataserver |
| `mysql` | `mysql:8.4` | Master, shard, ID and user databases |
| `garage` | `dxflrs/garage` | S3-compatible file storage |
| `redis` | `valkey/valkey` | Rate limits and notifications |
| `memcached` | `memcached` | Cache |

One-shot services that run on every `docker compose up` before the others:

| Service | Purpose |
| --- | --- |
| `init-data` | Creates the directories under `data/` with the owners the services run as |
| `db-migrate` | Backs up and migrates the databases to the schema of the built dataserver; imports a legacy dump once |
| `s3-import` | Uploads the files of a legacy export into Garage once |

What the dataserver uses on zotero.org, and what replaces it here:

| zotero.org | Here |
| --- | --- |
| Amazon S3 | Garage. Any S3-compatible store that supports POST policy uploads works (`S3_ENDPOINT`, `S3_PUBLIC_URL`) |
| DynamoDB (full-text index state) | Not used (`FULLTEXT_INDEXING_TABLE` empty) |
| Elasticsearch + indexer Lambda | Not used (`SEARCH_HOSTS` empty). Clients search their local full-text index |
| SNS / SQS | Not used |
| zotero.org website (login, account) | `portal` with an OIDC provider |

## Layout

- `src/server/*`: upstream sources as git submodules, unmodified; versions in `versions.lock`
- `src/patches/dataserver/`: changes to the dataserver, applied at image build time
- `docker/*/`: one image per service, plus the one-shot service scripts
- `config/`: dataserver, Apache, PHP, MySQL, Garage and stream-server configuration
- `config/dataserver-scripts/`: database setup, migrations and user management, copied into the dataserver image
- `bin/`: day-to-day operations
- `utils/`: setup, updates, patch check and smoke test
- `legacy/`: export from installations of the previous package
- `data/` (not in git): MySQL, Garage, backups, dataserver error logs, legacy import

## Installation

Requires Docker with the Compose plugin. Run the commands as a user allowed to use Docker (or with `sudo`).

```bash
git clone --recursive <repository url> zotero-selfhost && cd zotero-selfhost
./utils/setup-env.sh zotero.example.org   # host name clients use; creates .env with random secrets
# edit .env: public URLs, OIDC_* (see below), DEFAULT_GROUP_NAME, SHARED_GROUP_OWNER
docker compose up -d --build
./bin/init.sh                             # one-time: S3 buckets and CORS, databases, admin user, default group
./utils/smoke-test.py                     # optional end-to-end check
./utils/smoke-test.py --public            # same via the client-facing URLs (tests the reverse proxy)
```

`bin/init.sh` keeps existing databases; `bin/init.sh --force` recreates them and deletes all data.

By default all ports listen on `127.0.0.1` only (`BIND_ADDRESS` in `.env`):

| Port | Service | Client-facing URL in `.env` |
| --- | --- | --- |
| 8180 | API | `ZOTERO_API_URL` |
| 8181 | Streaming | `STREAMING_URL` |
| 8182 | S3 | `S3_PUBLIC_URL` |
| 8183 | web-library (static files) | `WEB_LIBRARY_URL` + `/static/` |
| 8184 | portal | `WEB_LIBRARY_URL` |

Put a reverse proxy with TLS in front of the ports, e.g. one host name each for API, streaming, S3 and the
web interface. On the web interface host, route `/static/` to port 8183 and everything else to 8184.
Set the URLs in `.env` (plus `API_SCHEME`/`API_AUTHORITY`) to the proxied addresses.

- The streaming host needs WebSocket forwarding.
- Clients must reach `S3_PUBLIC_URL` under exactly that host name, because upload and download URLs are
  signed for it. Keep the `Host` header, don't re-encode the path, and allow large request bodies.
- The portal needs HTTPS, since its session cookie is marked secure.

After changing `.env`, run `docker compose up -d`. If `WEB_LIBRARY_URL` changes, run `bin/init.sh` again to
update the S3 CORS rules.

## Login (OIDC)

The portal signs users in with an OpenID Connect provider. Create a confidential client there with the
redirect URI `<WEB_LIBRARY_URL>/oidc/callback` and set in `.env`:

```bash
OIDC_ISSUER=https://id.example.org/realms/example
OIDC_CLIENT_ID=zotero
OIDC_CLIENT_SECRET=...
```

- On the first login the portal creates a Zotero user with its own library, named after `preferred_username`.
  An existing local user with the same email that isn't linked yet is taken over instead.
- The web-library page is generated per user, with an API key of that user.
- The desktop client's "Log In" opens `<WEB_LIBRARY_URL>/login` in the browser; after the OIDC login the user
  confirms the connection, and the client receives its API key.
- Every user who can log in at the provider gets an account; restrict access in the provider if needed.

## Users and groups

Users are normally created by the portal on first login. By hand:

```bash
./bin/create-user.sh <username> <password> <email>   # also joins the default group
./bin/list-user.sh
./bin/delete-user.sh <userID>                         # with library, API keys and OIDC link
./bin/create-group.sh <name> <owner-username> [members|admins]
./bin/set-group-role.sh <groupID> <username> <admin|member>
./bin/create-api-key.sh <username> <password> [key-name]
```

- Every new user joins group 1 as a member. `bin/init.sh` creates it as `DEFAULT_GROUP_NAME`.
- Without `SHARED_GROUP_OWNER` all members can write.
- `SHARED_GROUP_OWNER=<email>` makes the group read-only for members and binds it to the user with that email:
  they become its owner and can write. If that user doesn't exist yet, they become owner on their first login.
  The setting is applied on every start (`db-migrate`); the previous owner becomes admin.
  Further writers: `bin/set-group-role.sh <groupID> <username> admin`.
- Storage quota for new users comes from `ZOTERO_STORAGE_QUOTA_MB` (default: unlimited).

## Desktop client

Use the official Zotero client. In Settings → Advanced → Config Editor set:

| Preference | Value |
| --- | --- |
| `extensions.zotero.api.url` | `ZOTERO_API_URL` with trailing `/`, e.g. `https://api.zotero.example.org/` |
| `extensions.zotero.streaming.url` | `STREAMING_URL`, e.g. `wss://stream.zotero.example.org/` |

Restart Zotero, then click "Log In" under Settings → Account (older versions: Sync). The browser opens the
portal login. Texts such as "Sync with zotero.org" and links to the zotero.org website stay unchanged.

## Data and backups

All state is in bind mounts under `data/`, so a file-level backup of that directory (with the stack stopped,
or a MySQL dump plus `data/garage/`) is enough.

- `data/mysql/`: databases
- `data/garage/`: attachment files and full text
- `data/backups/`: dumps written by `db-migrate` before every schema change (root only)
- `data/legacy/`: legacy export to import (see below)

Restore a dump:

```bash
zcat data/backups/<file>.sql.gz | docker compose exec -T mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'
```

## Updating

Upstream sources are pinned: web-library to a release tag, dataserver, stream-server and tinymce-clean-server
(which have no release tags) to a master commit. The pins are in `versions.lock` and the submodule pointers.

```bash
./utils/update.sh                           # pinned versions and what upstream offers
./utils/update.sh dataserver master         # pin a submodule to a tag, branch or commit; checks the patches
./utils/update.sh web-library v1.8.3
docker compose up -d --build                # db-migrate migrates the databases, with a backup first
./utils/smoke-test.py
```

`db-migrate` checks every known schema change against the database and applies what is missing, so it works
from any older version. When upstream adds a new directory to `src/server/dataserver/misc/db-updates/`, add a
matching step to `config/dataserver-scripts/migrate.sh`. New item types and fields are applied automatically
(`admin/schema_update`).

To change a patch, check out the `selfhost` branch in `src/server/dataserver` (or apply the patches
with `utils/patch.sh`), commit, and regenerate the files with `git format-patch -o ../../patches/dataserver origin/master`.

## Upgrading from the 2021 package

In the same checkout, with the old containers still present:

```bash
git pull
git submodule sync && git submodule update --init --recursive
./utils/setup-env.sh <public-host>
sudo legacy/export.sh               # old databases and MinIO files -> data/legacy/
docker compose up -d --build        # db-migrate imports and migrates the database
./bin/init.sh                       # Garage setup; s3-import uploads the files
```

The old stack kept its data in anonymous container volumes, and MySQL 8.4 can't open a 5.7 data directory,
so `legacy/export.sh` dumps the databases and copies the files first. Details in [README-upgrade.md](README-upgrade.md).

## Known limitations

- No server-side full-text search (web-library "All Fields & Tags + full text"). Full text is stored and synced.
- No self-service registration beyond what the OIDC provider allows.
- The web-library downloads fonts, styles and prebuilt reader and note-editor modules from zotero.org at image build time,
  and citation styles at runtime.
- Translation server (adding items by identifier in the web-library) is not included.
