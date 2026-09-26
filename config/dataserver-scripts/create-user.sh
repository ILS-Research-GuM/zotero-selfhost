#!/bin/sh
# Usage: create-user.sh <username> <password> <email>
# New users also join the shared group (see apply-shared-group.sh) as members if there is one.
# Storage quota comes from ZOTERO_STORAGE_QUOTA_MB (default: unlimited).
set -e

USERNAME="$1"
PASSWORD="$2"
EMAIL="$3"
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$EMAIL" ]; then
	echo "Usage: $0 <username> <password> <email>" >&2
	exit 1
fi
# Values are interpolated into SQL, so restrict them to safe characters
echo "$USERNAME" | grep -Eq '^[A-Za-z0-9._-]{1,40}$' || { echo "Invalid username" >&2; exit 1; }
echo "$EMAIL" | grep -Eq '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$' || { echo "Invalid email" >&2; exit 1; }
QUOTA="${ZOTERO_STORAGE_QUOTA_MB:-1000000}"
echo "$QUOTA" | grep -Eq '^[0-9]+$' || { echo "Invalid ZOTERO_STORAGE_QUOTA_MB" >&2; exit 1; }

export MYSQL_PWD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD not set}"
MYSQL="mysql -N -h ${MYSQL_HOST:-mysql} -u root"

HASH=$(php -r 'echo password_hash($argv[1], PASSWORD_BCRYPT);' -- "$PASSWORD")

USERID=$($MYSQL -e "INSERT INTO zotero_www.users (username, password) VALUES ('$USERNAME', '$HASH'); SELECT LAST_INSERT_ID();")

$MYSQL <<EOF
INSERT INTO zotero_www.users_email (userID, email) VALUES ($USERID, '$EMAIL');
INSERT INTO zotero_master.libraries (libraryType, shardID) VALUES ('user', 1);
SET @lib = LAST_INSERT_ID();
INSERT INTO zotero_master.users (userID, libraryID, username) VALUES ($USERID, @lib, '$USERNAME');
INSERT INTO zotero_shard_1.shardLibraries (libraryID, libraryType) VALUES (@lib, 'user');
-- Quota in MB; 1000000 means unlimited. TIMESTAMP columns end in 2038.
INSERT INTO zotero_master.storageAccounts (userID, quota, expiration)
	VALUES ($USERID, $QUOTA, '2038-01-01 00:00:00');
EOF
# The settings table only exists once a shared group was set up
$MYSQL -e "INSERT INTO zotero_master.groupUsers (groupID, userID, role, joined)
	SELECT value, $USERID, 'member', CURRENT_TIMESTAMP FROM zotero_selfhost.settings WHERE name = 'sharedGroupID'" 2>/dev/null || true

echo "Created user '$USERNAME' with userID $USERID"
