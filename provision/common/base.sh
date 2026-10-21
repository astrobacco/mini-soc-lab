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
        connection.autoconnect yes connection.autoconnect-priority 999 \
        ipv4.method manual ipv4.addresses "${LAB_IP}/24" ipv4.never-default yes \
        ipv4.routes "10.10.0.0/16 ${LAB_GATEWAY}" ipv6.method disabled >/dev/null
    nmcli con up minisoc-lab >/dev/null
    # Stop NetworkManager from ever racing minisoc-lab with its own
    # auto-generated "Wired connection" DHCP profile for this NIC - seen in
    # practice losing just the extra 10.0.0.0/16 route (the primary address
    # still came from minisoc-lab) after a non-`vagrant up` VM restart, with
    # no error anywhere. no-auto-default removes the competing profile
    # entirely instead of just trying to out-prioritize it.
    mkdir -p /etc/NetworkManager/conf.d
    cat > /etc/NetworkManager/conf.d/90-minisoc-no-auto-default.conf <<CONF
[main]
no-auto-default=${iface}
CONF
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
fi

# Belt and braces on every backend, not just systems with neither NetworkManager
# nor netplan: a boot-time unit that unconditionally re-asserts the lab route
# after the network is up. The nmcli/netplan declarative routes above are the
# first line of defense and normally enough on their own, but a real incident
# showed NetworkManager's declarative ipv4.routes silently not being applied
# on an otherwise-successful boot (primary address present and correct, extra
# route just missing, no error logged anywhere) - this unit is what makes that
# self-healing on every subsequent boot instead of needing a manual
# `vagrant provision` to notice and fix it each time.
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

# Every box (bento/ubuntu, kalilinux/rolling) ships with cloud-init's own
# sshd_config.d/50-cloud-init.conf setting "PasswordAuthentication yes" and a
# vagrant:vagrant password - fine for Vagrant's own SSH-key based control
# connection (never uses the password), but it means anyone who reaches a VM
# over the lab network can log in with the single best-known default
# credential on the internet. Found by Greenbone as a Critical (9.8)
# finding. sshd takes the *first* value it sees for a directive, and
# Include processes sshd_config.d/*.conf alphabetically, so this file's name
# has to sort before "50-cloud-init.conf" to actually win.
cat > /etc/ssh/sshd_config.d/00-minisoc-harden.conf <<'EOF'
# Mini-SOC: disable password auth lab-wide (key-only). Must sort before
# 50-cloud-init.conf - sshd uses the first value seen for each directive.
PasswordAuthentication no
EOF
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
# Belt and braces: the password is also usable for local/FTP logins if
# anything else on a VM ever accepts password auth (e.g. vsftpd's
# local_enable) - lock it out entirely. Vagrant and sudo both work off the
# SSH key / NOPASSWD:ALL sudoers entry, neither needs this password.
passwd -l vagrant >/dev/null

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
