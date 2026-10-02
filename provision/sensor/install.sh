#!/usr/bin/env bash
# sensor VM: Suricata network IDS.
# NIC 3 is plugged into the SERVERS network in promiscuous mode without an IP
# address: it silently receives a copy of all traffic there. Suricata inspects
# it with the Emerging Threats Open rules; alerts go to eve-alerts.json, which
# the Wazuh agent ships to the manager (agent group "ids-sensor").
set -euo pipefail
source /opt/minisoc/lib.sh
FILES=/tmp/minisoc-sensor

# ---------------------------------------------------------------- monitoring port
SNIFF_IF=$(ip -o link | awk -v mac="${SNIFF_MAC}" 'tolower($0) ~ mac {sub(":","",$2); print $2}')
[ -n "$SNIFF_IF" ] || die "monitoring interface with MAC ${SNIFF_MAC} not found"
log "Monitoring interface: ${SNIFF_IF}"

# Keep the port up, promiscuous and without an IP on every boot. NIC offloading
# is turned off so Suricata sees the packets as they were on the wire.
apt_install ethtool
cat > /etc/systemd/system/minisoc-sniff.service <<EOF
[Unit]
Description=Mini-SOC: prepare IDS monitoring interface ${SNIFF_IF}
Before=suricata.service
After=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/ip addr flush dev ${SNIFF_IF}
ExecStart=/usr/sbin/ip link set ${SNIFF_IF} up promisc on
ExecStart=-/usr/sbin/ethtool -K ${SNIFF_IF} gro off lro off tso off gso off

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now minisoc-sniff.service >/dev/null

# ---------------------------------------------------------------- suricata
if ! command -v suricata >/dev/null; then
    log "Installing Suricata (OISF stable PPA)"
    add-apt-repository -y ppa:oisf/suricata-stable >/dev/null
    apt_install suricata
fi
log "$(suricata -V)"

log "Writing Mini-SOC Suricata settings"
sed "s|{{SNIFF_IF}}|${SNIFF_IF}|" "${FILES}/minisoc.yaml" > /etc/suricata/minisoc.yaml
# The networks we defend. Everything else - including the RED network the
# attacker lives in - counts as "external", so inbound attack rules fire.
sed -i -e 's|^\(\s*\)HOME_NET:.*|\1HOME_NET: "[10.10.10.0/24,10.10.20.0/24]"|' \
       -e 's|^\(\s*\)EXTERNAL_NET:.*|\1EXTERNAL_NET: "!$HOME_NET"|' /etc/suricata/suricata.yaml
# Suricata reads include files after the main file; their sections replace the defaults.
grep -q '^include:' /etc/suricata/suricata.yaml || printf '\ninclude:\n  - /etc/suricata/minisoc.yaml\n' >> /etc/suricata/suricata.yaml

log "Downloading the Emerging Threats Open rule set"
suricata-update -q --no-test >/dev/null 2>&1 || suricata-update --no-test
# refresh the rules every night
cat > /etc/cron.d/minisoc-suricata-update <<'EOF'
30 3 * * * root suricata-update -q && suricatasc -c reload-rules >/dev/null 2>&1
EOF

log "Testing the configuration"
suricata -T -c /etc/suricata/suricata.yaml >/tmp/suricata-test.log 2>&1 \
    || { tail -20 /tmp/suricata-test.log; die "Suricata configuration test failed"; }
systemctl enable suricata >/dev/null
systemctl restart suricata
wait_for "Suricata to load its rules" 300 test -S /var/run/suricata/suricata-command.socket

# ---------------------------------------------------------------- wazuh agent
install_wazuh_agent ids-sensor

rm -rf "${FILES}"
log "Sensor ready: Suricata listens on ${SNIFF_IF} (SERVERS network)"
