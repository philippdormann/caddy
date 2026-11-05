# Caddy mirror image - tracks upstream caddyserver/caddy releases.
# https://github.com/philippdormann/caddy
#
# Built for linux/amd64 + linux/arm64 only. Base is alpine:3 (rolling) so
# regular rebuilds pick up Alpine security fixes without waiting for a new
# Caddy release. This intentionally differs from the official image, which
# pins the Alpine minor version.
#
# Local builds need the upstream artifacts in ./artifacts/ first, e.g.:
#   version=2.11.9
#   mkdir -p artifacts
#   for f in checksums.txt checksums.txt.sig checksums.txt.pem \
#            linux_amd64.tar.gz linux_arm64.tar.gz; do
#     curl -fsSLO "https://github.com/caddyserver/caddy/releases/download/v${version}/caddy_${version}_${f}"
#   done
#   mv caddy_* checksums* artifacts/
# (CI downloads these and verifies the Sigstore signature before building.)
ARG ALPINE_VERSION=3

# Stage 1: integrity-check + prepare the binary.
# Build tooling (libcap) never lands in the runtime image.
FROM alpine:${ALPINE_VERSION} AS fetcher
ARG CADDY_VERSION
ARG TARGETARCH
RUN apk add --no-cache libcap
# Populated and Sigstore-verified by CI (see .github/workflows/build.yml).
COPY artifacts/checksums.txt /tmp/caddy_checksums.txt
COPY artifacts/caddy_*_linux_*.tar.gz /tmp/
RUN set -eux; \
	if [ -z "${CADDY_VERSION:-}" ]; then echo "CADDY_VERSION build arg is required" >&2; exit 1; fi; \
	case "${TARGETARCH}" in \
		amd64) binArch='amd64' ;; \
		arm64) binArch='arm64' ;; \
		*) echo >&2 "error: unsupported architecture (${TARGETARCH}) - this image supports amd64 and arm64 only"; exit 1 ;; \
	esac; \
	tarball="/tmp/caddy_${CADDY_VERSION}_linux_${binArch}.tar.gz"; \
	(cd /tmp && grep -E "  caddy_${CADDY_VERSION}_linux_${binArch}\.tar\.gz$" caddy_checksums.txt | sha512sum -c -); \
	mkdir -p /out; \
	tar x -z -f "${tarball}" -C /out caddy; \
	setcap cap_net_bind_service=+p /out/caddy; \
	chmod +x /out/caddy; \
	getcap /out/caddy

# Stage 2: minimal runtime image.
FROM alpine:${ALPINE_VERSION}

ARG ALPINE_VERSION
ARG CADDY_VERSION
ARG BASE_DIGEST=unknown
ARG TARGETARCH

RUN apk add --no-cache \
	ca-certificates \
	curl \
	mailcap

RUN set -eux; \
	mkdir -p \
		/config/caddy \
		/data/caddy \
		/etc/caddy \
		/usr/share/caddy \
	; \
	chmod 1777 /config/caddy /data/caddy; \
	wget -O /etc/caddy/Caddyfile "https://github.com/caddyserver/dist/raw/33ae08ff08d168572df2956ed14fbc4949880d94/config/Caddyfile"; \
	wget -O /usr/share/caddy/index.html "https://github.com/caddyserver/dist/raw/33ae08ff08d168572df2956ed14fbc4949880d94/welcome/index.html"

COPY --from=fetcher /out/caddy /usr/bin/caddy

# Fail the build if file capabilities did not survive the stage copy, then
# smoke-test the binary for this platform (emulated via QEMU for arm64).
RUN set -eux; \
	getcap /usr/bin/caddy | grep -q cap_net_bind_service || \
		{ echo "file capabilities lost in COPY --from=fetcher" >&2; exit 1; }; \
	chmod +x /usr/bin/caddy; \
	caddy version

# See https://caddyserver.com/docs/conventions#file-locations for details
ENV XDG_CONFIG_HOME=/config
ENV XDG_DATA_HOME=/data

LABEL org.opencontainers.image.title="Caddy" \
	org.opencontainers.image.description="a powerful, enterprise-ready, open source web server with automatic HTTPS written in Go" \
	org.opencontainers.image.url="https://caddyserver.com" \
	org.opencontainers.image.documentation="https://caddyserver.com/docs" \
	org.opencontainers.image.vendor="Light Code Labs" \
	org.opencontainers.image.licenses="Apache-2.0" \
	org.opencontainers.image.source="https://github.com/philippdormann/caddy" \
	org.opencontainers.image.version="${CADDY_VERSION}" \
	org.opencontainers.image.base.name="alpine:${ALPINE_VERSION}" \
	org.opencontainers.image.base.digest="${BASE_DIGEST}"

EXPOSE 80
EXPOSE 443
EXPOSE 443/udp
EXPOSE 2019

WORKDIR /srv

CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
