#!/usr/bin/env bash
# Run this ON target (vagrant ssh target) to remediate exercise 02: moves
# DVWA's default security level to "high", which defeats this exercise's
# UNION-based injection (same vulnerable-looking SQLi page, but the query
# is built safely at that level) - this is the "quick config fix" a real
# admin could ship immediately, versus "rewrite the app" as the proper
# long-term fix. Re-run exercises/02-dvwa-sqli/README.md's Step 2 (with a
# fresh login/session) afterwards to confirm it no longer works.
set -euo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"

CONF=/var/www/html/legacy/config/config.inc.php
sed -i "s|^\(\$_DVWA\[ 'default_security_level' \] *=\).*|\1 'high';|" "$CONF"

echo "Fixed: DVWA default security level is now 'high' on $(hostname)."
echo "A browser that already has a 'security=low' cookie from before won't see this"
echo "change until it logs in fresh or sets DVWA Security -> High itself - that's a"
echo "real limitation of a cookie-remembered setting, not a bug in this fix."
