#!/bin/sh
# Usage: bin/delete-user.sh <userID>   (see bin/list-user.sh)
cd "$(dirname "$0")/.."
exec docker compose exec -T dataserver /var/www/zotero/misc/delete-user.sh "$@"
