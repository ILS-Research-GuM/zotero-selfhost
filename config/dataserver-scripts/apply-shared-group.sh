#!/bin/sh
# Sets up the shared group from SHARED_GROUP_OWNER, once. Run by db-migrate on every start and
# by init-mysql.sh, but does nothing once the group exists: later changes to its owner, admins
# or settings are kept.
#   empty: no shared group is created
#   email: a group named DEFAULT_GROUP_NAME that every new user joins as member. Members can
#          only read; the user with that email owns it and can write. If that user doesn't exist
#          yet, the admin user owns it until the portal hands it over on their first login.
# The group ID is kept in zotero_selfhost.settings (sharedGroupID); an existing group with the
# same name is adopted.
set -e
[ -n "${SHARED_GROUP_OWNER:-}" ] || exit 0
cd "$(dirname "$0")"

export MYSQL_PWD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD not set}"
MYSQL="mysql -N -h ${MYSQL_HOST:-mysql} -u root"
NAME="${DEFAULT_GROUP_NAME:-Shared}"

$MYSQL <<'EOF'
CREATE DATABASE IF NOT EXISTS zotero_selfhost;
CREATE TABLE IF NOT EXISTS zotero_selfhost.settings (
	name varchar(100) NOT NULL PRIMARY KEY,
	value varchar(255) NOT NULL);
EOF

setting() { $MYSQL -e "SELECT value FROM zotero_selfhost.settings WHERE name='$1'"; }
GROUPID=$(setting sharedGroupID)
if [ -n "$GROUPID" ] && [ -n "$($MYSQL -e "SELECT 1 FROM zotero_master.\`groups\` WHERE groupID=$GROUPID")" ]; then
	exit 0
fi

EMAIL=$(echo "$SHARED_GROUP_OWNER" | sed "s/'/''/g")
OWNER=$($MYSQL -e "SELECT u.username FROM zotero_www.users_email e JOIN zotero_master.users u USING (userID)
	WHERE e.email='$EMAIL' ORDER BY u.userID LIMIT 1")
# Adopt an existing group of that name, or create it
GROUPID=$($MYSQL -e "SELECT groupID FROM zotero_master.\`groups\` WHERE name='$(echo "$NAME" | sed "s/'/''/g")' ORDER BY groupID LIMIT 1")
if [ -z "$GROUPID" ]; then
	GROUPID=$(./create-group.sh "$NAME" "${OWNER:-${ZOTERO_ADMIN_USER:-admin}}" admins | sed -n 's/.*groupID \([0-9]*\).*/\1/p')
	[ -n "$GROUPID" ] || { echo "Creating the shared group failed" >&2; exit 1; }
fi
$MYSQL -e "REPLACE INTO zotero_selfhost.settings (name, value) VALUES ('sharedGroupID', '$GROUPID')"
# Users that exist already join as well
$MYSQL -e "INSERT IGNORE INTO zotero_master.groupUsers (groupID, userID, role, joined)
	SELECT $GROUPID, userID, 'member', CURRENT_TIMESTAMP FROM zotero_master.users"
if [ -z "$OWNER" ]; then
	# Handed over by the portal on the first login with this email
	$MYSQL -e "REPLACE INTO zotero_selfhost.settings (name, value) VALUES ('sharedGroupPendingOwner', '$EMAIL')"
	echo "No user with email $SHARED_GROUP_OWNER yet; they become owner of the shared group on first login"
fi

cd ../admin
php -r 'set_include_path("../include"); require "header.inc.php"; require "../model/Error.inc.php";
	[, $groupID, $owner] = $argv;
	$group = Zotero_Groups::get((int) $groupID);
	$group->libraryEditing = "admins";
	$group->fileEditing = "admins";
	if ($owner) {
		$group->ownerUserID = (int) Zotero_DB::valueQuery("SELECT userID FROM users WHERE username=?", $owner);
	}
	$group->save();
	echo "Shared group $groupID ($group->name): read-only for members, owner " . Zotero_Users::getUsername($group->ownerUserID) . "\n";' "$GROUPID" "$OWNER"
