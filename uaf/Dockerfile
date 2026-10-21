# UAF proof environment for the CVE-2026-109618 *claim*: PHP 8.4.4 built
# twice from the pinned release tarball, observed under valgrind memcheck.
#
#   php-stock    = released source. The progress-trigger PoC stays clean:
#                  ext/session/session.c keeps progress->data referenced
#                  (Z_TRY_ADDREF), so there is no UAF to observe.
#   php-ablated  = same source with exactly that one line removed.
#                  The trigger then produces memcheck's
#                  "Invalid read of size ... (heap use after free)" report,
#                  the valgrind twin of the writeup's ASAN stack.
#
# Why valgrind and not ASAN: AddressSanitizer self-crashes at init
# (infinite "AddressSanitizer:DEADLYSIGNAL") on the Docker Desktop WSL2 VM
# kernel (vsyscall/vDSO incompatibility). memcheck has no such dependency
# and reports the same heap-use-after-free. On Linux/macOS hosts an ASAN
# build works too; the sed ablation is identical.
#
# The ablated build exists ONLY to show which single line the claim depends
# on. It is not a supported PHP build. Local testing only.
FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PHP_VER=8.4.4 \
    PHP_SHA256=719551f50a81961f802aa9102bf4a1a0b5a315074330ab37bc8035a15f4be71b

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential autoconf bison re2c pkg-config \
      ca-certificates curl procps valgrind \
 && rm -rf /var/lib/apt/lists/*

# configure spawns short-lived conftest probes; valgrind's startup cost
# would dominate, so the tool is attached at serve time, not at build time.
WORKDIR /src
RUN curl -fsSL -o php.tar.gz "https://www.php.net/distributions/php-${PHP_VER}.tar.gz" \
 && echo "${PHP_SHA256}  php.tar.gz" | sha256sum -c - \
 && tar xzf php.tar.gz && rm php.tar.gz

WORKDIR /src/php-${PHP_VER}

RUN ./configure \
      --disable-all --enable-cli --enable-session --enable-debug \
      CFLAGS="-O1 -g -fno-omit-frame-pointer" \
 && make -j"$(nproc)" \
 && cp sapi/cli/php /usr/local/bin/php-stock

# Ablation: drop the reference that keeps progress->data alive.
RUN sed -i 's/^\([[:space:]]*\)Z_TRY_ADDREF(progress->data);/\1\/* ABLATED *\//' ext/session/session.c \
 && grep -q "ABLATED" ext/session/session.c \
 && ! grep -q "^[[:space:]]*Z_TRY_ADDREF(progress->data);" ext/session/session.c \
 && make -j"$(nproc)" \
 && cp sapi/cli/php /usr/local/bin/php-ablated

COPY php.ini /app/php.ini
COPY webroot/ /app/webroot/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8099
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
