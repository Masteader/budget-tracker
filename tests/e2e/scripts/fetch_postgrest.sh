#!/usr/bin/env bash
# Download the official PostgREST static Linux binary used by the e2e suite.
#
#   tests/e2e/scripts/fetch_postgrest.sh [DEST_DIR]
#
# Prints the absolute path of the binary on success. The version matches the PostgREST 12.x
# line hosted Supabase projects run. Override with POSTGREST_VERSION=v12.2.x.
set -euo pipefail

VERSION="${POSTGREST_VERSION:-v12.2.3}"
DEST="${1:-${XDG_CACHE_HOME:-$HOME/.cache}/bt-e2e/postgrest-${VERSION}}"
ASSET="postgrest-${VERSION}-linux-static-x64.tar.xz"
URL="https://github.com/PostgREST/postgrest/releases/download/${VERSION}/${ASSET}"

mkdir -p "$DEST"
if [[ ! -x "$DEST/postgrest" ]]; then
    curl -sSfL --retry 3 --max-time 300 -o "$DEST/$ASSET" "$URL"
    tar -xJf "$DEST/$ASSET" -C "$DEST" postgrest
    rm -f "$DEST/$ASSET"
    chmod +x "$DEST/postgrest"
fi
"$DEST/postgrest" --version >&2
echo "$DEST/postgrest"
