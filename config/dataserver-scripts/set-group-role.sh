#!/bin/sh
# Usage: set-group-role.sh <groupID> <username> <admin|member>
# In groups with editing "admins", admins can write and members can only read.
set -e

GROUPID="$1"
USERNAME="$2"
ROLE="$3"
echo "$GROUPID" | grep -Eq '^[0-9]+$' || { echo "Usage: $0 <groupID> <username> <admin|member>" >&2; exit 1; }
case "$ROLE" in admin|member) ;; *) echo "Role must be 'admin' or 'member'" >&2; exit 1 ;; esac

cd "$(dirname "$0")/../admin"
php -r 'set_include_path("../include"); require "header.inc.php"; require "../model/Error.inc.php";
	[, $groupID, $username, $role] = $argv;
	$userID = Zotero_DB::valueQuery("SELECT userID FROM users WHERE username=?", $username);
	if (!$userID) { fwrite(STDERR, "Unknown user $username\n"); exit(1); }
	$group = Zotero_Groups::get((int) $groupID);
	if (!$group) { fwrite(STDERR, "Unknown group $groupID\n"); exit(1); }
	if ($group->getUserRole($userID) === "owner") { fwrite(STDERR, "$username is the owner of this group\n"); exit(1); }
	$group->getUserRole($userID) ? $group->updateUser($userID, $role) : $group->addUser($userID, $role);
	echo "$username is now $role in group $groupID ($group->name)\n";' "$GROUPID" "$USERNAME" "$ROLE"
