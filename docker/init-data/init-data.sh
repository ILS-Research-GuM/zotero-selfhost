#!/bin/sh
# Creates the bind-mounted data directories with the owners the services run as.
# Only touches files whose owner is wrong, so repeated starts stay fast.
set -eu

fix() {
	dir="/data/$1" uid="$2" gid="$3" mode="$4"
	mkdir -p "$dir"
	find "$dir" \( ! -user "$uid" -o ! -group "$gid" \) -exec chown -h "$uid:$gid" {} +
	chmod "$mode" "$dir"
	echo "$dir: $uid:$gid $mode"
}

chown 0:0 /data
chmod 755 /data
fix mysql 999 999 750             # mysql user in mysql:8.4
fix garage 0 0 700                # garage runs as root
fix dataserver-errors 33 33 750   # www-data in php:8.4-apache
fix backups 0 0 700               # database dumps of db-migrate
fix legacy 0 0 700                # legacy export to import (see legacy/)
# Public downloads served by the portal (/downloads), filled by a host user: DOWNLOADS_OWNER
# (uid:gid) owns the directory so that user can publish without root. Files stay as they are;
# they only need to be world-readable for the portal.
owner="${DOWNLOADS_OWNER:-0:0}"
case "$owner" in
	*[!0-9:]* | :* | *: | *:*:*) echo "DOWNLOADS_OWNER must be uid:gid, got '$owner'" >&2; exit 1 ;;
	*:*) ;;
	*) echo "DOWNLOADS_OWNER must be uid:gid, got '$owner'" >&2; exit 1 ;;
esac
mkdir -p /data/downloads
chown "$owner" /data/downloads
chmod 755 /data/downloads
echo "/data/downloads: $owner 755"
