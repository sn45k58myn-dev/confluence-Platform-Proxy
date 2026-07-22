#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

for tag in 0.1.0 1.2.3-rc.1 1.2.3+build.7; do
    bash "$project_root/tools/validate-tag.sh" "$tag"
done
for tag in v1.2.3 01.2.3 1.2 1.2.3.4 1.2.3-; do
    if bash "$project_root/tools/validate-tag.sh" "$tag" >/dev/null 2>&1; then
        echo "Invalid semantic release tag unexpectedly passed: $tag" >&2
        exit 1
    fi
done

payload="$workdir/payload"
mkdir -p "$payload/LICENSES" "$payload/vendor" "$payload/bin/install" \
    "$payload/bin/nginx/conf/servers" "$payload/bin/nginx/conf/ports"
printf '#!/usr/bin/env bash\nexit 0\n' > "$payload/service"
chmod 750 "$payload/service"
printf '#!/usr/bin/env php\n<?php exit(0);\n' > "$payload/console.php"
printf '<?php // synthetic bootstrap\n' > "$payload/bootstrap.php"
printf '<?php // synthetic autoloader\n' > "$payload/vendor/autoload.php"
printf '#!/usr/bin/env bash\nexit 0\n' > "$payload/bin/install/update_binaries.sh"
printf '#!/usr/bin/env python3\n' > "$payload/bin/install/validate_tar.py"
printf '#!/usr/bin/env python3\n' > "$payload/bin/install/validate_runtime_manifest.py"
chmod 750 "$payload/bin/install/update_binaries.sh"
printf 'listen 80;\n' > "$payload/bin/nginx/conf/ports/http.conf"
printf 'listen 443 ssl;\n' > "$payload/bin/nginx/conf/ports/https.conf"
printf 'Synthetic test fixture only.\n' > "$payload/LICENSES/fixture.txt"
cat > "$payload/runtime-manifest.json" <<'JSON'
{
  "schema_version": 1,
  "target": "proxy",
  "components": [
    {
      "name": "fixture",
      "version": "1.0.0",
      "source": "https://example.invalid/fixture",
      "license": "Test-only",
      "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
  ]
}
JSON

for output in first second; do
    mkdir -p "$workdir/$output"
    SOURCE_DATE_EPOCH=1700000000 "$project_root/tools/build.sh" "$payload" "$workdir/$output"
done

first="$(sha256sum "$workdir/first/proxy.tar.gz" | cut -d' ' -f1)"
second="$(sha256sum "$workdir/second/proxy.tar.gz" | cut -d' ' -f1)"
[[ "$first" == "$second" ]] || { echo "Proxy package is not reproducible" >&2; exit 1; }

printf 'server_tokens off;\n' >> "$payload/bin/nginx/conf/ports/http.conf"
SOURCE_DATE_EPOCH=1700000000 "$project_root/tools/build.sh" "$payload" "$workdir/first"
replacement="$(sha256sum "$workdir/first/proxy.tar.gz" | cut -d' ' -f1)"
[[ "$replacement" != "$first" ]] || { echo "Proxy replacement fixture did not change the archive" >&2; exit 1; }
[[ "$(awk 'NF { count++ } END { print count + 0 }' "$workdir/first/hashes.sha256")" == 1 ]] || {
    echo "Proxy checksum inventory contains stale entries" >&2
    exit 1
}
if find "$workdir/first" -maxdepth 1 -type f \( -name '.hashes.*' -o -name '.proxy.tar.gz.*' \) -print -quit | grep -q .; then
    echo "Proxy publication left a temporary file behind" >&2
    exit 1
fi
(cd "$workdir/first" && sha256sum --check --strict hashes.sha256)
python3 "$project_root/tools/verify-archive.py" "$workdir/first/proxy.tar.gz"

missing_runtime="$workdir/missing-runtime"
cp -a "$payload" "$missing_runtime"
rm "$missing_runtime/console.php"
if SOURCE_DATE_EPOCH=1700000000 "$project_root/tools/build.sh" "$missing_runtime" "$workdir/missing-output" >/dev/null 2>&1; then
    echo "Proxy payload without its startup entry point unexpectedly passed validation" >&2
    exit 1
fi

non_executable="$workdir/non-executable"
cp -a "$payload" "$non_executable"
chmod 640 "$non_executable/bin/install/update_binaries.sh"
if SOURCE_DATE_EPOCH=1700000000 "$project_root/tools/build.sh" "$non_executable" "$workdir/non-executable-output" >/dev/null 2>&1; then
    echo "Proxy payload with a non-executable binary bootstrap unexpectedly passed validation" >&2
    exit 1
fi

forged="$workdir/forged"
cp -a "$payload" "$forged"
sed -i 's/"target": "proxy"/"target": "main"/' "$forged/runtime-manifest.json"
tar --sort=name --mtime='@1700000000' --owner=0 --group=0 --numeric-owner \
    --use-compress-program='gzip -n' --create --file "$workdir/forged-target.tar.gz" --directory "$forged" .
if python3 "$project_root/tools/verify-archive.py" "$workdir/forged-target.tar.gz" >/dev/null 2>&1; then
    echo "Proxy archive with a mismatched provenance target unexpectedly passed validation" >&2
    exit 1
fi

sed -i 's/"target": "main"/"target": "proxy"/' "$forged/runtime-manifest.json"
rm "$forged/LICENSES/fixture.txt"
printf 'Unrelated notice.\n' > "$forged/LICENSES/unrelated.txt"
tar --sort=name --mtime='@1700000000' --owner=0 --group=0 --numeric-owner \
    --use-compress-program='gzip -n' --create --file "$workdir/forged-license.tar.gz" --directory "$forged" .
if python3 "$project_root/tools/verify-archive.py" "$workdir/forged-license.tar.gz" >/dev/null 2>&1; then
    echo "Proxy archive without its component notice unexpectedly passed validation" >&2
    exit 1
fi

python3 - "$workdir/unsafe.tar.gz" <<'PY'
import io
import sys
import tarfile

with tarfile.open(sys.argv[1], "w:gz") as archive:
    member = tarfile.TarInfo("../escape")
    member.size = 1
    archive.addfile(member, io.BytesIO(b"x"))
PY
if python3 "$project_root/tools/verify-archive.py" "$workdir/unsafe.tar.gz" >/dev/null 2>&1; then
    echo "Unsafe archive unexpectedly passed validation" >&2
    exit 1
fi

echo "Proxy packager is deterministic"
