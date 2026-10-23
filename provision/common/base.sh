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
    # Belt and braces #2: Vagrant's own `private_network` plugin reconfigures
    # this interface's IP on *every* `vagrant up` (even --no-provision, even
    # just restarting an already-built VM) - not only at first boot. That
    # reconfiguration happens through NetworkManager (a plain "<iface>"
    # connection NM "assumes" from the already-applied state) and lands after
    # this project's boot-time minisoc-route.service below, silently
    # resetting the interface's routes while leaving the primary address
    # alone - caught live (2026-10-22) when the route vanished again *after*
    # minisoc-route.service had already run successfully once at boot. A
    # NetworkManager dispatcher script reacts to every connection state
    # change on every device, whenever it happens and whoever causes it, so
    # it catches this (and any future retrigger) instead of only the one
    # moment covered by `After=network-online.target`.
    cat > /etc/NetworkManager/dispatcher.d/90-minisoc-route <<DISP
#!/bin/sh
ip route replace 10.10.0.0/16 via ${LAB_GATEWAY} dev ${iface} 2>/dev/null || true
DISP
    chmod 755 /etc/NetworkManager/dispatcher.d/90-minisoc-route
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
# nor netplan: re-assert the lab route on a recurring timer, not just once at
# boot. A boot-time-only unit (the original 2026-10-21 fix) and a
# NetworkManager dispatcher script reacting to connection-state changes (the
# 2026-10-22 fix) both assume the route is only ever at risk at one knowable
# moment or from one knowable kind of event - caught live (2026-10-23, right
# before a demo) that it isn't: on kali this route can still vanish again
# after both of those already ran successfully, with nothing in the logs
# showing which mechanism wiped it (it doesn't line up with a dispatcher
# action NM ever logs, so something is reconfiguring the interface without
# going through an NM connection-state transition at all - most likely
# Vagrant's own `private_network` plugin touching the interface directly).
# Rather than needing to pin down exactly what does it and when, a timer that
# cheaply re-applies the same idempotent `ip route replace` every 15 seconds
# makes the actual trigger irrelevant - whatever wipes the route, it's back
# within 15 seconds, indefinitely, not just during boot.
cat > /etc/systemd/system/minisoc-route.service <<UNIT
[Unit]
Description=Mini-SOC: route lab networks via the firewall

[Service]
Type=oneshot
ExecStart=/usr/sbin/ip route replace 10.10.0.0/16 via ${LAB_GATEWAY} dev ${iface}
UNIT
cat > /etc/systemd/system/minisoc-route.timer <<TIMER
[Unit]
Description=Mini-SOC: periodically re-assert the lab route

[Timer]
OnBootSec=5s
OnUnitActiveSec=15s
Unit=minisoc-route.service

[Install]
WantedBy=timers.target
TIMER
# Clean up the old boot-only enablement (WantedBy=multi-user.target, no
# longer in this unit's [Install] section) from a previous provisioning run,
# so a re-provisioned VM doesn't keep a stale direct-at-boot symlink
# alongside the new timer-driven one.
rm -f /etc/systemd/system/multi-user.target.wants/minisoc-route.service
systemctl daemon-reload
systemctl enable --now minisoc-route.timer >/dev/null
systemctl start minisoc-route.service >/dev/null

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
