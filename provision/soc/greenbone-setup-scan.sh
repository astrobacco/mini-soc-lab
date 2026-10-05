#!/usr/bin/env bash
# Creates a ready-to-run Greenbone scan of the SERVERS network.
# Runs once at boot (minisoc-greenbone-scan.service) and waits until the
# vulnerability feed has been loaded, which takes 30-60 minutes after install.
set -euo pipefail
cd /opt/greenbone
source /opt/minisoc/lib.sh

FULL_AND_FAST=daba56c8-73ec-11df-a475-002264764cea      # scan config "Full and fast"
ALL_TCP_NMAP_UDP=730ef368-57e2-11e1-a90f-406186ea4fc5   # port list "All TCP and Nmap top 100 UDP"
OPENVAS_SCANNER=08b69003-5fc2-4037-a479-93b440211c73    # "OpenVAS Default" scanner
PASSWORD=$(grep '^LAB_PASSWORD=' /opt/minisoc/greenbone.env | cut -d= -f2-)

gmp() {
    docker compose run --rm -T gvm-tools gvm-cli --gmp-username admin --gmp-password "$PASSWORD" \
        socket --socketpath /run/gvmd/gvmd.sock --xml "$1" 2>/dev/null
}

log "Waiting for the Greenbone feed (scan config 'Full and fast')"
until gmp "<get_configs config_id=\"${FULL_AND_FAST}\"/>" | grep -q 'status="200"'; do sleep 60; done
until gmp "<get_port_lists port_list_id=\"${ALL_TCP_NMAP_UDP}\"/>" | grep -q 'status="200"'; do sleep 30; done

if gmp '<get_tasks filter="name=&quot;Scan SERVERS network&quot;"/>' | grep -q '<task id='; then
    log "Scan task 'Scan SERVERS network' exists already"
else
    target_id=$(gmp '<get_targets filter="name=&quot;Mini-SOC SERVERS&quot;"/>' | grep -o '<target id="[^"]*"' | head -1 | cut -d'"' -f2 || true)
    if [ -z "$target_id" ]; then
        target_id=$(gmp "<create_target><name>Mini-SOC SERVERS</name><hosts>10.10.20.0/24</hosts>
            <exclude_hosts>10.10.20.1</exclude_hosts><alive_tests>Consider Alive</alive_tests>
            <port_list id=\"${ALL_TCP_NMAP_UDP}\"/></create_target>" | grep -o 'id="[^"]*"' | head -1 | cut -d'"' -f2)
    fi
    gmp "<create_task><name>Scan SERVERS network</name>
         <comment>Created by Mini-SOC setup. Start it from Scans &gt; Tasks.</comment>
         <config id=\"${FULL_AND_FAST}\"/><target id=\"${target_id}\"/><scanner id=\"${OPENVAS_SCANNER}\"/></create_task>" >/dev/null
    log "Created Greenbone task 'Scan SERVERS network'"
fi

# A single-host task against just "target" - much faster than sweeping the whole
# /24 (seconds vs. a /24 scan that times out probing 253 addresses nobody's
# using), and more realistic for an active incident where you already have a
# suspect host. Used by exercises/01-ftp-webshell/.
if gmp '<get_tasks filter="name=&quot;Scan target (incident response)&quot;"/>' | grep -q '<task id='; then
    log "Scan task 'Scan target (incident response)' exists already"
else
    host_target_id=$(gmp '<get_targets filter="name=&quot;Mini-SOC target (single host)&quot;"/>' | grep -o '<target id="[^"]*"' | head -1 | cut -d'"' -f2 || true)
    if [ -z "$host_target_id" ]; then
        host_target_id=$(gmp "<create_target><name>Mini-SOC target (single host)</name><hosts>10.10.20.10</hosts>
            <alive_tests>Consider Alive</alive_tests><port_list id=\"${ALL_TCP_NMAP_UDP}\"/></create_target>" \
            | grep -o 'id="[^"]*"' | head -1 | cut -d'"' -f2)
    fi
    gmp "<create_task><name>Scan target (incident response)</name>
         <comment>Created by Mini-SOC setup. Faster than 'Scan SERVERS network' - one host only.</comment>
         <config id=\"${FULL_AND_FAST}\"/><target id=\"${host_target_id}\"/><scanner id=\"${OPENVAS_SCANNER}\"/></create_task>" >/dev/null
    log "Created Greenbone task 'Scan target (incident response)'"
fi
