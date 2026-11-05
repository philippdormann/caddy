# Security policy

## Supported versions

Only the latest published build (floating tags `latest`/`alpine`/`2`) is
supported. It always tracks the latest stable upstream Caddy release on a
rolling `alpine:3` base, rebuilt automatically (see below).

## Rebuild policy

The [build workflow](.github/workflows/build.yml) runs every 6 hours and
rebuilds when either changes:

- a new stable upstream Caddy release, or
- a new `alpine:3` base image (picks up Alpine security fixes without waiting
  for a Caddy release).

## Supply-chain guarantees

- Upstream release artifacts are verified with **Sigstore** (`cosign
  verify-blob` against the upstream release workflow identity) before the
  build, and each tarball's **sha512** is re-checked inside the Dockerfile.
- Published images are signed keyless with **Cosign**. Verify with:

  ```bash
  cosign verify \
    --certificate-identity "https://github.com/philippdormann/caddy/.github/workflows/build.yml@refs/heads/main" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    ghcr.io/philippdormann/caddy:2
  ```

- Every build attaches an **SBOM** and **SLSA provenance** attestation, and is
  scanned with **Trivy** (results in code scanning; fixable CRITICAL OS/library
  CVEs fail the build).

## Reporting a vulnerability

Please use [private vulnerability reporting](../../security/advisories/new)
instead of opening a public issue. Vulnerabilities in Caddy itself or in
Alpine packages are best reported upstream first
([caddy](https://github.com/caddyserver/caddy/security),
[Alpine](https://security.alpinelinux.org/)); reports specific to this
mirror's build/publishing pipeline belong here.
