#!/usr/bin/env bash
set -euo pipefail

release_dir="${1:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -d "$release_dir" ]] || {
    echo "Release directory is required" >&2
    exit 1
}
for command in python3 sha256sum find awk sort; do
    command -v "$command" >/dev/null || {
        echo "Missing command: $command" >&2
        exit 1
    }
done

release_dir="$(cd "$release_dir" && pwd)"
[[ -s "$release_dir/proxy.tar.gz" ]] || {
    echo "Missing proxy.tar.gz" >&2
    exit 1
}
[[ -s "$release_dir/hashes.sha256" ]] || {
    echo "Missing hashes.sha256" >&2
    exit 1
}

mapfile -t actual_files < <(find "$release_dir" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
expected_files=(hashes.sha256 proxy.tar.gz)
[[ "${actual_files[*]}" == "${expected_files[*]}" ]] || {
    echo "Release contains missing or unexpected assets" >&2
    printf 'Expected: %s\nActual: %s\n' "${expected_files[*]}" "${actual_files[*]}" >&2
    exit 1
}
[[ "$(awk 'NF { count++ } END { print count + 0 }' "$release_dir/hashes.sha256")" == 1 ]] || {
    echo "hashes.sha256 must contain exactly one entry" >&2
    exit 1
}
[[ "$(awk '$2 == "proxy.tar.gz" || $2 == "*proxy.tar.gz" { count++ } END { print count + 0 }' "$release_dir/hashes.sha256")" == 1 ]] || {
    echo "Expected one digest for proxy.tar.gz" >&2
    exit 1
}

(cd "$release_dir" && sha256sum --check --strict hashes.sha256)
python3 "$script_dir/verify-archive.py" "$release_dir/proxy.tar.gz"

echo "Local proxy release satisfies the Confluence Platform contract"
