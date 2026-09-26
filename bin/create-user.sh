#!/bin/sh
# Usage: bin/create-user.sh <username> <password> <email>
cd "$(dirname "$0")/.."
exec docker compose exec -T dataserver /var/www/zotero/misc/create-user.sh "$@"
