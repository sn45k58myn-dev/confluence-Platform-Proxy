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

Every push exercises the deterministic packaging contract with a synthetic,
credential-free fixture. Runtime payloads remain local and are published only
after their origin and redistribution terms have been reviewed.
