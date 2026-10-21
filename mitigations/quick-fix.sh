#!/usr/bin/env bash
# quick-fix.sh - emergency mitigation for the PHP2Shell attack surface.
#
# Both CVE-2026-109618 and CVE-2026-109619 claims ride on the session
# upload-progress mechanism. The vendor-recommended stopgap until patched
# PHP is deployed is one directive:
#
#     session.upload_progress.enabled = Off
#
# Strategy: drop a marker .ini into every PHP config *scan* dir (scan files
# are parsed after php.ini, so last-one-wins beats any earlier "On", no
# matter how many inis are misconfigured), plus php_admin_flag in every FPM
# pool (pool overrides all inis). Idempotent, revertible.
#
# The upstream variant (eness repo quick-fix/run.sh) shipped truncated
# mid-heredoc and cannot execute; this is the complete rewrite, verified in
# a live container (see ../writeups/).
#
# Usage:
#   ./quick-fix.sh            apply
#   ./quick-fix.sh --check    report effective state, change nothing
#   ./quick-fix.sh --dry-run  print what would change
#   ./quick-fix.sh --revert   remove the drop-ins, restore pools
#   ./quick-fix.sh --restart  best-effort reload of php services
set -euo pipefail

CONTENT="; added by php2shell quick-fix - remove with quick-fix.sh --revert
session.upload_progress.enabled = Off"
DROPIN_NAME="zz-php2shell-quickfix.ini"
STATE_DIR="${STATE_DIR:-/var/lib/php2shell-quickfix}"
DRY=0

info() { echo "[*] $*"; }
ok()   { echo "[+] $*"; }
warn() { echo "[!] $*"; }
die()  { echo "[-] $*" >&2; exit 1; }

MODE="apply"
case "${1:-}" in
    --check)   MODE="check" ;;
    --dry-run) MODE="apply"; DRY=1 ;;
    --revert)  MODE="revert" ;;
    --restart) MODE="restart" ;;
    ""|--apply) ;;
    *) die "unknown option: $1 (use --check/--dry-run/--revert/--restart)" ;;
esac

find_scan_dirs() {
    # Prefer what the runtime itself reports, fall back to the known layouts
    # (official Docker images + distro packages).
    if command -v php >/dev/null 2>&1; then
        php --ini 2>/dev/null | sed -n 's/^Scan this dir:[[:space:]]*//p'
    fi
    for d in /usr/local/etc/php/conf.d /etc/php/*/apache2/conf.d \
             /etc/php/*/fpm/conf.d /etc/php/*/cli/conf.d; do
        [ -d "$d" ] && echo "$d"
    done | sort -u
}

find_pool_confs() {
    for p in /etc/php/*/fpm/pool.d/*.conf; do
        [ -f "$p" ] && echo "$p"
    done | sort -u
}

effective_state() {
    # ini_get() on this flag: "1" when On (the default), "" when Off.
    if command -v php >/dev/null 2>&1; then
        v="$(php -r 'echo ini_get("session.upload_progress.enabled");' 2>/dev/null)" || v=""
        if [ "$v" = "1" ]; then echo "ENABLED (vulnerable surface)"; else echo "disabled"; fi
        return
    fi
    echo "unknown (no usable php CLI; check web SAPI with phpinfo())"
}

do_apply() {
    local hit=0 d p
    for d in $(find_scan_dirs); do
        hit=1
        if [ "$DRY" = 1 ]; then
            echo "would write: $d/$DROPIN_NAME"
            continue
        fi
        [ -w "$d" ] || { warn "not writable: $d"; continue; }
        printf '%s\n' "$CONTENT" > "$d/$DROPIN_NAME"
        ok "drop-in: $d/$DROPIN_NAME"
    done
    for p in $(find_pool_confs); do
        hit=1
        grep -qF 'php_admin_flag[session.upload_progress.enabled]' "$p" 2>/dev/null \
            && { ok "pool already flagged: $p"; continue; }
        if [ "$DRY" = 1 ]; then
            echo "would append php_admin_flag to: $p"
            continue
        fi
        mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"
        cp -p "$p" "$STATE_DIR/$(echo "$p" | tr '/' '_')"
        printf '\n; php2shell quick-fix\nphp_admin_flag[session.upload_progress.enabled] = off\n' >> "$p"
        ok "pool flagged: $p"
    done
    [ "$hit" = 1 ] || die "no PHP config scan dirs / FPM pools found - is PHP installed?"
    [ "$DRY" = 1 ] || info "activate: $0 --restart   (in Docker: docker restart <container>)"
}

do_check() {
    local d hit=0
    info "effective state (this SAPI): $(effective_state)"
    for d in $(find_scan_dirs); do
        hit=1
        [ -f "$d/$DROPIN_NAME" ] && ok "mitigated: $d" || warn "exposed: $d"
    done
    [ "$hit" = 1 ] || die "no PHP config scan dirs found - is PHP installed?"
}

do_revert() {
    local d p flat hit=0
    for d in $(find_scan_dirs); do
        if [ -f "$d/$DROPIN_NAME" ]; then
            rm -f "$d/$DROPIN_NAME" && ok "removed: $d/$DROPIN_NAME"; hit=1
        fi
    done
    if [ -d "$STATE_DIR" ]; then
        for p in $(find_pool_confs); do
            flat="$STATE_DIR/$(echo "$p" | tr '/' '_')"
            [ -f "$flat" ] && cp -p "$flat" "$p" && rm -f "$flat" \
                && ok "pool restored: $p" && hit=1
        done
    fi
    [ "$hit" = 1 ] || warn "nothing to revert"
    info "restart PHP to reload."
}

do_restart() {
    local done_any=0 svc
    for svc in php8.3-fpm php8.2-fpm php8.1-fpm php-fpm apache2 httpd lsws litespeed; do
        if command -v systemctl >/dev/null 2>&1 \
           && systemctl list-unit-files 2>/dev/null | grep -q "^$svc\.service"; then
            if [ "$svc" = apache2 ] && command -v apachectl >/dev/null 2>&1; then
                apachectl configtest >/dev/null 2>&1 || { warn "apache configtest FAILED - not reloading"; continue; }
            fi
            systemctl reload-or-restart "$svc" && ok "restarted $svc"
            done_any=1
        fi
    done
    [ "$done_any" = 1 ] || warn "no systemd PHP service found; use your stack's restart path"
}

if [ "$(id -u)" != 0 ] && [ "$MODE" != "check" ] && [ "$MODE" != "restart" ]; then
    die "run as root (writing PHP config)"
fi

case "$MODE" in
    check)   do_check ;;
    apply)   do_apply ;;
    revert)  do_revert ;;
    restart) do_restart ;;
esac
