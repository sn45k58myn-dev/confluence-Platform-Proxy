# Confluence Platform Proxy

Public source and release contract for the lightweight Confluence Platform proxy
node package.

The default branch contains packaging and verification tooling. Runtime payloads
are staged locally under `payload/`, built with `tools/build.sh`, and published as
the `proxy.tar.gz` asset with `hashes.sha256`.

No placeholder proxy release is published: the platform will fail closed until a
reviewed payload satisfies [RELEASE_CONTRACT.md](RELEASE_CONTRACT.md).

The proxy asset is application/configuration content, not an OS-specific binary
bundle. During provisioning, Platform runs the included fail-closed binary
updater in bootstrap mode so the target receives the release asset matching its
detected supported distribution before any PHP or Nginx entry point is invoked.

Create the reviewed application payload from the matching Platform
`loadbalancer.tar.gz` with:

```bash
python3 tools/assemble-platform.py loadbalancer.tar.gz 2.3.5 \
  https://github.com/sn45k58myn-dev/confluence-Platform-Releases/releases/download/2.3.5/loadbalancer.tar.gz \
  payload-2.3.5
bash tools/build.sh payload-2.3.5 dist
```

Assembly rejects unsafe archives and strips OS-specific ELF runtimes; those are
installed from the separately verified Binaries release during provisioning.

Every push exercises the deterministic packaging contract with a synthetic,
credential-free fixture. Runtime payloads remain local and are published only
after their origin and redistribution terms have been reviewed.

## Publish a verified release

Verify the assembled release directory before tagging:

```bash
tools/verify-local-release.sh dist
git tag -a X.Y.Z -m "Confluence Platform Proxy X.Y.Z"
git push origin X.Y.Z
```

Publish only through the guarded command:

```bash
tools/publish-release.sh X.Y.Z dist
```

The publisher requires a clean checkout whose pushed tag resolves to `HEAD`,
revalidates the exact two-file release set, creates or updates only a draft,
uploads and downloads the draft for verification, then publishes and verifies
the immutable release again. Corrections to a published package require a new
patch tag.
