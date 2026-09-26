#!/bin/sh
# One-time setup after the first "docker compose up -d": S3 storage and databases.
# Re-running it recreates the databases and deletes all data in them.
set -e
cd "$(dirname "$0")/.."
. ./.env

DC="docker compose"
garage() { $DC exec -T garage /garage "$@"; }

echo "Setting up Garage..."
NODE_ID=$(garage node id -q | cut -d@ -f1)
if ! garage layout show | grep -q "$(echo "$NODE_ID" | cut -c1-16)"; then
	garage layout assign -z dc1 -c 100G "$NODE_ID"
	garage layout apply --version 1
fi
garage key info "$S3_ACCESS_KEY" >/dev/null 2>&1 \
	|| garage key import --yes -n zotero "$S3_ACCESS_KEY" "$S3_SECRET_KEY"
for bucket in zotero zotero-fulltext; do
	garage bucket info "$bucket" >/dev/null 2>&1 || garage bucket create "$bucket"
	garage bucket allow --read --write --owner "$bucket" --key "$S3_ACCESS_KEY"
done

echo "Setting up databases..."
$DC exec -T dataserver /var/www/zotero/misc/init-mysql.sh

echo "Done."
