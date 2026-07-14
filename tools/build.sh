#!/usr/bin/env bash
set -euo pipefail

payload="${1:-payload}"
output_dir="${2:-dist}"

[[ -f "$payload/service" ]] || { echo "Missing proxy service launcher" >&2; exit 1; }
[[ -d "$payload/bin/nginx/conf/servers" ]] || { echo "Missing nginx server configuration directory" >&2; exit 1; }
[[ -f "$payload/bin/nginx/conf/ports/http.conf" ]] || { echo "Missing HTTP port configuration" >&2; exit 1; }
[[ -f "$payload/bin/nginx/conf/ports/https.conf" ]] || { echo "Missing HTTPS port configuration" >&2; exit 1; }

if find "$payload" -type f \( -iname '*.key' -o -iname '*.pem' -o -iname '*.p12' -o -iname '*.pfx' -o -name 'config.ini' -o -name '*.json' \) -print -quit | grep -q .; then
    echo "Payload contains a forbidden credential or environment-specific file" >&2
    exit 1
fi

mkdir -p "$output_dir"
archive="$output_dir/proxy.tar.gz"
tar --create --gzip --file "$archive" --directory "$payload" .
tar -tzf "$archive" >/dev/null
sha256sum "$archive" | awk '{ print $1 "  proxy.tar.gz" }' > "$output_dir/hashes.sha256"

echo "Created $archive and $output_dir/hashes.sha256"
