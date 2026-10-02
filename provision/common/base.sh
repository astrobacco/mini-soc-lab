#!/usr/bin/env bash
# Runs first on every Linux VM: routing into the lab, basic packages, time zone.
set -euo pipefail
source /tmp/minisoc-common/lib.sh

log "Base setup (lab IP ${LAB_IP}, gateway ${LAB_GATEWAY})"

# Route all lab networks (10.10.0.0/16) through the OPNsense firewall.
# The default route stays on the NAT adapter, so downloads never depend on the
# firewall and Vagrant keeps working even if the firewall is down.
iface=$(ip -o -4 addr show | awk -v ip="${LAB_IP}" '$4 ~ "^"ip"/" {print $2}')
[ -n "$iface" ] || die "no interface with ${LAB_IP} found"
cat > /etc/netplan/60-minisoc.yaml <<NETPLAN
network:
  version: 2
  ethernets:
    ${iface}:
      routes:
        - to: 10.10.0.0/16
          via: ${LAB_GATEWAY}
NETPLAN
chmod 600 /etc/netplan/60-minisoc.yaml
netplan apply 2>/dev/null

grep -q minisoc.lab /etc/hosts || cat >> /etc/hosts <<HOSTS
# Mini-SOC lab
10.10.10.1   fw.minisoc.lab fw
10.10.10.10  wazuh.minisoc.lab wazuh
10.10.10.20  soc.minisoc.lab soc
10.10.10.30  sensor.minisoc.lab sensor
10.10.20.10  target.minisoc.lab target
10.10.66.10  kali.minisoc.lab kali
HOSTS

timedatectl set-timezone Europe/Zurich
install -d -m 755 /opt/minisoc
cp /tmp/minisoc-common/lib.sh /opt/minisoc/lib.sh
rm -rf /tmp/minisoc-common   # so a re-provision copies the folder fresh
log "Base setup done"
