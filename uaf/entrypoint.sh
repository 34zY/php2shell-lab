#!/usr/bin/env bash
set -euo pipefail

BIN="${PHP_BIN:-/usr/local/bin/php-stock}"
PORT="${PORT:-8099}"

mkdir -p /tmp/uaf-sess

# USE_ZEND_ALLOC=0 routes every allocation through the system allocator so
# valgrind (and ASAN, where it works) can see them. Required for the
# experiment: PHP's own mm would hide reads of freed memory.
export USE_ZEND_ALLOC=0

# -q: suppress the memcheck banner; --trace-children: follow any child
# processes; --log-fd=1 keeps reports on the container stdout (docker logs).
# php -S is single-process: a UAF abort on php-ablated kills the server.
exec valgrind -q --tool=memcheck --trace-children=yes --num-callers=24 \
     --log-fd=1 --error-limit=no \
     "$BIN" -c /app/php.ini -S "0.0.0.0:$PORT" -t /app/webroot
