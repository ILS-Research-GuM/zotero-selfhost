#!/bin/sh
# Usage: bin/create-group.sh <name> <owner-username>
cd "$(dirname "$0")/.."
exec docker compose exec -T dataserver /var/www/zotero/misc/create-group.sh "$@"
