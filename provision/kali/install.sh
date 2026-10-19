#!/usr/bin/env bash
# kali VM: the attacker on the RED network. Used for red team exercises
# against the target; nothing here is reachable from outside the lab.
set -euo pipefail
source /opt/minisoc/lib.sh

log "Installing attack tools"
apt_install nmap nikto sqlmap hydra gobuster curl

# Short cheat sheet for the first exercises
cat > /home/vagrant/EXERCISES.txt <<'TXT'
Mini-SOC red team exercises (target: 10.10.20.10)

target's front page (http://10.10.20.10/) is a normal-looking "Northgate
Defense Systems" site - no hint of a training app. The actual vulnerable
app (DVWA, login admin / password) is still there, just not linked from
anywhere: it's found the way it'd really happen, through recon.

1. Port scan:      nmap -sV 10.10.20.10
2. Web scan:       nikto -h http://10.10.20.10/
3. Find the hidden app: gobuster dir -u http://10.10.20.10/ \
                     -w /usr/share/wordlists/dirb/common.txt
                     (turns up /legacy/ - an old internal tool
                     nobody decommissioned)
4. SQL injection:  sqlmap -u "http://10.10.20.10/legacy/vulnerabilities/sqli/?id=1&Submit=Submit" \
                     --cookie="PHPSESSID=<your session>; security=low" --batch
5. File upload:    log in to /legacy/, open "File Upload", upload any
                     .php file - the Wazuh agent on target watches
                     /var/www/html in real time (FIM) and alerts the moment
                     the file lands.
Then check what Suricata/Wazuh raised:
  - Wazuh dashboard (https://localhost:8444) -> Discover, index pattern
    "wazuh-alerts-*", filter by rule group "minisoc_ids" or "web".
  - DFIR-IRIS (https://localhost:8445): level >= 10 alerts become cases
    automatically, with your IP as an indicator and target as the asset.
See the README's "Red team exercise" section for the full walkthrough.
TXT
chown vagrant:vagrant /home/vagrant/EXERCISES.txt

rm -rf /tmp/minisoc-kali
log "Kali ready (10.10.66.10), exercises in ~/EXERCISES.txt"
