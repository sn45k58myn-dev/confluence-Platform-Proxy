#!/usr/bin/env python3
"""Validate one proxy archive without extracting it."""

from __future__ import annotations

import json
import re
import stat
import sys
import tarfile
import urllib.parse
from pathlib import Path, PurePosixPath


MAX_MEMBERS = 50_000
MAX_EXPANDED_BYTES = 2 * 1024 * 1024 * 1024
MAX_MEMBER_BYTES = 512 * 1024 * 1024
REQUIRED_FILES = {
    "service",
    "console.php",
    "bootstrap.php",
    "vendor/autoload.php",
    "bin/php/bin/php",
    "bin/php/lib/php.ini",
    "bin/nginx/sbin/nginx",
    "bin/nginx/conf/nginx.conf",
    "runtime-manifest.json",
    "bin/nginx/conf/ports/http.conf",
    "bin/nginx/conf/ports/https.conf",
}
REQUIRED_DIRECTORIES = {"LICENSES", "bin/nginx/conf/servers"}
FORBIDDEN_BASENAMES = {"config.ini", "id_rsa", "id_ed25519", "server.key"}
FORBIDDEN_SUFFIXES = (".key", ".pem", ".p12", ".pfx")
MANIFEST_KEYS = {"schema_version", "target", "components"}
COMPONENT_KEYS = {"name", "version", "source", "license", "sha256"}


def fail(message: str) -> None:
    raise SystemExit(message)


def safe_path(value: str, *, base: PurePosixPath = PurePosixPath(".")) -> str:
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        fail(f"Archive path contains a control character: {value!r}")
    normalized = value.replace("\\", "/")
    path = PurePosixPath(normalized)
    if not normalized or path.is_absolute() or re.match(r"^[A-Za-z]:", normalized):
        fail(f"Unsafe archive path: {value}")
    parts: list[str] = []
    for part in (base / path).parts:
        if part in ("", "."):
            continue
        if part == "..":
            if not parts:
                fail(f"Archive path escapes its root: {value}")
            parts.pop()
        else:
            parts.append(part)
    return "/".join(parts)


def verify(path: Path) -> None:
    manifest_bytes: bytes | None = None
    with tarfile.open(path, "r:gz") as archive:
        members = archive.getmembers()
        if not members or len(members) > MAX_MEMBERS:
            fail("Archive is empty or contains too many members")
        member_paths = {safe_path(member.name) for member in members}
        seen: set[str] = set()
        seen_casefold: set[str] = set()
        expanded_bytes = 0
        mtimes: set[int] = set()
        by_path: dict[str, tarfile.TarInfo] = {}
        for member in members:
            canonical = safe_path(member.name)
            if canonical in seen or canonical.casefold() in seen_casefold:
                fail(f"Archive contains a duplicate or case-colliding path: {member.name}")
            seen.add(canonical)
            seen_casefold.add(canonical.casefold())
            by_path[canonical] = member
            basename = PurePosixPath(canonical).name.lower()
            if basename in FORBIDDEN_BASENAMES or basename.endswith(FORBIDDEN_SUFFIXES) or re.fullmatch(r"[0-9]+\.json", basename):
                fail(f"Archive contains forbidden secret material: {member.name}")
            if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                fail(f"Archive contains a special filesystem entry: {member.name}")
            if member.uid != 0 or member.gid != 0:
                fail(f"Archive member is not root-owned: {member.name}")
            if member.mode & (stat.S_ISUID | stat.S_ISGID):
                fail(f"Archive member has elevated permission bits: {member.name}")
            if (member.isfile() or member.isdir()) and stat.S_IMODE(member.mode) & stat.S_IWOTH:
                fail(f"Archive member is world-writable: {member.name}")
            if member.size > MAX_MEMBER_BYTES:
                fail(f"Archive member exceeds the size limit: {member.name}")
            expanded_bytes += member.size
            if expanded_bytes > MAX_EXPANDED_BYTES:
                fail("Archive exceeds the expanded size limit")
            mtimes.add(member.mtime)
            if member.issym():
                target = safe_path(member.linkname, base=PurePosixPath(canonical).parent)
                if target not in member_paths:
                    fail(f"Archive symbolic link target is missing: {member.name}")
            elif member.islnk():
                target = safe_path(member.linkname)
                if target not in member_paths:
                    fail(f"Archive hard link target is missing: {member.name}")
        manifest_member = by_path.get("runtime-manifest.json")
        if manifest_member is not None and manifest_member.isfile():
            stream = archive.extractfile(manifest_member)
            manifest_bytes = stream.read() if stream is not None else None

    if len(mtimes) != 1:
        fail("Archive members do not share one deterministic timestamp")
    for required in REQUIRED_FILES:
        member = by_path.get(required)
        if member is None or not member.isfile():
            fail(f"Archive is missing required file: {required}")
    for required in REQUIRED_DIRECTORIES:
        member = by_path.get(required)
        if member is None or not member.isdir():
            fail(f"Archive is missing required directory: {required}")
    if not any(name.startswith("LICENSES/") and member.isfile() for name, member in by_path.items()):
        fail("Proxy license inventory is empty")
    if manifest_bytes is None:
        fail("Proxy runtime provenance manifest cannot be read")
    verify_manifest(
        manifest_bytes,
        {PurePosixPath(name).name for name, member in by_path.items() if name.startswith("LICENSES/") and member.isfile()},
    )
    for executable in ("service", "bin/php/bin/php", "bin/nginx/sbin/nginx"):
        member = by_path[executable]
        if stat.S_IMODE(member.mode) & stat.S_IXUSR == 0:
            fail(f"Proxy runtime file is not owner-executable: {executable}")


