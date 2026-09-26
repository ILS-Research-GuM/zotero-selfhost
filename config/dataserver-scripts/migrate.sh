#!/bin/bash
# Brings the databases to the schema of the dataserver in this image. Runs as the one-shot
# service db-migrate before the dataserver starts, and can be run again any time.
#
# 1. Legacy import: if /legacy/legacy.sql.gz (or .sql) exists and was not imported yet, it
#    replaces all zotero_* databases (after a backup of the current ones).
# 2. Migrations: every step checks the database itself and only runs when something is
#    missing, so it works from any older version (tested from the 2021 schema). Before the
#    first change a full dump goes to /backups. Applied steps are logged in
#    zotero_selfhost.migrations.
# 3. The item types and fields of the bundled zotero-schema (admin/schema_update).
#
# A fresh stack without databases is left alone; bin/init.sh creates them.
set -euo pipefail
cd "$(dirname "$0")"
umask 077  # dumps contain password hashes

export MYSQL_PWD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD not set}"
HOST="${MYSQL_HOST:-mysql}"
BACKUP_DIR=/backups
LEGACY_DIR=/legacy
# Session like the old servers: no strict mode, so ALTERs accept the old zero dates
mysql_() { mysql -h "$HOST" -u root --init-command="SET SESSION sql_mode=''" "$@"; }
q() { mysql_ -N -B "$1" -e "$2"; }
log() { echo "[db-migrate] $*"; }

has_db() { [ -n "$(q information_schema "SELECT 1 FROM SCHEMATA WHERE SCHEMA_NAME='$1'")" ]; }
has_table() { [ -n "$(q information_schema "SELECT 1 FROM TABLES WHERE TABLE_SCHEMA='$1' AND TABLE_NAME='$2'")" ]; }
has_col() { [ -n "$(q information_schema "SELECT 1 FROM COLUMNS WHERE TABLE_SCHEMA='$1' AND TABLE_NAME='$2' AND COLUMN_NAME='$3'")" ]; }
col() { q information_schema "SELECT $4 FROM COLUMNS WHERE TABLE_SCHEMA='$1' AND TABLE_NAME='$2' AND COLUMN_NAME='$3'"; }
# An index whose first column is $3
has_index_on() { [ -n "$(q information_schema "SELECT 1 FROM STATISTICS WHERE TABLE_SCHEMA='$1' AND TABLE_NAME='$2' AND COLUMN_NAME='$3' AND SEQ_IN_INDEX=1 LIMIT 1")" ]; }
has_index() { [ -n "$(q information_schema "SELECT 1 FROM STATISTICS WHERE TABLE_SCHEMA='$1' AND TABLE_NAME='$2' AND INDEX_NAME='$3' LIMIT 1")" ]; }

backup() {
	mkdir -p "$BACKUP_DIR"
	local file="$BACKUP_DIR/zotero-$1-$(date -u +%Y%m%d-%H%M%S).sql.gz"
	local dbs
	dbs=$(q information_schema "SELECT SCHEMA_NAME FROM SCHEMATA WHERE SCHEMA_NAME LIKE 'zotero\\_%'")
	log "Backup of $(echo $dbs) to $file"
	mysqldump -h "$HOST" -u root --single-transaction --routines --triggers --events --databases $dbs \
		| gzip > "$file.tmp"
	gzip -t "$file.tmp"
	mv "$file.tmp" "$file"
}

# --- 1. Legacy import --------------------------------------------------------------------

