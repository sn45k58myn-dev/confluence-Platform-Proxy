#!/usr/bin/env python3
"""Lock the fail-closed proxy publication sequence."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "tools" / "publish-release.sh").read_text(encoding="utf-8")


class PublishReleaseContractTest(unittest.TestCase):
    def test_local_contract_runs_before_remote_mutation(self) -> None:
        local_verify = SOURCE.index('verify-local-release.sh" "$release_dir"')
        release_lookup = SOURCE.index('gh release view "$tag"')
        release_create = SOURCE.index('release create "$tag"')

        self.assertLess(local_verify, release_lookup)
        self.assertLess(local_verify, release_create)

    def test_publication_is_bound_to_clean_pushed_tag(self) -> None:
        for marker in (
            'git -C "$project_root" diff --quiet',
            'git -C "$project_root" diff --cached --quiet',
            'rev-parse "$tag^{commit}"',
            '[[ "$tag_commit" == "$head_commit" ]]',
            'ls-remote origin "refs/tags/$tag"',
            '[[ -n "$remote_tag" && "$remote_tag" == "$local_tag" ]]',
        ):
            self.assertIn(marker, SOURCE)

    def test_only_drafts_can_be_replaced(self) -> None:
        self.assertIn('--json isDraft --jq .isDraft', SOURCE)
        self.assertIn('Published release $tag is immutable', SOURCE)
        self.assertIn('--draft', SOURCE)
        self.assertIn('--clobber', SOURCE)

    def test_remote_assets_are_verified_before_and_after_publish(self) -> None:
        verification = 'verify-release.sh" "$tag" "$repository"'
        publish = 'publish_args=(release edit "$tag" --repo "$repository" --draft=false)'

        self.assertEqual(2, SOURCE.count(verification))
        first_verify = SOURCE.index(verification)
        publish_release = SOURCE.index(publish)
        second_verify = SOURCE.index(verification, first_verify + 1)
        self.assertLess(first_verify, publish_release)
        self.assertLess(publish_release, second_verify)


if __name__ == "__main__":
    unittest.main()
