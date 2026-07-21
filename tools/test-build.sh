#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

payload="$workdir/payload"
mkdir -p "$payload/bin/nginx/conf/servers" "$payload/bin/nginx/conf/ports"
printf '#!/usr/bin/env bash\nexit 0\n' > "$payload/service"
chmod 750 "$payload/service"
printf 'listen 80;\n' > "$payload/bin/nginx/conf/ports/http.conf"
printf 'listen 443 ssl;\n' > "$payload/bin/nginx/conf/ports/https.conf"

for output in first second; do
    mkdir -p "$workdir/$output"
    SOURCE_DATE_EPOCH=1700000000 "$project_root/tools/build.sh" "$payload" "$workdir/$output"
done

first="$(sha256sum "$workdir/first/proxy.tar.gz" | cut -d' ' -f1)"
second="$(sha256sum "$workdir/second/proxy.tar.gz" | cut -d' ' -f1)"
[[ "$first" == "$second" ]] || { echo "Proxy package is not reproducible" >&2; exit 1; }
(cd "$workdir/first" && sha256sum --check --strict hashes.sha256)

echo "Proxy packager is deterministic"
