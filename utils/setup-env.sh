#!/bin/sh
# Usage: utils/setup-env.sh [public-host]
# Creates .env with random secrets. public-host is the name or IP clients use to reach the server.
set -e
cd "$(dirname "$0")/.."

if [ -e .env ]; then
	echo ".env already exists, not overwriting" >&2
	exit 1
fi

HOST="${1:-localhost}"
hex() { od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'; }
pw() { hex 16; }

cat > .env <<EOF
# Host address and ports the services listen on.
# 127.0.0.1 = only reachable locally (e.g. behind a reverse proxy); 0.0.0.0 = all interfaces
BIND_ADDRESS=127.0.0.1
API_PORT=8180
STREAM_PORT=8181
S3_PORT=8182
WEB_LIBRARY_PORT=8183
PORTAL_PORT=8184

# URLs as reachable by clients -- change when running behind a reverse proxy
ZOTERO_API_URL=http://$HOST:8180
S3_PUBLIC_URL=http://$HOST:8182
STREAMING_URL=ws://$HOST:8181/
WEB_LIBRARY_URL=http://$HOST:8183
API_SCHEME=http
API_AUTHORITY=$HOST:8180

# Secrets
MYSQL_ROOT_PASSWORD=$(pw)
ZOTERO_AUTH_SALT=$(hex 16)
ZOTERO_SUPER_USER=admin
ZOTERO_SUPER_PASSWORD=$(pw)
# Garage requires key IDs of the form GK + 24 hex digits and 64 hex digit secrets
S3_ACCESS_KEY=GK$(hex 12)
S3_SECRET_KEY=$(hex 32)
GARAGE_RPC_SECRET=$(hex 32)

# First user, created by bin/init.sh
ZOTERO_ADMIN_USER=admin
ZOTERO_ADMIN_PASSWORD=$(pw)
ZOTERO_ADMIN_EMAIL=admin@localhost
# Storage quota per new user in MB (1000000 = unlimited)
ZOTERO_STORAGE_QUOTA_MB=1000000
# Group all new users join (created by bin/init.sh as group 1).
# DEFAULT_GROUP_EDITING=admins: members can only read, owner and admins can write
DEFAULT_GROUP_NAME=Shared
DEFAULT_GROUP_EDITING=members

# Keycloak login for the web-library and the desktop client (portal service)
OIDC_ISSUER=
OIDC_CLIENT_ID=zotero
OIDC_CLIENT_SECRET=

# Commit of src/server/web-library (see versions.lock), updated by utils/update.sh
WEB_LIBRARY_COMMIT=$(git -C src/server/web-library rev-parse HEAD)
EOF
chmod 600 .env
echo "Created .env for host '$HOST'"
