#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

root="$workdir/platform"
mkdir -p "$root/vendor/composer/ca-bundle/res" "$root/bin/install" \
    "$root/bin/nginx/conf/ports" "$root/bin/nginx/conf/servers" "$root/bin/ffmpeg_bin/4.0"
printf 'AGPL test licence\n' > "$root/LICENSE"
printf '#!/bin/sh\n' > "$root/service"
printf '<?php\n' > "$root/console.php"
printf '<?php\n' > "$root/bootstrap.php"
printf '<?php\n' > "$root/vendor/autoload.php"
printf '%s\n' '-----BEGIN CERTIFICATE-----' 'public-ca' '-----END CERTIFICATE-----' \
    > "$root/vendor/composer/ca-bundle/res/cacert.pem"
printf '#!/bin/bash\n' > "$root/bin/install/update_binaries.sh"
printf '#!/usr/bin/env python3\n' > "$root/bin/install/validate_tar.py"
printf '#!/usr/bin/env python3\n' > "$root/bin/install/validate_runtime_manifest.py"
printf 'listen 80;\n' > "$root/bin/nginx/conf/ports/http.conf"
printf 'listen 443 ssl;\n' > "$root/bin/nginx/conf/ports/https.conf"
printf '\177ELFsynthetic' > "$root/bin/ffmpeg_bin/4.0/ffmpeg"
tar --sort=name --mtime='@1700000000' --owner=0 --group=0 --numeric-owner \
    --use-compress-program='gzip -n' --create --file "$workdir/loadbalancer.tar.gz" --directory "$root" .

source_url="https://github.com/sn45k58myn-dev/confluence-Platform-Releases/releases/download/2.3.5/loadbalancer.tar.gz"
python3 "$project_root/tools/assemble-platform.py" \
    "$workdir/loadbalancer.tar.gz" 2.3.5 "$source_url" "$workdir/payload"
[[ ! -e "$workdir/payload/bin/ffmpeg_bin" ]] || { echo "OS-specific FFmpeg was retained" >&2; exit 1; }
[[ -s "$workdir/payload/LICENSES/platform-proxy-app.txt" ]] || { echo "Proxy app licence is missing" >&2; exit 1; }
python3 "$project_root/tools/verify-source.py" "$workdir/payload"
SOURCE_DATE_EPOCH=1700000000 "$project_root/tools/build.sh" "$workdir/payload" "$workdir/dist"

python3 - "$workdir/unsafe.tar.gz" <<'PY'
import io
import sys
import tarfile
with tarfile.open(sys.argv[1], "w:gz") as archive:
    member = tarfile.TarInfo("../escape")
    member.size = 1
    archive.addfile(member, io.BytesIO(b"x"))
PY
if python3 "$project_root/tools/assemble-platform.py" \
    "$workdir/unsafe.tar.gz" 2.3.5 "$source_url" "$workdir/unsafe-output" >/dev/null 2>&1; then
    echo "Unsafe Platform archive unexpectedly passed proxy assembly" >&2
    exit 1
fi

echo "Proxy payload assembler is safe and runtime-neutral"
