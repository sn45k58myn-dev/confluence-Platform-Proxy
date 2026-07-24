#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-${GITHUB_REF_NAME:-}}"
REPOSITORY="${2:-sn45k58myn-dev/confluence-Platform-Proxy}"
bash "$(dirname "$0")/validate-tag.sh" "$TAG"

for command in gh; do
    command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
gh release download "$TAG" --repo "$REPOSITORY" --dir "$workdir" --pattern '*'
bash "$(dirname "$0")/verify-local-release.sh" "$workdir"

echo "Proxy release $TAG satisfies the Confluence Platform contract"
