#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-${GITHUB_REF_NAME:-}}"
REPOSITORY="${2:-sn45k58myn-dev/confluence-Platform-Proxy}"
bash "$(dirname "$0")/validate-tag.sh" "$TAG"

for command in gh python3 sha256sum; do
    command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
gh release download "$TAG" --repo "$REPOSITORY" --dir "$workdir" --pattern '*'
[[ -s "$workdir/proxy.tar.gz" ]] || { echo "Missing proxy.tar.gz" >&2; exit 1; }
[[ -s "$workdir/hashes.sha256" ]] || { echo "Missing hashes.sha256" >&2; exit 1; }
mapfile -t actual_files < <(find "$workdir" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
[[ "${actual_files[*]}" == "hashes.sha256 proxy.tar.gz" ]] || {
    echo "Proxy release contains missing or unexpected assets" >&2
    printf 'Expected: hashes.sha256 proxy.tar.gz\nActual: %s\n' "${actual_files[*]}" >&2
    exit 1
}
[[ "$(awk 'NF { count++ } END { print count + 0 }' "$workdir/hashes.sha256")" == 1 ]] || {
    echo "hashes.sha256 must contain exactly one proxy archive entry" >&2
    exit 1
}
count="$(awk '$2 == "proxy.tar.gz" || $2 == "*proxy.tar.gz" { count++ } END { print count + 0 }' "$workdir/hashes.sha256")"
[[ "$count" == 1 ]] || { echo "Expected one proxy.tar.gz digest" >&2; exit 1; }
(cd "$workdir" && sha256sum --check --strict hashes.sha256)

python3 "$(dirname "$0")/verify-archive.py" "$workdir/proxy.tar.gz"

echo "Proxy release $TAG satisfies the Confluence Platform contract"
