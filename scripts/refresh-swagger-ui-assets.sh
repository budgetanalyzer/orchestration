#!/bin/bash

set -euo pipefail

SWAGGER_UI_VERSION="5.11.0"
SWAGGER_UI_INTEGRITY="sha512-j0PIATqQSEFGOLmiJOJZj1X1Jt6bFIur3JpY7+ghliUnfZs0fpWDdHEkn9q7QUlBtKbkn6TepvSxTqnE8l3s0A=="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DOCS_DIR="$REPO_ROOT/docs-aggregator"
TMP_DIR="$(mktemp -d)"
TARBALL="$TMP_DIR/swagger-ui-dist-$SWAGGER_UI_VERSION.tgz"
PACKAGE_DIR="$TMP_DIR/package"

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

curl -fsSL "https://registry.npmjs.org/swagger-ui-dist/-/swagger-ui-dist-$SWAGGER_UI_VERSION.tgz" -o "$TARBALL"

ACTUAL_INTEGRITY="sha512-$(openssl dgst -sha512 -binary "$TARBALL" | openssl base64 -A)"
if [[ "$ACTUAL_INTEGRITY" != "$SWAGGER_UI_INTEGRITY" ]]; then
    echo "Integrity mismatch for swagger-ui-dist@$SWAGGER_UI_VERSION" >&2
    echo "Expected: $SWAGGER_UI_INTEGRITY" >&2
    echo "Actual:   $ACTUAL_INTEGRITY" >&2
    exit 1
fi

tar -xzf "$TARBALL" -C "$TMP_DIR"

cp "$PACKAGE_DIR/swagger-ui.css" "$DOCS_DIR/swagger-ui.css"
cp "$PACKAGE_DIR/swagger-ui-bundle.js" "$DOCS_DIR/swagger-ui-bundle.js"
cp "$PACKAGE_DIR/swagger-ui-standalone-preset.js" "$DOCS_DIR/swagger-ui-standalone-preset.js"
cp "$PACKAGE_DIR/LICENSE" "$DOCS_DIR/swagger-ui-LICENSE"
cp "$PACKAGE_DIR/NOTICE" "$DOCS_DIR/swagger-ui-NOTICE"

echo "Updated docs-aggregator Swagger UI assets to v$SWAGGER_UI_VERSION"
