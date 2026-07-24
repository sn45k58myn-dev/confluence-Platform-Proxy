#!/usr/bin/env bash
set -euo pipefail

tag="${1:-}"
release_dir="${2:-}"
repository="${3:-sn45k58myn-dev/confluence-Platform-Proxy}"
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_dir="$project_root/tools"
assets=(proxy.tar.gz hashes.sha256)

bash "$script_dir/validate-tag.sh" "$tag"
bash "$script_dir/verify-local-release.sh" "$release_dir"
release_dir="$(cd "$release_dir" && pwd)"
for command in gh git sha256sum; do
    command -v "$command" >/dev/null || {
        echo "Missing command: $command" >&2
        exit 1
    }
done

git -C "$project_root" diff --quiet
git -C "$project_root" diff --cached --quiet
local_tag="$(git -C "$project_root" rev-parse "refs/tags/$tag")"
tag_commit="$(git -C "$project_root" rev-parse "$tag^{commit}")"
head_commit="$(git -C "$project_root" rev-parse HEAD)"
[[ "$tag_commit" == "$head_commit" ]] || {
    echo "Release tag must resolve to the checked-out commit" >&2
    exit 1
}
remote_tag="$(git -C "$project_root" ls-remote origin "refs/tags/$tag" | awk 'NR == 1 { print $1 }')"
[[ -n "$remote_tag" && "$remote_tag" == "$local_tag" ]] || {
    echo "Release tag is missing from origin or differs from the local tag" >&2
    exit 1
}

is_prerelease=false
[[ "$tag" == *-* ]] && is_prerelease=true
notes="$(mktemp)"
trap 'rm -f "$notes"' EXIT
{
    printf 'Confluence Platform proxy package `%s`\n\n' "$tag"
    printf 'Source commit: `%s`\n\n' "$tag_commit"
    printf 'The package was verified against `RELEASE_CONTRACT.md` before and after publication.\n'
} > "$notes"

if gh release view "$tag" --repo "$repository" >/dev/null 2>&1; then
    [[ "$(gh release view "$tag" --repo "$repository" --json isDraft --jq .isDraft)" == "true" ]] || {
        echo "Published release $tag is immutable; use a new patch tag" >&2
        exit 1
    }
else
    create_args=(
        release create "$tag"
        --repo "$repository"
        --verify-tag
        --title "Confluence Platform Proxy $tag"
        --notes-file "$notes"
        --draft
    )
    [[ "$is_prerelease" == "true" ]] && create_args+=(--prerelease)
    gh "${create_args[@]}"
fi

gh release edit "$tag" \
    --repo "$repository" \
    --title "Confluence Platform Proxy $tag" \
    --notes-file "$notes"
upload_assets=()
for asset in "${assets[@]}"; do
    upload_assets+=("$release_dir/$asset")
done
gh release upload "$tag" \
    --repo "$repository" \
    --clobber \
    "${upload_assets[@]}"
bash "$script_dir/verify-release.sh" "$tag" "$repository"

publish_args=(release edit "$tag" --repo "$repository" --draft=false)
if [[ "$is_prerelease" == "true" ]]; then
    publish_args+=(--prerelease)
else
    publish_args+=(--latest)
fi
gh "${publish_args[@]}"
bash "$script_dir/verify-release.sh" "$tag" "$repository"

echo "Published verified proxy release $tag"
