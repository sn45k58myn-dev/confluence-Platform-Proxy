# Proxy release contract

Every release must contain:

- `proxy.tar.gz`
- `hashes.sha256` with exactly one SHA-256 entry for `proxy.tar.gz`

After extraction into `/home/confluencetv`, the archive must provide:

- `service` — the proxy service launcher
- `bin/nginx/conf/servers/` — generated parent-server configurations
- `bin/nginx/conf/ports/http.conf`
- `bin/nginx/conf/ports/https.conf`

Archive paths must be relative and may not traverse outside the extraction root.
The payload must not include credentials, private keys, generated server JSON,
database configuration, or environment-specific certificates.

Tags use semantic versions. Release assets are immutable; publish a new patch tag
to correct a package.
