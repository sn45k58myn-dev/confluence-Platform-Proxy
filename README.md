# Confluence Platform Proxy

Public source and release contract for the lightweight Confluence Platform proxy
node package.

The default branch contains packaging and verification tooling. Runtime payloads
are staged locally under `payload/`, built with `tools/build.sh`, and published as
the `proxy.tar.gz` asset with `hashes.sha256`.

No placeholder proxy release is published: the platform will fail closed until a
reviewed payload satisfies [RELEASE_CONTRACT.md](RELEASE_CONTRACT.md).
