#!/bin/sh
# Applies SHARED_GROUP_OWNER to group 1, the group every user joins. Run by db-migrate on every
# start and by init-mysql.sh.
#   empty: the group is left as it is (new installations: all members can edit)
#   email: the group becomes read-only for members, and the user with that email becomes its
#          owner (the previous owner becomes admin). If the user doesn't exist yet, the portal
#          makes them owner on their first login.
set -e
[ -n "${SHARED_GROUP_OWNER:-}" ] || exit 0

cd "$(dirname "$0")/../admin"
php -r 'set_include_path("../include"); require "header.inc.php"; require "../model/Error.inc.php";
	$email = $argv[1];
	$group = Zotero_Groups::get(1);
	if (!$group) { exit(0); }
	if ($group->libraryEditing != "admins" || $group->fileEditing != "admins") {
		$group->libraryEditing = "admins";
		$group->fileEditing = "admins";
		$group->save();
		echo "Group 1 ($group->name) is now read-only for members\n";
	}
	$userID = Zotero_DB::valueQuery("SELECT userID FROM zotero_www.users_email WHERE email=? ORDER BY userID LIMIT 1", $email);
	if (!$userID) {
		echo "No user with email $email yet; they become owner of group 1 on first login\n";
		exit(0);
	}
	if ($group->ownerUserID != $userID) {
		$group->ownerUserID = (int) $userID;
		$group->save();
		echo "User $userID ($email) is now owner of group 1 ($group->name)\n";
	}' "$SHARED_GROUP_OWNER"
