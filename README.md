# Caddy images for `linux/amd64` + `linux/arm64` on GHCR

[![Build and publish Caddy image](https://github.com/philippdormann/caddy/actions/workflows/build.yml/badge.svg)](https://github.com/philippdormann/caddy/actions/workflows/build.yml)

Automatically tracks [upstream Caddy releases](https://github.com/caddyserver/caddy/releases)
and publishes multi-arch images to `ghcr.io/philippdormann/caddy` — without waiting
for the [Docker Official Images pipeline](https://github.com/caddyserver/caddy-docker/issues/417),
which typically lags new releases by hours and builds architectures one at a time.

```bash
docker pull ghcr.io/philippdormann/caddy:2
```

## Tags

All tags are Alpine-based and multi-arch (`linux/amd64`, `linux/arm64`):

| Tag | Example | Follows |
| --- | --- | --- |
| `2.11.9`, `2.11.9-alpine` | full version | upstream release |
| `2.11`, `2.11-alpine` | minor | latest `2.11.x` build |
| `2`, `2-alpine` | major | latest `2.x` build |
| `latest`, `alpine` | floating | latest stable build |
| `2.11.9-20261106-15` | dated build | immutable: one unique tag per build (`<version>-<date>-<run>`), never re-pushed — pin this for reproducible deployments |

## How it works

- A scheduled workflow runs **every 6 hours** and asks the GitHub API for the
  latest stable upstream Caddy release.
- It resolves the current `alpine:3` base image digest and compares it against
  the `org.opencontainers.image.base.digest` label of the already published image.
- It rebuilds (with `--pull`, so the base is always fresh) and pushes **only** when
  the Caddy version is new or the Alpine base changed. Otherwise the run is a no-op.
- The build uses the **digest-pinned** base (`alpine:3@sha256:…`), so there is no
  gap between the checked digest and the built image, and the exact base is
  recorded in the image labels (`org.opencontainers.image.base.*`).
- Binaries are the official upstream release tarballs, verified with `sha512sum`
  against the `checksums.txt` published alongside each upstream release.
- You can also trigger a build manually via **Actions → Build and publish Caddy image →
  Run workflow**, optionally pinning a version or forcing a rebuild.

## Supply-chain security

- Upstream release tarballs are **Sigstore-verified** (`cosign verify-blob`
  against the upstream release workflow identity) before every build, and each
  tarball's **sha512** is re-checked inside the Dockerfile.
- Published images are signed keyless with **Cosign**:

  ```bash
  cosign verify \
    --certificate-identity "https://github.com/philippdormann/caddy/.github/workflows/build.yml@refs/heads/main" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    ghcr.io/philippdormann/caddy:2
  ```

- Every build attaches an **SBOM** and **SLSA provenance** attestation, and is
  scanned with **Trivy** (findings in code scanning; fixable CRITICAL
  OS/library CVEs fail the build). See [SECURITY.md](SECURITY.md).

## Building locally

The Dockerfile consumes upstream artifacts from `./artifacts/` (populated and
Sigstore-verified by CI). To reproduce a build locally:

```bash
version=2.11.9
mkdir -p artifacts
for f in checksums.txt checksums.txt.sig checksums.txt.pem \
         linux_amd64.tar.gz linux_arm64.tar.gz; do
  curl -fsSLO "https://github.com/caddyserver/caddy/releases/download/v${version}/caddy_${version}_${f}"
done
mv caddy_* checksums* artifacts/
docker buildx build --build-arg CADDY_VERSION="${version}" --build-arg BASE_DIGEST=local .
```

`ALPINE_PIN` has no default: local builds must pass the exact digest, e.g.
`--build-arg ALPINE_PIN="3@$(docker buildx imagetools inspect alpine:3 | grep -m1 Digest: | awk '{print $2}')"`.
CI passes the digest-pinned `3@sha256:…` reference it resolved and verified.
To reproduce a published build exactly, inspect its
`org.opencontainers.image.base.digest` label and pass that digest.

## Differences vs. the official `library/caddy` image

- Only `linux/amd64` + `linux/arm64` (no armv6/v7, ppc64le, riscv64, s390x, Windows).
- Base tracks rolling `alpine:3` for freshness instead of a pinned Alpine minor,
  so security rebuilds land automatically — but every build uses the
  **digest-pinned** base it resolved (`alpine:3@sha256:…`), never the floating tag.
- No `builder`/`xcaddy` variant (add one if needed — see the official
  [caddy-docker](https://github.com/caddyserver/caddy-docker) repo for reference).
- Full-version tags (e.g. `2.11.9`) move if the Alpine base is rebuilt, same as
  official image rebuilds. Pin by digest or use the immutable dated build tags
  (e.g. `2.11.9-20261106-15`) if you need an immutable reference.
- The runtime image is built in two stages: build tooling (`libcap`) never
  ships, and the build fails if the `cap_net_bind_service` file capability
  does not survive into the final image.

## License

Apache-2.0 (see [LICENSE](LICENSE)). The Dockerfile derives from the
[official caddy-docker image](https://github.com/caddyserver/caddy-docker)
(also Apache-2.0); Caddy itself is by Light Code Labs / the Caddy authors.
