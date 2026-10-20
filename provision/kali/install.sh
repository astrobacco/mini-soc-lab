#!/usr/bin/env bash
# kali VM: the attacker on the RED network. Used for red team exercises
# against the target; nothing here is reachable from outside the lab.
set -euo pipefail
source /opt/minisoc/lib.sh

log "Installing attack tools"
apt_install nmap nikto sqlmap hydra gobuster curl python3-requests

install -o vagrant -g vagrant -m 755 /tmp/minisoc-kali/dvwa-bruteforce.py /home/vagrant/dvwa-bruteforce.py

# A small curated list, not full rockyou: fast enough for a live demo,
# still includes the real password so the exercise actually succeeds.
cat > /home/vagrant/passwords.txt <<'TXT'
123456
admin
letmein
qwerty
password
changeme
TXT
chown vagrant:vagrant /home/vagrant/passwords.txt

# Short cheat sheet for the first exercises
cat > /home/vagrant/EXERCISES.txt <<'TXT'
Mini-SOC red team exercises (target: 10.10.20.10)

target's front page (http://10.10.20.10/) is a normal-looking "Northgate
Defense Systems" site - no hint of a training app. The actual vulnerable
app (DVWA) is still there, just not linked from anywhere, and its login
credentials are never just handed to you either: both are found the way
they'd really happen, through recon and a brute force.

1. Port scan:      nmap -sV 10.10.20.10
2. Web scan:       nikto -h http://10.10.20.10/
3. Find the hidden app: gobuster dir -u http://10.10.20.10/ \
                     -w /usr/share/wordlists/dirb/common.txt
                     (turns up /legacy/ - an old internal tool
                     nobody decommissioned)
4. Brute-force the login: python3 ~/dvwa-bruteforce.py ~/passwords.txt
                     Hydra's http-post-form module can't be used as-is
                     here - DVWA's CSRF token is single-use, so a fixed
                     token reused across attempts always looks "wrong"
                     to Hydra, false-positiving every password. This
                     script does a fresh GET+token+POST per attempt,
                     the way a real attacker's own script would.
5. SQL injection:  sqlmap -u "http://10.10.20.10/legacy/vulnerabilities/sqli/?id=1&Submit=Submit" \
                     --cookie="PHPSESSID=<your session>; security=low" --batch
6. File upload:    log in to /legacy/, open "File Upload", upload any
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
