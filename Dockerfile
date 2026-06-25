ARG BASE_IMAGE=cgr.dev/chainguard/wolfi-base:latest
FROM ${BASE_IMAGE} AS build_flood
LABEL stage=build

WORKDIR /build

RUN --mount=type=cache,target=/var/cache/apk,sharing=locked apk upgrade && apk add bash ca-certificates curl jq nodejs-24 npm pnpm tar

SHELL ["/bin/bash", "-c"]

RUN --mount=type=bind,source=.github/dependency-versions.json,target=/build/dv.json \
    --mount=type=bind,source=scripts/fetch-dep.sh,target=/usr/local/bin/fetch-dep <<ENDRUN
set -uex
umask 0022
fetch-dep flood
ENDRUN

RUN <<ENDRUN
set -uex
umask 0022
export HUSKY=0
cd flood
pnpm install --frozen-lockfile
npm run build
npm pack --ignore-scripts
mv flood-*.tgz /build/flood.tgz
ENDRUN

# Build flood
FROM ${BASE_IMAGE} AS flood
ARG SOURCE_DATE_EPOCH=0
RUN --mount=type=cache,target=/var/cache/apk,sharing=locked \
    --mount=type=bind,from=build_flood,source=/build,target=/mnt/build \
    --mount=type=bind,source=files,target=/mnt/files <<ENDRUN
set -uex
umask 0022
apk add --no-interactive bash coreutils curl mediainfo nodejs-24 npm tzdata
npm install --global --production /mnt/build/flood.tgz
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
