#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-${GITHUB_REF_NAME:-}}"
REPOSITORY="${2:-sn45k58myn-dev/confluence-Platform-Proxy}"
[[ "$TAG" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] || { echo "A semantic release tag is required" >&2; exit 1; }

for command in gh sha256sum tar; do
    command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
gh release download "$TAG" --repo "$REPOSITORY" --dir "$workdir" --pattern '*'
[[ -s "$workdir/proxy.tar.gz" ]] || { echo "Missing proxy.tar.gz" >&2; exit 1; }
[[ -s "$workdir/hashes.sha256" ]] || { echo "Missing hashes.sha256" >&2; exit 1; }
count="$(awk '$2 == "proxy.tar.gz" || $2 == "*proxy.tar.gz" { count++ } END { print count + 0 }' "$workdir/hashes.sha256")"
[[ "$count" == 1 ]] || { echo "Expected one proxy.tar.gz digest" >&2; exit 1; }
(cd "$workdir" && sha256sum --check --strict hashes.sha256)

listing="$workdir/proxy.paths"
tar -tzf "$workdir/proxy.tar.gz" > "$listing"
grep -Eq '(^|/)service$' "$listing" || { echo "Proxy service launcher is missing" >&2; exit 1; }
grep -Eq '(^|/)bin/nginx/conf/servers/$' "$listing" || { echo "Nginx server configuration directory is missing" >&2; exit 1; }
grep -Eq '(^|/)bin/nginx/conf/ports/http\.conf$' "$listing" || { echo "HTTP port configuration is missing" >&2; exit 1; }
grep -Eq '(^|/)bin/nginx/conf/ports/https\.conf$' "$listing" || { echo "HTTPS port configuration is missing" >&2; exit 1; }
! grep -Eq '(^/|(^|/)\.\.(/|$)|^[A-Za-z]:)' "$listing" || { echo "Archive contains an unsafe path" >&2; exit 1; }
! grep -Eqi '(^|/)(config\.ini|[^/]+\.(key|pem|p12|pfx)|[0-9]+\.json)$' "$listing" || { echo "Archive contains forbidden secret material" >&2; exit 1; }

echo "Proxy release $TAG satisfies the Confluence Platform contract"