def verify_manifest(raw: bytes, license_names: set[str]) -> None:
    try:
        manifest = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"Proxy runtime provenance manifest is invalid: {error}")
    if not isinstance(manifest, dict) or set(manifest) != MANIFEST_KEYS:
        fail("Proxy runtime provenance manifest schema is invalid")
    if manifest.get("schema_version") != 1 or manifest.get("target") != "proxy":
        fail("Proxy runtime provenance target is invalid")
    components = manifest.get("components")
    if not isinstance(components, list) or not components:
        fail("Proxy runtime provenance component list is empty")
    names: set[str] = set()
    for component in components:
        if not isinstance(component, dict) or set(component) != COMPONENT_KEYS:
            fail("Proxy runtime provenance component schema is invalid")
        name = component.get("name")
        source = component.get("source")
        parsed = urllib.parse.urlsplit(source) if isinstance(source, str) else None
        if not isinstance(name, str) or not name.strip() or name in names:
            fail("Proxy runtime provenance component name is missing or duplicated")
        names.add(name)
        if not isinstance(component.get("version"), str) or not component["version"].strip():
            fail(f"Proxy runtime provenance component version is missing: {name}")
        if not isinstance(component.get("license"), str) or not component["license"].strip():
            fail(f"Proxy runtime provenance component license is missing: {name}")
        if parsed is None or parsed.scheme != "https" or not parsed.netloc:
            fail(f"Proxy runtime provenance component source is untrusted: {name}")
        if not isinstance(component.get("sha256"), str) or re.fullmatch(r"[0-9a-f]{64}", component["sha256"]) is None:
            fail(f"Proxy runtime provenance component digest is invalid: {name}")
        if not any(candidate == name or candidate.startswith(f"{name}.") for candidate in license_names):
            fail(f"Proxy runtime provenance component has no matching license notice: {name}")


def main() -> None:
    if len(sys.argv) != 2:
        fail("Usage: verify-archive.py ARCHIVE")
    path = Path(sys.argv[1])
    if not path.is_file() or path.stat().st_size == 0:
        fail("Archive does not exist or is empty")
    verify(path)
    print(f"Proxy archive is safe: {path.name}")


if __name__ == "__main__":
    main()
