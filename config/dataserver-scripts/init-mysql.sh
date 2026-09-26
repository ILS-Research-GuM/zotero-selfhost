#!/bin/sh
# Creates all dataserver databases from scratch. Destroys existing data.
set -e
cd "$(dirname "$0")"

export MYSQL_PWD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD not set}"
MYSQL="mysql -h ${MYSQL_HOST:-mysql} -u root"

for db in zotero_master zotero_shard_1 zotero_shard_2 zotero_ids zotero_www; do
	echo "DROP DATABASE IF EXISTS $db; CREATE DATABASE $db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" | $MYSQL
done

$MYSQL zotero_master < master.sql
$MYSQL zotero_master < coredata.sql
$MYSQL zotero_master < events.sql

for db in zotero_shard_1 zotero_shard_2; do
	$MYSQL $db < shard.sql
	$MYSQL $db < triggers.sql
done

$MYSQL zotero_ids < ids.sql
$MYSQL zotero_www < www.sql

$MYSQL zotero_master <<'EOF'
INSERT INTO shardHosts (shardHostID, address, port, state) VALUES (1, 'mysql', 3306, 'up');
INSERT INTO shards (shardID, shardHostID, db, state) VALUES
	(1, 1, 'zotero_shard_1', 'up'),
	(2, 1, 'zotero_shard_2', 'up');
EOF

# Add item types and fields of the current zotero-schema
(cd ../admin && php schema_update > /dev/null 2>&1)

./create-user.sh "${ZOTERO_ADMIN_USER:-admin}" "${ZOTERO_ADMIN_PASSWORD:?ZOTERO_ADMIN_PASSWORD not set}" "${ZOTERO_ADMIN_EMAIL:-admin@localhost}"
# Group every new user joins as member
./create-group.sh "${DEFAULT_GROUP_NAME:-Shared}" "${ZOTERO_ADMIN_USER:-admin}"
