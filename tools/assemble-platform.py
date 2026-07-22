#!/usr/bin/env python3
"""Create a runtime-neutral proxy payload from a Platform LB archive."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import stat
import sys
import tarfile
import tempfile
import urllib.parse
from pathlib import Path, PurePosixPath


MAX_MEMBERS = 100_000
MAX_EXPANDED_BYTES = 4 * 1024 * 1024 * 1024
SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$")
SOURCE_PATH = re.compile(
    r"^/sn45k58myn-dev/confluence-Platform-Releases/releases/download/[^/]+/loadbalancer\.tar\.gz$"
)
REQUIRED_FILES = (
    "LICENSE",
    "service",
    "console.php",
    "bootstrap.php",
    "vendor/autoload.php",
    "bin/install/update_binaries.sh",
    "bin/install/validate_tar.py",
    "bin/install/validate_runtime_manifest.py",
    "bin/nginx/conf/ports/http.conf",
    "bin/nginx/conf/ports/https.conf",
)
RUNTIME_PATHS = (
    "bin/ffmpeg_bin",
    "bin/redis/redis-server",
    "bin/guess",
    "bin/yt-dlp",
)


def fail(message: str) -> None:
    raise SystemExit(message)


def canonical_path(value: str) -> str:
    normalized = value.replace("\\", "/")
    path = PurePosixPath(normalized)
    if path.is_absolute() or re.match(r"^[A-Za-z]:", normalized):
        fail(f"Platform archive contains an unsafe path: {value}")
    parts = [part for part in path.parts if part not in ("", ".")]
    if ".." in parts or any(ord(character) < 32 or ord(character) == 127 for character in value):
        fail(f"Platform archive contains an unsafe path: {value}")
    return "/".join(parts)


def inspect_archive(path: Path) -> None:
    expanded = 0
    seen: set[str] = set()
    seen_casefold: set[str] = set()
    with tarfile.open(path, "r:gz") as archive:
        members = archive.getmembers()
        if not members or len(members) > MAX_MEMBERS:
            fail("Platform archive is empty or contains too many members")
        for member in members:
            canonical = canonical_path(member.name)
            if not canonical:
                continue
            if canonical in seen or canonical.casefold() in seen_casefold:
                fail(f"Platform archive contains a duplicate path: {member.name}")
            seen.add(canonical)
            seen_casefold.add(canonical.casefold())
            if not (member.isfile() or member.isdir()):
                fail(f"Platform archive contains a link or special entry: {member.name}")
            if member.mode & (stat.S_ISUID | stat.S_ISGID):
                fail(f"Platform archive contains elevated permission bits: {member.name}")
            if stat.S_IMODE(member.mode) & stat.S_IWOTH:
                fail(f"Platform archive contains a world-writable entry: {member.name}")
            expanded += member.size
            if expanded > MAX_EXPANDED_BYTES:
                fail("Platform archive exceeds the expanded size limit")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    if len(sys.argv) != 5:
        fail("Usage: assemble-platform.py LOADBALANCER_ARCHIVE VERSION SOURCE_URL OUTPUT_PAYLOAD")
    archive_path = Path(sys.argv[1]).resolve()
    version = sys.argv[2]
    source = sys.argv[3]
    output = Path(sys.argv[4]).resolve()
    parsed = urllib.parse.urlsplit(source)
    if not archive_path.is_file() or archive_path.stat().st_size == 0:
        fail("Platform load-balancer archive is missing or empty")
    if SEMVER.fullmatch(version) is None:
        fail("Platform version is not semantic")
    if parsed.scheme != "https" or parsed.netloc != "github.com" or SOURCE_PATH.fullmatch(parsed.path) is None:
        fail("Platform source URL is not a trusted release asset")
    if output.exists():
        fail("Output payload already exists")

    inspect_archive(archive_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=f".{output.name}.", dir=output.parent))
    try:
        with tarfile.open(archive_path, "r:gz") as archive:
            archive.extractall(temporary, filter="data")
        for required in REQUIRED_FILES:
            if not (temporary / required).is_file():
                fail(f"Platform archive is missing required proxy file: {required}")
        for relative in RUNTIME_PATHS:
            path = temporary / relative
            if path.is_dir():
                shutil.rmtree(path)
            elif path.exists():
                path.unlink()
        for path in temporary.rglob("*"):
            if path.is_file():
                with path.open("rb") as stream:
                    if stream.read(4) == b"\x7fELF":
                        fail(f"Proxy application payload still contains an OS-specific ELF binary: {path.relative_to(temporary)}")

        licenses = temporary / "LICENSES"
        licenses.mkdir(mode=0o755, exist_ok=True)
        shutil.copyfile(temporary / "LICENSE", licenses / "platform-proxy-app.txt")
        digest = sha256_file(archive_path)
        manifest = {
            "schema_version": 1,
            "target": "proxy",
            "components": [
                {
                    "name": "platform-proxy-app",
                    "version": version,
                    "source": source,
                    "license": "AGPL-3.0-or-later",
                    "sha256": digest,
                }
            ],
        }
        (temporary / "runtime-manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        temporary.rename(output)
    except BaseException:
        shutil.rmtree(temporary, ignore_errors=True)
        raise
    print(f"Created runtime-neutral proxy payload: {output}")


if __name__ == "__main__":
    main()
