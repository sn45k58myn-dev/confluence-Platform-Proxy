#!/usr/bin/env python3
"""Regression checks for bounded, immutable GitHub workflow inputs."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = {
    path.name: path.read_text(encoding="utf-8")
    for path in sorted((ROOT / ".github" / "workflows").glob("*.yml"))
}


class WorkflowContractTest(unittest.TestCase):
    def test_workflows_are_permission_and_time_bounded(self) -> None:
        self.assertEqual({"ci.yml", "verify-release.yml"}, set(WORKFLOWS))
        for name, source in WORKFLOWS.items():
            with self.subTest(workflow=name):
                self.assertIn("permissions:\n  contents: read", source)
                self.assertRegex(source, r"timeout-minutes: [1-9][0-9]*")

    def test_actions_are_pinned_to_full_commits(self) -> None:
        for name, source in WORKFLOWS.items():
            actions = re.findall(r"uses:\s*([^\s]+)", source)
            self.assertTrue(actions, name)
            for action in actions:
                with self.subTest(workflow=name, action=action):
                    self.assertRegex(action, r"^[^@]+@[a-f0-9]{40}$")

    def test_release_verification_remains_post_publication_and_manual(self) -> None:
        source = WORKFLOWS["verify-release.yml"]

        self.assertIn("release:\n    types: [published]", source)
        self.assertIn("workflow_dispatch:", source)
        self.assertIn('tools/verify-release.sh "${{ inputs.tag || github.event.release.tag_name }}"', source)


if __name__ == "__main__":
    unittest.main()
