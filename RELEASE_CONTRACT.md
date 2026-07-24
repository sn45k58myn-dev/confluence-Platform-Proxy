# Proxy release contract

Every release must contain:

- `proxy.tar.gz`
- `hashes.sha256` with exactly one SHA-256 entry for `proxy.tar.gz`

After extraction into `/home/confluencetv`, the archive must provide:

- `service` — the proxy service launcher
- `console.php`, `bootstrap.php`, and `vendor/autoload.php` — the application
  entry points required by the remote startup command
- `bin/install/update_binaries.sh` plus its trusted `validate_tar.py` and
  `validate_runtime_manifest.py` validators (the installer invokes the updater
  explicitly through `/bin/bash`)
- `bin/nginx/conf/servers/` — generated parent-server configurations
- `bin/nginx/conf/ports/http.conf`
- `bin/nginx/conf/ports/https.conf`
- `runtime-manifest.json` — a schema-versioned `proxy` manifest declaring the
  version, HTTPS source, license, and SHA-256 digest of every runtime component
- a non-empty `LICENSES/` directory containing notices for every redistributed
  runtime component

Every component declared in `runtime-manifest.json` must have a corresponding
notice named `LICENSES/<name>` or `LICENSES/<name>.*`; unrelated generic notices
do not satisfy the redistribution contract.

Archive paths must be relative and may not traverse outside the extraction root.
The payload must not include credentials, private keys, generated server JSON,
database configuration, or environment-specific certificates.
The packager fails closed when the runtime provenance manifest or license
inventory is absent, incomplete, invalid, or empty. OS-specific PHP and Nginx
executables are deliberately not embedded in this generic archive: the Platform
install flow layers the verified matching Confluence Platform Binaries asset
before it runs the startup command.

Tags use semantic versions. Release assets are immutable; publish a new patch tag
to correct a package.

Publication uses `tools/publish-release.sh`. The command must verify the exact
local set, upload only to a draft bound to the pushed source tag, verify the
downloaded draft before publication, and verify the immutable published release
again. Direct publication of unverified assets is outside this contract.
