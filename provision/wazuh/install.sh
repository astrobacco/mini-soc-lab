#!/usr/bin/env bash
# wazuh VM: Wazuh all-in-one (indexer + manager + dashboard) plus the lab
# configuration: syslog from OPNsense, agent groups, custom rules and the
# DFIR-IRIS integration.
set -euo pipefail
source /opt/minisoc/lib.sh
FILES=/tmp/minisoc-wazuh
OSSEC=/var/ossec

# ---------------------------------------------------------------- install
if [ ! -x "${OSSEC}/bin/wazuh-control" ]; then
    log "Installing Wazuh ${WAZUH_VERSION} all-in-one (this takes 10-20 minutes)"
    cd /root
    curl -fsSLO "https://packages.wazuh.com/${WAZUH_VERSION%.*}/wazuh-install.sh"
    bash wazuh-install.sh --all-in-one > /root/wazuh-install.log 2>&1 \
        || { tail -30 /root/wazuh-install.log; die "Wazuh installation failed (see /root/wazuh-install.log)"; }
    # no unattended upgrades of Wazuh: indexer, manager and agents must match
    apt-mark hold wazuh-indexer wazuh-manager wazuh-dashboard filebeat >/dev/null
fi

# ---------------------------------------------------------------- admin password
log "Setting the dashboard 'admin' password to the lab password"
PWTOOL=/usr/share/wazuh-indexer/plugins/opensearch-security/tools/wazuh-passwords-tool.sh
if ! curl -sfk -u "admin:${LAB_PASSWORD}" https://127.0.0.1:9200 >/dev/null; then
    bash "$PWTOOL" -u admin -p "${LAB_PASSWORD}" > /root/wazuh-password.log 2>&1 \
        || { tail -20 /root/wazuh-password.log; die "could not change the admin password"; }
fi

# ---------------------------------------------------------------- manager config
log "Configuring the Wazuh manager"
install -o root -g wazuh -m 640 "${FILES}/minisoc_rules.xml" "${OSSEC}/etc/rules/minisoc_rules.xml"
install -o root -g wazuh -m 750 "${FILES}/custom-iris.py" "${OSSEC}/integrations/custom-iris.py"
# Wazuh's integrations are started through a shell wrapper that runs the .py
# file with Wazuh's bundled Python; the Slack wrapper is generic and reused.
install -o root -g wazuh -m 750 "${OSSEC}/integrations/slack" "${OSSEC}/integrations/custom-iris"

# Our additions live in their own <ossec_config> block (Wazuh merges all blocks),
# marked so that re-running this script replaces them instead of duplicating.
sed -i '/<!-- MINISOC BEGIN -->/,/<!-- MINISOC END -->/d' "${OSSEC}/etc/ossec.conf"
cat >> "${OSSEC}/etc/ossec.conf" <<EOF
<!-- MINISOC BEGIN -->
<ossec_config>
  <!-- OPNsense sends its firewall log (filterlog) and auth events via syslog -->
  <remote>
    <connection>syslog</connection>
    <port>514</port>
    <protocol>udp</protocol>
    <allowed-ips>10.10.10.1</allowed-ips>
    <local_ip>10.10.10.10</local_ip>
  </remote>

  <!-- Every alert with level >= 10 becomes an alert in DFIR-IRIS -->
  <integration>
    <name>custom-iris</name>
    <hook_url>https://10.10.10.20/alerts/add</hook_url>
    <api_key>${IRIS_API_KEY}</api_key>
    <level>10</level>
    <alert_format>json</alert_format>
  </integration>
</ossec_config>
<!-- MINISOC END -->
EOF

# Agent groups: agents pick their config up from the manager when they enroll.
for group in ids-sensor linux-servers; do
    if ! "${OSSEC}/bin/agent_groups" -l 2>/dev/null | grep -qw "$group"; then
        "${OSSEC}/bin/agent_groups" -a -g "$group" -q >/dev/null
    fi
    install -o wazuh -g wazuh -m 660 "${FILES}/groups/${group}/agent.conf" "${OSSEC}/etc/shared/${group}/agent.conf"
done

log "Checking the rule set"
"${OSSEC}/bin/wazuh-analysisd" -t >/dev/null 2>&1 || { "${OSSEC}/bin/wazuh-analysisd" -t; die "rule/config test failed"; }

systemctl restart wazuh-manager
wait_for "Wazuh API" 180 curl -sfk -o /dev/null -w '%{http_code}' https://127.0.0.1:55000/
wait_for "Wazuh dashboard" 300 curl -sfk -o /dev/null https://127.0.0.1/app/login

rm -rf "${FILES}"
log "Wazuh is ready: https://localhost:${PORT_WAZUH:-8444}  (user: admin)"
