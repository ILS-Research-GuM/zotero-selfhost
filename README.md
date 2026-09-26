# Zotero Selfhost

A self-hosted Zotero sync server: the official [dataserver](https://github.com/zotero/dataserver),
[stream-server](https://github.com/zotero/stream-server) and [web-library](https://github.com/zotero/web-library),
packaged with Docker Compose and without any AWS dependency. The official Zotero desktop client
syncs against it after changing two settings, so no custom client build is needed.

Originally based on [zotero-prime](https://github.com/SamuelHassine/zotero-prime) and
[foxsen/zotero-selfhost](https://github.com/foxsen/zotero-selfhost).

## Services

| Service | Image | Purpose |
| --- | --- | --- |
| `dataserver` | built, PHP 8.4 + Apache | Zotero API (sync, login, files) |
| `stream-server` | built, Node 22 | WebSocket push notifications |
| `web-library` | built, nginx | Browser UI (optional) |
| `tinymce-clean` | built, Node 22 | Sanitizes note HTML for the dataserver |
| `mysql` | `mysql:8.4` | Master, shard, ID and user databases |
| `garage` | `dxflrs/garage` | S3-compatible file storage |
| `redis` | `valkey/valkey` | Rate limits and notifications |
| `memcached` | `memcached` | Cache |

What the dataserver uses on zotero.org, and what replaces it here:

| zotero.org | Here |
| --- | --- |
| Amazon S3 | Garage. Any S3-compatible store that supports POST policy uploads works (`S3_ENDPOINT`, `S3_PUBLIC_URL`) |
| DynamoDB (full-text index state) | Not used (`FULLTEXT_INDEXING_TABLE` empty) |
| Elasticsearch + indexer Lambda | Not used (`SEARCH_HOSTS` empty). Clients search their local full-text index |
| SNS / SQS | Not used |

## Layout

- `src/server/*`: upstream sources as git submodules, unmodified
- `src/patches/dataserver/`: changes to the dataserver, applied at image build time
- `docker/*/Dockerfile`: one image per service
- `config/`: dataserver, Apache, PHP, MySQL, Garage and stream-server configuration
- `config/dataserver-scripts/`: database setup and user management, copied into the dataserver image
- `bin/`: day-to-day operations
- `utils/`: setup, updates, patch check and smoke test

## Installation

Requires Docker with the Compose plugin. Run the commands as a user allowed to use Docker (or with `sudo`).

```bash
git clone --recursive <repository url> zotero-selfhost && cd zotero-selfhost
./utils/setup-env.sh zotero.example.org   # host name clients use; creates .env with random secrets
docker compose up -d --build
./bin/init.sh                             # one-time: S3 buckets, databases, admin user, "Shared" group
./utils/smoke-test.py                     # optional end-to-end check
./utils/smoke-test.py --public            # same via the client-facing URLs (tests the reverse proxy)
```

By default all ports listen on `127.0.0.1` only (`BIND_ADDRESS` in `.env`):

| Port | Service | Client-facing URL in `.env` |
| --- | --- | --- |
| 8180 | API | `ZOTERO_API_URL` |
| 8181 | Streaming | `STREAMING_URL` |
| 8182 | S3 | `S3_PUBLIC_URL` |
| 8183 | web-library | `WEB_LIBRARY_URL` |

For access from other machines, put a reverse proxy with TLS in front of the ports and set the four URLs
(plus `API_SCHEME`/`API_AUTHORITY`) to the proxied addresses, or set `BIND_ADDRESS=0.0.0.0`.
Clients must reach `S3_PUBLIC_URL` under exactly that host name, because download URLs are signed for it.
After changing `.env`, run `docker compose up -d`.

## Users and groups

```bash
./bin/create-user.sh <username> <password> <email>   # also joins the "Shared" group
./bin/create-group.sh <name> <owner-username>
./bin/list-user.sh
./bin/create-api-key.sh <username> <password> [key-name]
```

Storage quota for new users comes from `ZOTERO_STORAGE_QUOTA_MB` (default: unlimited).

## Desktop client

Use the official Zotero client. In Settings → Advanced → Config Editor set:

| Preference | Value |
| --- | --- |
| `extensions.zotero.api.url` | `ZOTERO_API_URL` with trailing `/`, e.g. `https://api.zotero.example.org/` |
| `extensions.zotero.streaming.url` | `STREAMING_URL`, e.g. `wss://stream.zotero.example.org/` |

Restart Zotero, then log in under Settings → Sync with a user created above. Texts such as
"Sync with zotero.org" and links to the zotero.org website stay unchanged.

## web-library

The web-library shows a single configured library. Create a key with `bin/create-api-key.sh`, put
`WEB_LIBRARY_USER_ID`, `WEB_LIBRARY_USER_SLUG` and `WEB_LIBRARY_API_KEY` into `.env` and run
`docker compose up -d web-library`. The key is embedded in the page, so protect the web-library
(e.g. with authentication in the reverse proxy).

## Updating

```bash
./utils/update.sh          # moves submodules to upstream HEAD and checks that the patches still apply
docker compose up -d --build
./utils/smoke-test.py
```

Schema changes of the dataserver are in `src/server/dataserver/misc/db-updates/` and must be applied
to existing databases by hand. New item types and fields: `docker compose exec -w /var/www/zotero/admin dataserver php schema_update`.

To change a patch, check out the `selfhost` branch in `src/server/dataserver` (or apply the patches
with `utils/patch.sh`), commit, and regenerate the files with `git format-patch -o ../../patches/dataserver origin/master`.

## Known limitations

- No server-side full-text search (web-library "All Fields & Tags + full text"). Full text is stored and synced.
- No web registration or login page. Users are created with `bin/create-user.sh`.
- The web-library downloads fonts, styles and prebuilt reader and note-editor modules from zotero.org at image build time,
  and citation styles at runtime. Uploading files from the web-library needs CORS on the S3 bucket.
- Translation server (adding items by identifier in the web-library) is not included.
