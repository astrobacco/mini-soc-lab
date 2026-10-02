#!/bin/sh
# Phase 1 (runs on plain FreeBSD 14): install our config, then convert the
# machine into OPNsense with the official opnsense-bootstrap script.
# The VM has to be rebooted afterwards; setup.sh does that with "vagrant reload".
set -eu

RELEASE="${OPNSENSE_RELEASE:?OPNSENSE_RELEASE not set}"
BOOTSTRAP_URL="https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in"

if [ -f /usr/local/opnsense/version/core ]; then
    echo "[fw] OPNsense is already installed - skipping bootstrap"
    exit 0
fi

echo "[fw] Writing Mini-SOC config.xml"
# OPNsense regenerates ~vagrant/.ssh/authorized_keys from config.xml on every
# boot, so the key Vagrant generated for this VM must be stored in the config.
keys_b64=$(openssl base64 -A < /home/vagrant/.ssh/authorized_keys)
mkdir -p /conf
sed "s|{{VAGRANT_AUTHORIZED_KEYS_B64}}|${keys_b64}|" /tmp/config.xml.tpl > /conf/config.xml

echo "[fw] Downloading opnsense-bootstrap"
fetch -q -o /tmp/opnsense-bootstrap.sh "$BOOTSTRAP_URL"
# The upstream script ends with "reboot". We reboot from the host instead, so
# Vagrant notices the reboot and waits for SSH properly.
sed -i '' 's/^[[:space:]]*reboot$/	echo "[fw] bootstrap finished - reboot pending"/' /tmp/opnsense-bootstrap.sh

echo "[fw] Converting FreeBSD into OPNsense ${RELEASE} (takes 5-15 minutes)"
sh /tmp/opnsense-bootstrap.sh -r "$RELEASE" -y
