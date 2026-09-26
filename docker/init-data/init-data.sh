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
