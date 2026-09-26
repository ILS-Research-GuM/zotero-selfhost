#!/bin/sh
# Usage: bin/set-group-role.sh <groupID> <username> <admin|member>
cd "$(dirname "$0")/.."
exec docker compose exec -T dataserver /var/www/zotero/misc/set-group-role.sh "$@"
