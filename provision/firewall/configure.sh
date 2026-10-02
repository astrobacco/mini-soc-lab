#!/bin/sh
# Phase 2 (runs on OPNsense after the first reboot): lab password + sanity checks.
set -eu

if [ ! -f /usr/local/opnsense/version/core ]; then
    echo "[fw] OPNsense is not installed - did the bootstrap step fail?" >&2
    exit 1
fi

echo "[fw] Setting the root (web GUI) password"
printf '%s\n' "${LAB_PASSWORD:?}" | /usr/local/opnsense/scripts/shell/password.php root -h 0 >/dev/null 2>&1

echo "[fw] Reloading firewall rules"
configctl filter reload >/dev/null

echo "[fw] $(opnsense-version)"
for ifc in vtnet1 vtnet2 vtnet3; do
    printf '[fw]   %s %s\n' "$ifc" "$(ifconfig "$ifc" | awk '/inet /{print $2}')"
done
