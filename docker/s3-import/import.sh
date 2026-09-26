#!/bin/sh
# One-shot service s3-import: uploads the attachment files of a legacy export
# (data/legacy/s3/<bucket>/...) into Garage, once. Does nothing without an export.
# Garage needs its buckets first (bin/init.sh), which runs this again afterwards.
set -eu
SRC=/legacy/s3
MARK=/legacy/.s3-imported
S3="aws --endpoint-url http://garage:3900 s3"

[ -d "$SRC" ] && [ ! -e "$MARK" ] || exit 0

for bucket in zotero zotero-fulltext; do
	[ -d "$SRC/$bucket" ] || continue
	if ! $S3 ls "s3://$bucket" >/dev/null 2>&1; then
		echo "[s3-import] Bucket $bucket not available yet; run bin/init.sh"
		exit 0
	fi
	echo "[s3-import] Uploading $SRC/$bucket to s3://$bucket"
	$S3 sync "$SRC/$bucket" "s3://$bucket" --only-show-errors --exclude '.minio.sys/*'
done
date -u +%FT%TZ > "$MARK"
echo "[s3-import] Done"
