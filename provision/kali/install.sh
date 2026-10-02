#!/usr/bin/env bash
# kali VM: the attacker on the RED network. Used for red team exercises
# against the target; nothing here is reachable from outside the lab.
set -euo pipefail
source /opt/minisoc/lib.sh

log "Installing attack tools"
apt_install nmap nikto sqlmap hydra gobuster curl

# Short cheat sheet for the first exercises
cat > /home/vagrant/EXERCISES.txt <<'TXT'
Mini-SOC red team exercises (target: 10.10.20.10, DVWA login admin / password)

1. Port scan:      nmap -sV 10.10.20.10
2. Web scan:       nikto -h http://10.10.20.10/dvwa/
3. SQL injection:  sqlmap -u "http://10.10.20.10/dvwa/vulnerabilities/sqli/?id=1&Submit=Submit" \
                     --cookie="PHPSESSID=<your session>; security=low" --batch
4. File upload:    log in to DVWA, open "File Upload", upload any .php file -
                     the Wazuh agent on target watches /var/www/html in real
                     time (FIM) and alerts the moment the file lands.
Then check what Suricata/Wazuh raised:
  - Wazuh dashboard (https://localhost:8444) -> Security events, filter by
    rule group "minisoc_ids" or "web".
  - DFIR-IRIS (https://localhost:8445): level >= 10 alerts become cases
    automatically, with your IP as an indicator and target as the asset.
See the README's "Red team exercise" section for the full walkthrough.
TXT
chown vagrant:vagrant /home/vagrant/EXERCISES.txt

rm -rf /tmp/minisoc-kali
log "Kali ready (10.10.66.10), exercises in ~/EXERCISES.txt"
