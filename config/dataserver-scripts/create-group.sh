#!/bin/sh
# Usage: create-group.sh <name> <owner-username> [members|admins]
# The third argument sets who may edit: all members (default) or only owner and admins.
set -e

NAME="$1"
OWNER="$2"
EDITING="${3:-members}"
if [ -z "$NAME" ] || [ -z "$OWNER" ]; then
	echo "Usage: $0 <name> <owner-username>" >&2
	exit 1
fi
# Values are interpolated into SQL, so restrict them to safe characters
echo "$NAME" | grep -Eq '^[A-Za-z0-9 ._-]{1,100}$' || { echo "Invalid group name" >&2; exit 1; }
echo "$OWNER" | grep -Eq '^[A-Za-z0-9._-]{1,40}$' || { echo "Invalid username" >&2; exit 1; }
case "$EDITING" in members|admins) ;; *) echo "Editing must be 'members' or 'admins'" >&2; exit 1 ;; esac
SLUG=$(echo "$NAME" | tr 'A-Z ' 'a-z_')

export MYSQL_PWD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD not set}"
MYSQL="mysql -N -h ${MYSQL_HOST:-mysql} -u root"

OWNERID=$($MYSQL -e "SELECT userID FROM zotero_master.users WHERE username = '$OWNER'")
[ -n "$OWNERID" ] || { echo "Unknown user '$OWNER'" >&2; exit 1; }

GROUPID=$($MYSQL <<EOF
INSERT INTO zotero_master.libraries (libraryType, shardID) VALUES ('group', 2);
SET @lib = LAST_INSERT_ID();
INSERT INTO zotero_shard_2.shardLibraries (libraryID, libraryType) VALUES (@lib, 'group');
INSERT INTO zotero_master.\`groups\`
	(libraryID, name, slug, type, libraryEditing, libraryReading, fileEditing, description, url, dateModified)
	VALUES (@lib, '$NAME', '$SLUG', 'Private', '$EDITING', 'members', '$EDITING', '', '', CURRENT_TIMESTAMP);
SET @group = LAST_INSERT_ID();
INSERT INTO zotero_master.groupUsers (groupID, userID, role, joined)
	VALUES (@group, $OWNERID, 'owner', CURRENT_TIMESTAMP);
SELECT @group;
EOF
)

echo "Created group '$NAME' with groupID $GROUPID"
