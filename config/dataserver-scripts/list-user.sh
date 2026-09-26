#!/bin/sh
export MYSQL_PWD="${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD not set}"
echo "SELECT u.userID, u.username, e.email FROM zotero_www.users u LEFT JOIN zotero_www.users_email e USING (userID);" \
	| mysql -h "${MYSQL_HOST:-mysql}" -u root
