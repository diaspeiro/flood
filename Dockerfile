ARG BASE_IMAGE=cgr.dev/chainguard/wolfi-base:latest
FROM ${BASE_IMAGE} AS build_flood
LABEL stage=build

ARG FLOOD_VERSION

WORKDIR /build

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked apk upgrade && apk add bash git nodejs-24 npm pnpm

SHELL ["/bin/bash", "-c"]

# Setup build directory
RUN <<ENDRUN
set -uex
umask 0022
clone_repo_version() { git -c advice.detachedHead=false clone --depth 1 --branch "$2" "https://github.com/$1" "${@:3}"; }
clone_repo_version "jesec/flood" "v${FLOOD_VERSION}"
ENDRUN

# Build flood
RUN <<ENDRUN
set -uex
umask 0022
cd flood
pnpm install --frozen-lockfile
npm run build
npm pack --ignore-scripts
cp "flood-${FLOOD_VERSION}.tgz" /tmp/flood.tgz
ENDRUN

FROM ${BASE_IMAGE} AS flood
ARG SOURCE_DATE_EPOCH=0
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked \
    --mount=type=bind,from=build_flood,source=/build,target=/mnt/build \
    --mount=type=bind,source=files,target=/mnt/files <<ENDRUN
set -uex
umask 0022
apk add --no-interactive bash coreutils curl mediainfo nodejs-24 npm tzdata
npm install -g "/mnt/build/flood-${FLOOD_VERSION}.tgz"
cp -a /mnt/files/. /
find /docker-entrypoint.d -type f -regex '.*\.\(sh\|envsh\)$' -print0 | xargs -r0 chmod +x
chmod +x /docker-entrypoint.sh
rm -rf /var/cache/apk/* /var/cache/ldconfig /var/cache/misc
find / -xdev -exec touch -hd "@${SOURCE_DATE_EPOCH}" {} + || true
ENDRUN                                                                                                                                                                                                                                                                        

VOLUME [ "/flood", "/ipc/flood", "/ipc/rtorrent", "/downloads" ]
USER nonroot
ENTRYPOINT [ "/docker-entrypoint.sh" ]
CMD [ "flood", "--rundir=/flood", "--allowedpath=/downloads", "--allowedpath=/ipc/rtorrent", "--port=/ipc/flood/flood.sock", "--baseuri=/flood" ]
