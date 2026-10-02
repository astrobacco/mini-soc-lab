#!/usr/bin/env bash
# Runs first on every Linux VM: routing into the lab, basic packages, time zone.
set -euo pipefail
source /tmp/minisoc-common/lib.sh

log "Base setup (lab IP ${LAB_IP}, gateway ${LAB_GATEWAY})"

# Route all lab networks (10.10.0.0/16) through the OPNsense firewall.
# The default route stays on the NAT adapter, so downloads never depend on the
# firewall and Vagrant keeps working even if the firewall is down.
iface=$(ip -o -4 addr show | awk -v ip="${LAB_IP}" '$4 ~ "^"ip"/" {print $2}')
if [ -z "$iface" ] && command -v nmcli >/dev/null; then
    # NetworkManager (Kali) may have replaced Vagrant's static address with a DHCP
    # attempt: take the NIC that is not the NAT adapter (the default route's)
    nat=$(ip -o route show default | awk '{print $5; exit}')
    iface=$(ip -o link | awk -F': ' -v nat="$nat" '$2 != "lo" && $2 != nat {print $2; exit}')
fi
[ -n "$iface" ] || die "no interface with ${LAB_IP} found"
if command -v nmcli >/dev/null && systemctl is-active --quiet NetworkManager; then
    log "Pinning ${LAB_IP} on ${iface} in NetworkManager"
    nmcli -t -f NAME con show | grep -qx minisoc-lab && nmcli con delete minisoc-lab >/dev/null
    nmcli con add type ethernet ifname "$iface" con-name minisoc-lab \
        ipv4.method manual ipv4.addresses "${LAB_IP}/24" ipv4.never-default yes \
        ipv4.routes "10.10.0.0/16 ${LAB_GATEWAY}" ipv6.method disabled >/dev/null
    nmcli con up minisoc-lab >/dev/null
elif command -v netplan >/dev/null && [ -d /etc/netplan ]; then
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
else
    # Kali and other non-netplan systems: a small boot-time unit sets the route
    cat > /etc/systemd/system/minisoc-route.service <<UNIT
[Unit]
Description=Mini-SOC: route lab networks via the firewall
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/ip route replace 10.10.0.0/16 via ${LAB_GATEWAY} dev ${iface}

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable --now minisoc-route.service >/dev/null
fi

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
