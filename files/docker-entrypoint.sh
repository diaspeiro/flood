#!/bin/sh

set -eu

if [ "$(basename "${1:-}")" = "flood" ]; then
while read -r f; do
    case "$f" in
        *.envsh) [ -x "$f" ] && . "$f" ;;
        *.sh)    [ -x "$f" ] && "$f" ;;
    esac
done << EOF
$(find "/docker-entrypoint.d/" -follow -type f | sort -V)
EOF
fi

exec "$@"
