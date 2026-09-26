#!/bin/sh
# Usage: bin/create-api-key.sh <username> <password> [key-name]
# Creates an API key with full access to the user's library and groups,
# the same way the desktop client does on login.
set -e
cd "$(dirname "$0")/.."
. ./.env

if [ -z "$1" ] || [ -z "$2" ]; then
	echo "Usage: $0 <username> <password> [key-name]" >&2
	exit 1
fi

python3 -c 'import json,sys; print(json.dumps({
	"username": sys.argv[1], "password": sys.argv[2], "name": sys.argv[3],
	"access": {"user": {"library": True, "files": True, "notes": True, "write": True},
		"groups": {"all": {"library": True, "write": True}}}}))' "$1" "$2" "${3:-web-library}" \
| curl -sS -f -X POST -H "Zotero-API-Version: 3" -H "Content-Type: application/json" \
	--data-binary @- "http://127.0.0.1:$API_PORT/keys"
echo
