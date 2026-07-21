#!/usr/bin/env bash
set -euo pipefail

tag="${1:-}"
semantic_version='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
[[ "$tag" =~ $semantic_version ]] || {
    echo "A strict semantic release tag is required" >&2
    exit 1
}
