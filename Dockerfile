ARG BASE_IMAGE=cgr.dev/chainguard/wolfi-base:latest
FROM ${BASE_IMAGE} AS build_flood
LABEL stage=build

WORKDIR /build

RUN --mount=type=cache,target=/var/cache,sharing=locked apk upgrade && apk add bash ca-certificates curl jq nodejs-24 pnpm tzdata

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
cd flood
sed -i -e 's/npm run/pnpm run/g' package.json
export HUSKY=0 CI=true
pnpm install --ignore-pnpmfile --ignore-scripts --ignore-workspace --frozen-lockfile --no-hoist --no-runtime
pnpm run build
pnpm pack
unset HUSKY CI
mv flood-*.tgz /build/flood.tgz
ENDRUN

# Build flood
FROM ${BASE_IMAGE} AS flood
ARG SOURCE_DATE_EPOCH=0
RUN --mount=type=cache,target=/var/cache,sharing=locked \
    --mount=type=bind,from=build_flood,source=/build,target=/mnt/build \
    --mount=type=bind,source=files,target=/mnt/files <<ENDRUN
set -uex
umask 0022
apk add --no-interactive bash coreutils curl mediainfo nodejs-24 pnpm tzdata
mkdir -p /opt/flood
export PNPM_HOME=/opt/flood
export PATH="$PNPM_HOME/bin:$PATH"
pnpm install --global --ignore-pnpmfile --ignore-scripts --ignore-workspace --no-hoist --no-lockfile --no-optional --offline --production /mnt/build/flood.tgz
cp -a /mnt/files/. /
find /docker-entrypoint.d -type f -regex '.*\.\(sh\|envsh\)$' -print0 | xargs -r0 chmod +x
chmod +x /docker-entrypoint.sh
find / -xdev -exec touch -hd "@${SOURCE_DATE_EPOCH}" {} + || true
ENDRUN

VOLUME [ "/flood", "/ipc/flood", "/ipc/rtorrent", "/downloads" ]
USER nonroot
ENTRYPOINT [ "/docker-entrypoint.sh" ]
CMD [ "flood", "--rundir=/flood", "--allowedpath=/downloads", "--allowedpath=/ipc/rtorrent", "--port=/ipc/flood/flood.sock", "--baseuri=/flood" ]
