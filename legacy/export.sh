#!/bin/sh
# Usage: sudo legacy/export.sh
# Exports the data of the previous (2021) stack into data/legacy/, where db-migrate and
# s3-import of this stack pick it up. Works after "git pull": it finds the old containers
# (db-zotero-mysql, db-zotero-minio) by their Compose labels, starting them if stopped.
# Writes data/legacy/legacy.sql.gz (all zotero_* databases) and data/legacy/s3/<bucket>/.
set -eu
cd "$(dirname "$0")/.."
OUT="${LEGACY_DIR:-$PWD/data/legacy}"

find_container() {
	ids=$(docker ps -aq -f "label=com.docker.compose.service=$1")
	[ -n "$ids" ] || { echo "No container of the old service $1 found" >&2; exit 1; }
	[ "$(echo "$ids" | wc -l)" -eq 1 ] || { echo "Several containers of $1 found: $ids" >&2; exit 1; }
	echo "$ids"
}
MYSQL=$(find_container db-zotero-mysql)
MINIO=$(find_container db-zotero-minio)
docker start "$MYSQL" "$MINIO" >/dev/null
MYSQL_NAME=$(docker inspect -f '{{.Name}}' "$MYSQL" | tr -d /)
NETWORK=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$MYSQL" | cut -d' ' -f1)

mkdir -p "$OUT"
chmod 700 "$OUT"
echo "Exporting from $MYSQL_NAME and $(docker inspect -f '{{.Name}}' "$MINIO" | tr -d /) to $OUT"
docker run --rm --network "$NETWORK" --volumes-from "$MINIO:ro" -v "$OUT:/export" \
	-e MYSQL_PWD="${OLD_MYSQL_PASSWORD:-zotero}" -e HOST="$MYSQL_NAME" mysql:5.7 bash -euo pipefail -c '
		until mysqladmin -h "$HOST" -uroot ping >/dev/null 2>&1; do sleep 2; done
		dbs=$(mysql -h "$HOST" -uroot -N -e "SHOW DATABASES LIKE '"'zotero\\\\_%'"'")
		echo "Dumping" $dbs
		mysqldump -h "$HOST" -uroot --single-transaction --routines --triggers --events \
			--databases $dbs | gzip > /export/legacy.sql.gz.tmp
		mv /export/legacy.sql.gz.tmp /export/legacy.sql.gz
		# Old MinIO versions store objects as plain files (fs mode); newer ones do not
		if find /data -name xl.meta | grep -q .; then
			echo "MinIO data is not in fs mode, copy the buckets with an S3 client instead" >&2
			exit 1
		fi
		mkdir -p /export/s3
		for b in zotero zotero-fulltext; do
			if [ -d "/data/$b" ]; then cp -a "/data/$b" /export/s3/; fi
		done
		echo "Export done: $(du -sh /export | cut -f1)"'
