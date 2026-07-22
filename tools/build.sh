#!/usr/bin/env bash
set -euo pipefail

payload="${1:-payload}"
output_dir="${2:-dist}"
source_date_epoch="${SOURCE_DATE_EPOCH:-$(git show -s --format=%ct HEAD 2>/dev/null || true)}"

required_files=(
    service
    console.php
    bootstrap.php
    vendor/autoload.php
    bin/php/bin/php
    bin/php/lib/php.ini
    bin/nginx/sbin/nginx
    bin/nginx/conf/nginx.conf
)
for required in "${required_files[@]}"; do
    [[ -f "$payload/$required" ]] || { echo "Missing proxy runtime file: $required" >&2; exit 1; }
done
for executable in service bin/php/bin/php bin/nginx/sbin/nginx; do
    [[ -x "$payload/$executable" ]] || { echo "Proxy runtime file is not executable: $executable" >&2; exit 1; }
done
[[ "$source_date_epoch" =~ ^[0-9]+$ ]] || { echo "SOURCE_DATE_EPOCH must be an integer" >&2; exit 1; }
[[ -d "$payload/LICENSES" ]] || { echo "Missing proxy license inventory" >&2; exit 1; }
find "$payload/LICENSES" -type f -print -quit | grep -q . || { echo "Proxy license inventory is empty" >&2; exit 1; }
python3 "$(dirname "$0")/verify-source.py" "$payload"
[[ -d "$payload/bin/nginx/conf/servers" ]] || { echo "Missing nginx server configuration directory" >&2; exit 1; }
[[ -f "$payload/bin/nginx/conf/ports/http.conf" ]] || { echo "Missing HTTP port configuration" >&2; exit 1; }
[[ -f "$payload/bin/nginx/conf/ports/https.conf" ]] || { echo "Missing HTTPS port configuration" >&2; exit 1; }

if find "$payload" -regextype posix-extended -type f \( -iname '*.key' -o -iname '*.pem' -o -iname '*.p12' -o -iname '*.pfx' -o -name 'config.ini' -o -regex '.*/[0-9]+\.json' \) -print -quit | grep -q .; then
    echo "Payload contains a forbidden credential or environment-specific file" >&2
    exit 1
fi

mkdir -p "$output_dir"
archive="$output_dir/proxy.tar.gz"
temporary_archive="$(mktemp "$output_dir/.proxy.tar.gz.XXXXXX")"
temporary_manifest=""
trap 'rm -f "${temporary_archive:-}" "${temporary_manifest:-}"' EXIT
tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 --numeric-owner \
    --use-compress-program='gzip -n' --create --file "$temporary_archive" --directory "$payload" .
tar -tzf "$temporary_archive" >/dev/null
mv -f "$temporary_archive" "$archive"
if ! python3 "$(dirname "$0")/verify-archive.py" "$archive"; then
    rm -f "$archive"
    echo "Packaged proxy archive failed final validation" >&2
    exit 1
fi
temporary_manifest="$(mktemp "$output_dir/.hashes.sha256.XXXXXX")"
sha256sum "$archive" | awk '{ print $1 "  proxy.tar.gz" }' > "$temporary_manifest"
mv -f "$temporary_manifest" "$output_dir/hashes.sha256"
temporary_manifest=""

echo "Created $archive and $output_dir/hashes.sha256"
