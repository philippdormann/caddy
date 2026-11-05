# Caddy mirror image - tracks upstream caddyserver/caddy releases.
# https://github.com/philippdormann/caddy
#
# Built for linux/amd64 + linux/arm64 only. The base follows the rolling
# alpine:3 tag, but every build must name the exact digest via ALPINE_PIN
# (CI resolves it fresh each run) - there is no floating default, so a build
# can never silently float on an unpinned base. This differs from the
# official image, which pins the Alpine minor in the Dockerfile instead.
#
# Local builds: pass the pinned digest explicitly, e.g.:
#   pin="3@$(docker buildx imagetools inspect alpine:3 | grep -m1 Digest: | awk '{print $2}')
#   docker buildx build --build-arg ALPINE_PIN="${pin}" --build-arg ... .
# (CI downloads the upstream artifacts and verifies the Sigstore signature
# before building; see .github/workflows/build.yml.)
ARG ALPINE_PIN

# Stage 1: integrity-check + prepare the binary.
# Build tooling (libcap) never lands in the runtime image.
FROM alpine:${ALPINE_PIN} AS fetcher
ARG CADDY_VERSION
ARG TARGETARCH
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
	chmod +x /out/caddy

# Stage 2: minimal runtime image.
FROM alpine:${ALPINE_PIN}

ARG ALPINE_PIN
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

# setcap lives in the final image only transiently: installed, applied and
# removed again within a single layer, so no build tooling ships.
# The getcap assertion fails the build if the capability is not effective.
RUN set -eux; \
	apk add --no-cache libcap; \
	setcap cap_net_bind_service=+p /usr/bin/caddy; \
	chmod +x /usr/bin/caddy; \
	getcap /usr/bin/caddy | grep -q cap_net_bind_service; \
	apk del libcap; \
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
	org.opencontainers.image.base.name="alpine:${ALPINE_PIN}" \
	org.opencontainers.image.base.digest="${BASE_DIGEST}"

EXPOSE 80
EXPOSE 443
EXPOSE 443/udp
EXPOSE 2019

WORKDIR /srv

CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
