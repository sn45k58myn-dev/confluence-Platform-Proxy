#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

payload="$workdir/payload"
mkdir -p "$payload/LICENSES" "$payload/bin/nginx/conf/servers" "$payload/bin/nginx/conf/ports"
printf '#!/usr/bin/env bash\nexit 0\n' > "$payload/service"
chmod 750 "$payload/service"
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
(cd "$workdir/first" && sha256sum --check --strict hashes.sha256)
python3 "$project_root/tools/verify-archive.py" "$workdir/first/proxy.tar.gz"

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
