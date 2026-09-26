#!/bin/sh
# One-time setup after the first "docker compose up -d": S3 storage and databases.
# Re-running it recreates the databases and deletes all data in them.
set -e
cd "$(dirname "$0")/.."
. ./.env

DC="docker compose"
garage() { $DC exec -T garage /garage "$@"; }

echo "Setting up Garage..."
NODE_ID=$(garage node id -q | cut -d@ -f1)
if ! garage layout show | grep -q "$(echo "$NODE_ID" | cut -c1-16)"; then
	garage layout assign -z dc1 -c 100G "$NODE_ID"
	garage layout apply --version 1
fi
garage key info "$S3_ACCESS_KEY" >/dev/null 2>&1 \
	|| garage key import --yes -n zotero "$S3_ACCESS_KEY" "$S3_SECRET_KEY"
for bucket in zotero zotero-fulltext; do
	garage bucket info "$bucket" >/dev/null 2>&1 || garage bucket create "$bucket"
	garage bucket allow --read --write --owner "$bucket" --key "$S3_ACCESS_KEY"
done

# Let the web-library fetch attachments directly from S3
echo "Setting bucket CORS for $WEB_LIBRARY_URL..."
CORS="{\"CORSRules\":[{\"AllowedOrigins\":[\"$WEB_LIBRARY_URL\"],\"AllowedMethods\":[\"GET\",\"HEAD\",\"POST\"],\"AllowedHeaders\":[\"*\"],\"ExposeHeaders\":[\"ETag\"],\"MaxAgeSeconds\":3600}]}"
for bucket in zotero zotero-fulltext; do
	docker run --rm --network host -e AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY" -e AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY" \
		-e AWS_DEFAULT_REGION=us-east-1 amazon/aws-cli --endpoint-url "http://127.0.0.1:${S3_PORT:-8182}" \
		s3api put-bucket-cors --bucket "$bucket" --cors-configuration "$CORS"
done

echo "Setting up databases..."
$DC exec -T dataserver /var/www/zotero/misc/init-mysql.sh

echo "Done. Log in with user '$ZOTERO_ADMIN_USER' and the password from ZOTERO_ADMIN_PASSWORD in .env"
