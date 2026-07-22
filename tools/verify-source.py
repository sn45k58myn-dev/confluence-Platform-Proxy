#!/usr/bin/env python3
"""Validate proxy payload provenance before packaging."""

from __future__ import annotations

import json
import re
import sys
import urllib.parse
from pathlib import Path


MANIFEST_KEYS = {"schema_version", "target", "components"}
COMPONENT_KEYS = {"name", "version", "source", "license", "sha256"}
PRIVATE_KEY_MARKER = re.compile(br"-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----")


def fail(message: str) -> None:
    raise SystemExit(message)


def main() -> None:
    if len(sys.argv) != 2:
        fail("Usage: verify-source.py PAYLOAD_ROOT")
    root = Path(sys.argv[1])
    for path in root.rglob("*"):
        if path.is_file() and path.stat().st_size <= 1024 * 1024:
            try:
                if PRIVATE_KEY_MARKER.search(path.read_bytes()):
                    fail(f"Proxy payload contains private key material: {path.relative_to(root)}")
            except OSError as error:
                fail(f"Proxy payload file cannot be inspected: {error}")
    manifest_path = root / "runtime-manifest.json"
    if not manifest_path.is_file():
        fail("Proxy payload has no runtime-manifest.json")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"Proxy runtime manifest is invalid: {error}")
    if not isinstance(manifest, dict) or set(manifest) != MANIFEST_KEYS:
        fail("Proxy runtime manifest schema is invalid")
    if manifest.get("schema_version") != 1 or manifest.get("target") != "proxy":
        fail("Proxy runtime manifest target is invalid")
    components = manifest.get("components")
    if not isinstance(components, list) or not components:
        fail("Proxy runtime manifest has no components")
    names: set[str] = set()
    for component in components:
        if not isinstance(component, dict) or set(component) != COMPONENT_KEYS:
            fail("Proxy runtime component schema is invalid")
        name = component.get("name")
        source = component.get("source")
        parsed = urllib.parse.urlsplit(source) if isinstance(source, str) else None
        if not isinstance(name, str) or not name.strip() or name in names:
            fail("Proxy runtime component name is missing or duplicated")
        names.add(name)
        if not isinstance(component.get("version"), str) or not component["version"].strip():
            fail(f"Proxy runtime component version is missing: {name}")
        if not isinstance(component.get("license"), str) or not component["license"].strip():
            fail(f"Proxy runtime component license is missing: {name}")
        if parsed is None or parsed.scheme != "https" or not parsed.netloc:
            fail(f"Proxy runtime component source is untrusted: {name}")
        if not isinstance(component.get("sha256"), str) or re.fullmatch(r"[0-9a-f]{64}", component["sha256"]) is None:
            fail(f"Proxy runtime component digest is invalid: {name}")
        if not any(
            path.is_file() and (path.name == name or path.name.startswith(f"{name}."))
            for path in (root / "LICENSES").rglob("*")
        ):
            fail(f"Proxy runtime component has no matching license notice: {name}")
    print("Proxy runtime provenance is complete")


if __name__ == "__main__":
    main()
