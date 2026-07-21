#!/usr/bin/env python3
"""Validate one proxy archive without extracting it."""

from __future__ import annotations

import re
import stat
import sys
import tarfile
from pathlib import Path, PurePosixPath


MAX_MEMBERS = 50_000
MAX_EXPANDED_BYTES = 2 * 1024 * 1024 * 1024
MAX_MEMBER_BYTES = 512 * 1024 * 1024
REQUIRED_FILES = {
    "service",
    "bin/nginx/conf/ports/http.conf",
    "bin/nginx/conf/ports/https.conf",
}
REQUIRED_DIRECTORIES = {"bin/nginx/conf/servers"}
FORBIDDEN_BASENAMES = {"config.ini", "id_rsa", "id_ed25519", "server.key"}
FORBIDDEN_SUFFIXES = (".key", ".pem", ".p12", ".pfx")


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
    service = by_path["service"]
    if stat.S_IMODE(service.mode) not in (0o750, 0o755):
        fail("Proxy service launcher has an unsafe mode")


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
