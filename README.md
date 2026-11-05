# Caddy images for `linux/amd64` + `linux/arm64` on GHCR

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

## How it works

- A scheduled workflow runs **every 6 hours** and asks the GitHub API for the
  latest stable upstream Caddy release.
- It resolves the current `alpine:3` base image digest and compares it against
  the `org.opencontainers.image.base.digest` label of the already published image.
- It rebuilds (with `--pull`, so the base is always fresh) and pushes **only** when
  the Caddy version is new or the Alpine base changed. Otherwise the run is a no-op.
- Binaries are the official upstream release tarballs, verified with `sha512sum`
  against the `checksums.txt` published alongside each upstream release.
- You can also trigger a build manually via **Actions → Build and publish Caddy image →
  Run workflow**, optionally pinning a version or forcing a rebuild.

## Differences vs. the official `library/caddy` image

- Only `linux/amd64` + `linux/arm64` (no armv6/v7, ppc64le, riscv64, s390x, Windows).
- Base is rolling `alpine:3` instead of a pinned Alpine minor, so security rebuilds
  land automatically.
- No `builder`/`xcaddy` variant (add one if needed — see the official
  [caddy-docker](https://github.com/caddyserver/caddy-docker) repo for reference).
- Full-version tags (e.g. `2.11.9`) move if the Alpine base is rebuilt, same as
  official image rebuilds. Pin by digest if you need an immutable reference.
