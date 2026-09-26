#!/bin/sh
cd "$(dirname "$0")/.."
exec docker compose exec -T dataserver /var/www/zotero/misc/list-user.sh
