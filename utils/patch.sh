#!/bin/sh
# Usage: utils/patch.sh [--check]
# Patches are applied at image build time (docker/dataserver/Dockerfile).
# This applies them to the dataserver submodule for development, or with --check only tests them.
set -e
cd "$(dirname "$0")/../src/server/dataserver"

for p in ../../patches/dataserver/*.patch; do
	if [ "$1" = "--check" ]; then
		git apply --check "$p" || { echo "Patch no longer applies: $p" >&2; exit 1; }
	else
		git apply "$p"
	fi
done
echo "Patches OK"
