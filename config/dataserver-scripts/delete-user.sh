#!/bin/sh
# Usage: delete-user.sh <userID>
# Deletes the user with all library data, API keys and the OIDC link. Files in S3 stay.
set -e

USERID="$1"
echo "$USERID" | grep -Eq '^[0-9]+$' || { echo "Usage: $0 <userID>" >&2; exit 1; }

export MYSQL_PWD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD not set}"
MYSQL="mysql -N -h ${MYSQL_HOST:-mysql} -u root"

# The dataserver only deletes users already marked as deleted on the website side
$MYSQL -e "INSERT INTO zotero_www.users (userID, username, password, role)
	SELECT userID, username, '', 'deleted' FROM zotero_master.users WHERE userID = $USERID
	ON DUPLICATE KEY UPDATE role = 'deleted'"

cd "$(dirname "$0")/../admin"
php -r 'set_include_path("../include"); require "header.inc.php"; require "../model/Error.inc.php";
	exit(Zotero_Users::deleteUser((int) $argv[1]) ? 0 : 1);' "$USERID" > /dev/null

$MYSQL -e "DELETE FROM zotero_www.users_meta WHERE userID = $USERID;
	DELETE FROM zotero_www.users_email WHERE userID = $USERID;
	DELETE FROM zotero_www.users WHERE userID = $USERID;"

echo "Deleted user $USERID"