import_legacy() {
	local dump
	dump=$(ls "$LEGACY_DIR"/legacy.sql.gz "$LEGACY_DIR"/legacy.sql 2>/dev/null | head -1 || true)
	[ -n "$dump" ] && [ ! -e "$LEGACY_DIR/.imported" ] || return 0

	has_db zotero_master && backup before-legacy-import
	for db in $(q information_schema "SELECT SCHEMA_NAME FROM SCHEMATA WHERE SCHEMA_NAME LIKE 'zotero\\_%'"); do
		q information_schema "DROP DATABASE \`$db\`"
	done
	log "Importing $dump"
	# MySQL 8 rejects the NO_AUTO_CREATE_USER mode that 5.7 dumps set for triggers
	{ case "$dump" in *.gz) zcat "$dump" ;; *) cat "$dump" ;; esac; } \
		| sed -e 's/NO_AUTO_CREATE_USER,//g; s/,NO_AUTO_CREATE_USER//g; s/NO_AUTO_CREATE_USER//g' \
		| mysql_
	date -u +%FT%TZ > "$LEGACY_DIR/.imported"
	log "Legacy import done"
}

# --- 2. Migrations -----------------------------------------------------------------------
# Each migration has check_<name> <db> (success when already in place) and
# apply_<name> <db>. The scope decides which databases it runs on.

# all databases

# Databases from MySQL 5.7 default to latin1, which tables without explicit charset inherited
latin1_tables() { q information_schema "SELECT TABLE_NAME FROM TABLES WHERE TABLE_SCHEMA='$1' AND TABLE_COLLATION LIKE 'latin1%'"; }
check_utf8mb4_default() {
	[ "$(q information_schema "SELECT DEFAULT_CHARACTER_SET_NAME FROM SCHEMATA WHERE SCHEMA_NAME='$1'")" = utf8mb4 ] \
		&& [ -z "$(latin1_tables $1)" ]
}
apply_utf8mb4_default() {
	local t
	q $1 "ALTER DATABASE \`$1\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
	for t in $(latin1_tables $1); do
		q $1 "ALTER TABLE \`$t\` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
	done
}

# master

check_libraries_hasData() { has_col $1 libraries hasData && ! has_col $1 libraries lastUpdated && ! has_col $1 libraries version; }
apply_libraries_hasData() {
	has_col $1 libraries hasData || q $1 "ALTER TABLE libraries ADD hasData TINYINT(1) NOT NULL DEFAULT 0 AFTER shardID, ADD INDEX (hasData)"
	if has_col $1 libraries version; then
		q $1 "UPDATE libraries SET hasData=1 WHERE version > 0 OR lastUpdated != '0000-00-00 00:00:00'"
		q $1 "ALTER TABLE libraries DROP COLUMN lastUpdated, DROP COLUMN version"
	fi
}

check_users_timestamps() { ! has_col $1 users joined && ! has_col $1 users lastSyncTime; }
apply_users_timestamps() {
	has_col $1 users joined && q $1 "ALTER TABLE users DROP joined"
	has_col $1 users lastSyncTime && q $1 "ALTER TABLE users DROP lastSyncTime"
	return 0
}

check_key_indexes() { has_index_on $1 keyPermissions libraryID && has_index_on $1 keys lastUsed && has_index_on $1 keyAccessLog timestamp; }
apply_key_indexes() {
	has_index_on $1 keyPermissions libraryID || q $1 "ALTER TABLE keyPermissions ADD INDEX (libraryID)"
	has_index_on $1 keys lastUsed || q $1 "CREATE INDEX lastUsed ON \`keys\` (lastUsed)"
	has_index_on $1 keyAccessLog timestamp || q $1 "CREATE INDEX timestamp ON keyAccessLog (timestamp)"
}

check_storage_logs() { ! has_table $1 storageDownloadLog && ! has_table $1 storageUploadLog; }
apply_storage_logs() { q $1 "DROP TABLE IF EXISTS storageDownloadLog, storageUploadLog"; }

check_group_description_utf8mb4() { [ "$(col $1 groups description CHARACTER_SET_NAME)" = utf8mb4 ]; }
apply_group_description_utf8mb4() {
	q $1 "ALTER TABLE \`groups\` CHANGE description description TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL"
}

check_login_sessions() { has_table $1 loginSessions; }
apply_login_sessions() {
	q $1 "CREATE TABLE loginSessions (
		sessionToken char(32) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL,
		userID int(10) unsigned DEFAULT NULL,
		keyID int(10) unsigned DEFAULT NULL,
		clientType enum('mac','windows','linux','ios','android','unknown') NOT NULL,
		status enum('pending','completed','expired','cancelled') NOT NULL DEFAULT 'pending',
		dateCreated timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
		dateExpires timestamp NOT NULL,
		dateCompleted timestamp NULL DEFAULT NULL,
		PRIMARY KEY (sessionToken), KEY userID (userID), KEY keyID (keyID), KEY dateExpires (dateExpires),
		CONSTRAINT loginSessions_ibfk_1 FOREIGN KEY (userID) REFERENCES users (userID) ON DELETE CASCADE,
		CONSTRAINT loginSessions_ibfk_2 FOREIGN KEY (keyID) REFERENCES \`keys\` (keyID) ON DELETE SET NULL
	) ENGINE=InnoDB DEFAULT CHARSET=utf8"
}

check_upload_queue_index() { has_index_on $1 storageUploadQueue time; }
apply_upload_queue_index() { q $1 "ALTER TABLE storageUploadQueue ADD INDEX time (time)"; }

check_charsets() { [ -n "$(q $1 "SELECT 1 FROM charsets WHERE charsetID=186")" ]; }
apply_charsets() {
	# Rows 169-186 from coredata.sql
	sed -n '/^INSERT INTO `charsets`/,/;/p' coredata.sql | sed 's/^INSERT INTO/INSERT IGNORE INTO/' | mysql_ $1
}

# www

check_www_password() { [ "$(col $1 users password CHARACTER_MAXIMUM_LENGTH)" -ge 255 ]; }
apply_www_password() { q $1 "ALTER TABLE users MODIFY password varchar(255) CHARACTER SET utf8 COLLATE utf8_bin NOT NULL"; }

check_www_email_validated() { has_col $1 users_email validated; }
apply_www_email_validated() { q $1 "ALTER TABLE users_email ADD validated tinyint(1) NOT NULL DEFAULT 1"; }

check_www_domain_blacklist() { ! has_table $1 storage_institutions || [ "$(col $1 storage_institutions domainBlacklist DATA_TYPE)" = varchar ]; }
apply_www_domain_blacklist() {
	q $1 "UPDATE storage_institutions SET domainBlacklist='' WHERE domainBlacklist IS NULL"
	q $1 "ALTER TABLE storage_institutions MODIFY domainBlacklist varchar(255) NOT NULL DEFAULT ''"
}

# shards

check_link_mode_embedded_image() { col $1 itemAttachments linkMode COLUMN_TYPE | grep -q EMBEDDED_IMAGE; }
apply_link_mode_embedded_image() {
	q $1 "ALTER TABLE itemAttachments CHANGE linkMode linkMode ENUM('IMPORTED_FILE','IMPORTED_URL','LINKED_FILE','LINKED_URL','EMBEDDED_IMAGE')"
}

# Item and creator IDs became BIGINT (upstream 2021-11-28 and 2022-11-05)
BIGINT_COLS="collectionItems.itemID deletedItems.itemID groupItems.itemID publicationsItems.itemID
	itemAttachments.itemID itemAttachments.sourceItemID itemAnnotations.itemID itemAnnotations.parentItemID
	itemCreators.itemID itemCreators.creatorID creators.creatorID itemData.itemID itemFulltext.itemID
	itemNotes.itemID itemNotes.sourceItemID itemRelated.itemID itemRelated.linkedItemID items.itemID
	itemSortFields.itemID itemTags.itemID itemTopLevel.itemID itemTopLevel.topLevelItemID storageFileItems.itemID"
small_id_cols() {
	local tc
	for tc in $BIGINT_COLS; do
		local t=${tc%.*} c=${tc#*.}
		has_col $1 $t $c || continue
		[ "$(col $1 $t $c DATA_TYPE)" = bigint ] || echo "$tc"
	done
}
check_bigint_ids() { [ -z "$(small_id_cols $1)" ]; }
apply_bigint_ids() {
	local db=$1 cols list fks tc t name c rt rc del upd
	cols=$(small_id_cols $db)
	list=$(for tc in $BIGINT_COLS; do printf "'%s'," "$tc"; done); list=${list%,}
	# Foreign keys on either side of the columns have to go while the types differ
	fks=$(q information_schema "SELECT CONCAT_WS('|', k.TABLE_NAME, k.CONSTRAINT_NAME,
			GROUP_CONCAT(k.COLUMN_NAME ORDER BY k.ORDINAL_POSITION), k.REFERENCED_TABLE_NAME,
			GROUP_CONCAT(k.REFERENCED_COLUMN_NAME ORDER BY k.ORDINAL_POSITION), r.DELETE_RULE, r.UPDATE_RULE)
		FROM KEY_COLUMN_USAGE k JOIN REFERENTIAL_CONSTRAINTS r ON r.CONSTRAINT_SCHEMA=k.CONSTRAINT_SCHEMA
			AND r.CONSTRAINT_NAME=k.CONSTRAINT_NAME AND r.TABLE_NAME=k.TABLE_NAME
		WHERE k.TABLE_SCHEMA='$db' AND k.REFERENCED_TABLE_NAME IS NOT NULL
			AND (CONCAT(k.TABLE_NAME, '.', k.COLUMN_NAME) IN ($list)
				OR CONCAT(k.REFERENCED_TABLE_NAME, '.', k.REFERENCED_COLUMN_NAME) IN ($list))
		GROUP BY k.TABLE_NAME, k.CONSTRAINT_NAME, k.REFERENCED_TABLE_NAME, r.DELETE_RULE, r.UPDATE_RULE")
	while IFS='|' read -r t name _ _ _ _ _; do
		if [ -n "$t" ]; then q $db "ALTER TABLE \`$t\` DROP FOREIGN KEY \`$name\`"; fi
	done <<< "$fks"
	for tc in $cols; do
		local def="BIGINT UNSIGNED"
		t=${tc%.*} c=${tc#*.}
		[ "$(col $db $t $c IS_NULLABLE)" = YES ] && def="$def NULL DEFAULT NULL" || def="$def NOT NULL"
		col $db $t $c EXTRA | grep -q auto_increment && def="$def AUTO_INCREMENT"
		log "  $db.$t.$c -> $def"
		q $db "ALTER TABLE \`$t\` MODIFY \`$c\` $def"
	done
	while IFS='|' read -r t name c rt rc del upd; do
		[ -n "$t" ] || continue
		c=$(echo "$c" | sed 's/,/`,`/g') rc=$(echo "$rc" | sed 's/,/`,`/g')
		q $db "ALTER TABLE \`$t\` ADD CONSTRAINT \`$name\` FOREIGN KEY (\`$c\`)
			REFERENCES \`$rt\` (\`$rc\`) ON DELETE $del ON UPDATE $upd"
	done <<< "$fks"
}

check_item_annotations() { has_table $1 itemAnnotations; }
apply_item_annotations() {
	q $1 "CREATE TABLE itemAnnotations (
		itemID bigint unsigned NOT NULL,
		parentItemID bigint unsigned NOT NULL,
		type enum('highlight','note','image','ink','underline','text') CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
		authorName varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT '',
		text text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL,
		comment mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL,
		color char(6) CHARACTER SET ascii NOT NULL,
		pageLabel varchar(50) NOT NULL,
		sortIndex varchar(18) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
		position text CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
		PRIMARY KEY (itemID), KEY parentItemID (parentItemID),
		CONSTRAINT itemAnnotations_ibfk_1 FOREIGN KEY (itemID) REFERENCES items (itemID) ON DELETE CASCADE,
		CONSTRAINT itemAnnotations_ibfk_2 FOREIGN KEY (parentItemID) REFERENCES itemAttachments (itemID)
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
}

# For databases that got itemAnnotations from an intermediate upstream version
check_item_annotation_columns() {
	col $1 itemAnnotations type COLUMN_TYPE | grep -q "'text'" && has_col $1 itemAnnotations authorName \
		&& [ "$(col $1 itemAnnotations text DATA_TYPE)" = text ] \
		&& [ "$(col $1 itemAnnotations position CHARACTER_SET_NAME)" = utf8mb4 ]
}
apply_item_annotation_columns() {
	q $1 "ALTER TABLE itemAnnotations
		CHANGE type type ENUM('highlight','note','image','ink','underline','text') CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
		CHANGE text text TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL,
		CHANGE position position TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL"
	has_col $1 itemAnnotations authorName \
		|| q $1 "ALTER TABLE itemAnnotations ADD authorName VARCHAR(80) NOT NULL DEFAULT '' AFTER type"
	return 0
}

check_item_top_level() { has_table $1 itemTopLevel; }
apply_item_top_level() {
	q $1 "CREATE TABLE itemTopLevel (
		itemID bigint unsigned NOT NULL,
		topLevelItemID bigint unsigned NOT NULL,
		PRIMARY KEY (itemID), KEY itemTopLevel_ibfk_2 (topLevelItemID),
		CONSTRAINT itemTopLevel_ibfk_1 FOREIGN KEY (itemID) REFERENCES items (itemID) ON DELETE CASCADE,
		CONSTRAINT itemTopLevel_ibfk_2 FOREIGN KEY (topLevelItemID) REFERENCES items (itemID) ON DELETE CASCADE
	) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
	q $1 "INSERT IGNORE INTO itemTopLevel
		SELECT itemID, sourceItemID FROM itemAttachments WHERE sourceItemID IS NOT NULL
		UNION SELECT itemID, sourceItemID FROM itemNotes WHERE sourceItemID IS NOT NULL"
}

check_settings_name() { [ "$(col $1 settings name CHARACTER_MAXIMUM_LENGTH)" -ge 60 ]; }
apply_settings_name() { q $1 "ALTER TABLE settings CHANGE name name VARCHAR(60) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL"; }

check_items_version_index() { has_index $1 items libraryVersion; }
apply_items_version_index() { q $1 "ALTER TABLE items ADD INDEX libraryVersion (libraryID, version)"; }

check_fulltext_library() { has_col $1 itemFulltext libraryID && has_index $1 itemFulltext libraryVersion; }
apply_fulltext_library() {
	has_col $1 itemFulltext libraryID || q $1 "ALTER TABLE itemFulltext ADD libraryID INT UNSIGNED NOT NULL AFTER itemID"
	q $1 "UPDATE itemFulltext IFT JOIN items I USING (itemID) SET IFT.libraryID=I.libraryID"
	has_index $1 itemFulltext libraryVersion || q $1 "ALTER TABLE itemFulltext ADD INDEX libraryVersion (libraryID, version)"
}

check_delete_log_data() { has_col $1 syncDeleteLogKeys data; }
apply_delete_log_data() { q $1 "ALTER TABLE syncDeleteLogKeys ADD data VARCHAR(255) NOT NULL DEFAULT ''"; }

check_storage_usage() { has_col $1 shardLibraries storageUsage; }
apply_storage_usage() {
	q $1 "ALTER TABLE shardLibraries ADD storageUsage BIGINT NOT NULL DEFAULT 0"
	q $1 "UPDATE shardLibraries SL SET storageUsage=(SELECT IFNULL(SUM(size), 0)
		FROM storageFileItems JOIN items USING (itemID) WHERE libraryID=SL.libraryID)"
}

check_attachment_last_read() { has_col $1 itemAttachments lastRead; }
apply_attachment_last_read() {
	q $1 "ALTER TABLE itemAttachments ADD lastRead INT UNSIGNED DEFAULT NULL, ADD INDEX lastRead (lastRead)"
}

# Triggers and events are replaced whenever the upstream files change (ledger ID has the hash)
check_triggers() { return 1; }
apply_triggers() { mysql_ $1 < triggers.sql; }
check_events() { return 1; }
apply_events() { mysql_ $1 < events.sql; }

MIGRATIONS=(
	all:utf8mb4_default
	master:libraries_hasData
	master:users_timestamps
	master:key_indexes
	master:storage_logs
	master:group_description_utf8mb4
	master:login_sessions
	master:upload_queue_index
	master:charsets
	master:events@$(md5sum < events.sql | cut -c1-12)
	www:www_password
	www:www_email_validated
	www:www_domain_blacklist
	shard:link_mode_embedded_image
	shard:bigint_ids
	shard:item_annotations
	shard:item_annotation_columns
	shard:item_top_level
	shard:settings_name
	shard:items_version_index
	shard:fulltext_library
	shard:delete_log_data
	shard:storage_usage
	shard:attachment_last_read
	shard:triggers@$(md5sum < triggers.sql | cut -c1-12)
)

dbs_for() {
	case $1 in
		all) q information_schema "SELECT SCHEMA_NAME FROM SCHEMATA WHERE SCHEMA_NAME LIKE 'zotero\\_%' AND SCHEMA_NAME != 'zotero_selfhost'" ;;
		master) echo zotero_master ;;
		www) has_db zotero_www && echo zotero_www || true ;;
		shard) q zotero_master "SELECT db FROM shards ORDER BY shardID" ;;
	esac
}

ledger_has() { [ -n "$(q zotero_selfhost "SELECT 1 FROM migrations WHERE id='$1'")" ]; }
ledger_add() { q zotero_selfhost "INSERT INTO migrations (id, result) VALUES ('$1', '$2')"; }

run_migrations() {
	q information_schema "CREATE DATABASE IF NOT EXISTS zotero_selfhost"
	q zotero_selfhost "CREATE TABLE IF NOT EXISTS migrations (
		id varchar(100) NOT NULL PRIMARY KEY,
		result enum('applied','present') NOT NULL,
		appliedAt timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP)"

	local pending=() m scope name db missing
	for m in "${MIGRATIONS[@]}"; do
		ledger_has "$m" && continue
		scope=${m%%:*} name=${m#*:} name=${name%@*}
		missing=
		for db in $(dbs_for $scope); do
			check_$name $db || { missing=1; break; }
		done
		if [ -n "$missing" ]; then pending+=("$m"); else ledger_add "$m" present; fi
	done

	if [ ${#pending[@]} -eq 0 ]; then
		log "Database schema is up to date"
		return
	fi
	log "Pending: ${pending[*]}"
	backup before-migration

	for m in "${pending[@]}"; do
		scope=${m%%:*} name=${m#*:} name=${name%@*}
		for db in $(dbs_for $scope); do
			if ! check_$name $db; then
				log "$m on $db"
				apply_$name $db
			fi
		done
		ledger_add "$m" applied
	done
}

# --- 3. zotero-schema --------------------------------------------------------------------

update_zotero_schema() {
	local fileVersion dbVersion
	fileVersion=$(php -r 'echo json_decode(file_get_contents("../htdocs/zotero-schema/schema.json"), true)["version"];')
	dbVersion=$(q zotero_master "SELECT value FROM settings WHERE name='schemaVersion'")
	if [ "${dbVersion:-0}" -lt "$fileVersion" ]; then
		log "Updating zotero-schema from version ${dbVersion:-0} to $fileVersion"
		local out
		out=$(cd ../admin && php schema_update 2>&1) || { echo "$out" >&2; exit 1; }
	fi
}

import_legacy
if ! has_db zotero_master; then
	log "No databases yet, nothing to migrate (bin/init.sh creates them)"
	exit 0
fi
run_migrations
update_zotero_schema
./apply-shared-group.sh
log "Done"
