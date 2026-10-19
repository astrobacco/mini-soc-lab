#!/usr/bin/env bash
# target VM: the practice server (the victim) on the SERVERS network.
# Apache + PHP + MariaDB. The site at / is a fake-but-realistic defense
# contractor front ("Northgate Defense Systems") - plain corporate filler,
# no hint of a training app. DVWA (Damn Vulnerable Web Application) is still
# installed underneath and fully functional, just not linked from anywhere:
# it sits at /legacy/, an old internal tool nobody decommissioned,
# the way a real engagement finds this kind of thing - through recon
# (nikto/gobuster), not by being handed the URL. It is deliberately
# insecure - it only ever lives on the isolated lab network. Apache logs
# and /var/www/html are watched by the Wazuh agent (agent group
# "linux-servers").
#
# Also installs vsftpd for the "01-ftp-webshell" blue-team exercise
# (see exercises/01-ftp-webshell/). It ships locked down (no anonymous
# access) - the exercise's own enable-vulnerability.sh turns the
# misconfiguration on and fix.sh turns it back off. Its writable
# /uploads folder (once that exercise is enabled) sits at the web root
# the same way /legacy does - a second forgotten problem on the
# same "real" site, which is closer to how an actual messy engagement
# looks than one pristine training app.
set -euo pipefail
source /opt/minisoc/lib.sh

DVWA_DIR=/var/www/html/legacy
DB_PASS="${LAB_PASSWORD}"

log "Installing Apache, PHP, MariaDB and vsftpd"
apt_install apache2 php php-mysqli php-gd libapache2-mod-php mariadb-server git vsftpd

# Older builds of this lab put DVWA at the obvious /dvwa - clean that up so
# it doesn't sit there as a leftover giveaway next to the hidden copy.
[ -d /var/www/html/dvwa ] && [ "/var/www/html/dvwa" != "${DVWA_DIR}" ] && rm -rf /var/www/html/dvwa

if [ ! -d "${DVWA_DIR}/.git" ]; then
    log "Downloading DVWA"
    for i in 1 2 3; do
        git clone -q --depth 1 https://github.com/digininja/DVWA.git "${DVWA_DIR}" && break
        rm -rf "${DVWA_DIR}"; [ "$i" = 3 ] && die "could not download DVWA"; sleep 10
    done
fi

systemctl enable --now mariadb >/dev/null
mysql -e "CREATE DATABASE IF NOT EXISTS dvwa;
          CREATE USER IF NOT EXISTS 'dvwa'@'localhost' IDENTIFIED BY '${DB_PASS}';
          ALTER USER 'dvwa'@'localhost' IDENTIFIED BY '${DB_PASS}';
          GRANT ALL ON dvwa.* TO 'dvwa'@'localhost'; FLUSH PRIVILEGES;"

cp -n "${DVWA_DIR}/config/config.inc.php.dist" "${DVWA_DIR}/config/config.inc.php"
sed -i -e "s|^\(\$_DVWA\[ 'db_user' \] *=\).*|\1 'dvwa';|" \
       -e "s|^\(\$_DVWA\[ 'db_password' \] *=\).*|\1 '${DB_PASS}';|" \
       -e "s|^\(\$_DVWA\[ 'default_security_level' \] *=\).*|\1 'low';|" \
       "${DVWA_DIR}/config/config.inc.php"

# DVWA needs these PHP settings and writable folders
PHPINI=$(ls /etc/php/*/apache2/php.ini | head -1)
sed -i -e 's/^allow_url_include.*/allow_url_include = On/' -e 's/^allow_url_fopen.*/allow_url_fopen = On/' "$PHPINI"
chown -R www-data:www-data "${DVWA_DIR}"
chmod -R u+w "${DVWA_DIR}/hackable/uploads" "${DVWA_DIR}/config"

# ---------------------------------------------------------------- the front: Northgate Defense Systems
# Plain static HTML/CSS, no framework - a normal-looking small defense/
# logistics contractor site. Entirely fictional: no real company, agency,
# flag or insignia. Nothing here links to /legacy or /uploads -
# both only ever get found by actually scanning the site.
log "Writing the Northgate Defense Systems front site"
install -d -m 755 /var/www/html/assets

cat > /var/www/html/assets/site.css <<'CSS'
:root { --navy:#0f2238; --navy2:#17314f; --accent:#9db4c9; --bg:#f4f6f8; --text:#1c2733; }
* { box-sizing: border-box; }
body { margin:0; font-family: Georgia, 'Times New Roman', serif; background:var(--bg); color:var(--text); }
header { background:var(--navy); color:#fff; padding: 18px 40px; display:flex; align-items:center; justify-content:space-between; }
header .brand { font-size: 1.4em; letter-spacing: 0.04em; font-weight:bold; }
header .brand span { color: var(--accent); }
nav a { color:#eee; text-decoration:none; margin-left: 26px; font-family: Arial, sans-serif; font-size: 0.95em; }
nav a:hover { color: var(--accent); }
.hero { background:var(--navy2); color:#fff; padding: 70px 40px; text-align:center; }
.hero h1 { margin:0 0 10px; font-size: 2.1em; }
.hero p { margin:0; font-family: Arial, sans-serif; color: var(--accent); font-size: 1.1em; }
main { max-width: 860px; margin: 0 auto; padding: 50px 30px; }
main h2 { border-bottom: 2px solid var(--navy2); padding-bottom: 8px; }
.cards { display:flex; gap:24px; margin-top:30px; flex-wrap: wrap; }
.card { flex:1; min-width:220px; background:#fff; border:1px solid #d9dfe4; border-radius:6px; padding:20px; }
.card h3 { margin-top:0; color:var(--navy2); font-family: Arial, sans-serif; }
footer { background:var(--navy); color:#9fb0bf; text-align:center; padding:22px; font-family: Arial, sans-serif; font-size:0.85em; margin-top:60px; }
CSS

NAV='<header><div class="brand">NORTHGATE <span>DEFENSE SYSTEMS</span></div><nav>
  <a href="/index.html">Home</a><a href="/about.html">About</a>
  <a href="/services.html">Services</a><a href="/contact.html">Contact</a></nav></header>'
FOOT='<footer>&copy; Northgate Defense Systems. All rights reserved. | Authorized personnel only.</footer>'
HEAD='<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><link rel="stylesheet" href="/assets/site.css">'

cat > /var/www/html/index.html <<HTML
<!doctype html><html><head><title>Northgate Defense Systems</title>${HEAD}</head><body>
${NAV}
<div class="hero"><h1>Northgate Defense Systems</h1>
<p>Integrated Logistics &amp; Systems Support for Defense Operations</p></div>
<main>
<h2>Welcome</h2>
<p>Northgate Defense Systems has supported defense and government clients with reliable
logistics coordination, systems integration, and operational infrastructure for over
two decades. Our teams work across a range of mission-critical programs, delivering
dependable support where it is needed most.</p>
<div class="cards">
<div class="card"><h3>Who we are</h3><p>A trusted logistics and systems integration
partner for defense operations, built on decades of hands-on program experience.</p></div>
<div class="card"><h3>What we do</h3><p>From secure communications infrastructure to
facility support, we keep critical programs running.</p></div>
<div class="card"><h3>Get in touch</h3><p>Reach our team directly for program inquiries
and partnership opportunities.</p></div>
</div>
</main>
${FOOT}
</body></html>
HTML

cat > /var/www/html/about.html <<HTML
<!doctype html><html><head><title>About - Northgate Defense Systems</title>${HEAD}</head><body>
${NAV}
<div class="hero"><h1>About Northgate</h1><p>Two decades of mission support</p></div>
<main>
<h2>Our story</h2>
<p>Founded by a small team of logistics and systems engineers, Northgate Defense Systems
has grown into a dependable partner for defense and government programs. We believe in
quiet, reliable execution: our clients rarely hear from us because things simply work.</p>
<h2>Our mission</h2>
<p>To provide dependable, mission-focused logistics and systems integration support,
wherever our clients need it, for as long as they need it.</p>
</main>
${FOOT}
</body></html>
HTML

cat > /var/www/html/services.html <<HTML
<!doctype html><html><head><title>Services - Northgate Defense Systems</title>${HEAD}</head><body>
${NAV}
<div class="hero"><h1>Services</h1><p>Mission-critical support, start to finish</p></div>
<main>
<h2>What we offer</h2>
<div class="cards">
<div class="card"><h3>Logistics Coordination</h3><p>End-to-end supply chain and
logistics planning for distributed operations.</p></div>
<div class="card"><h3>Systems Integration &amp; Support</h3><p>Design, deployment and
ongoing support for mission-critical systems.</p></div>
<div class="card"><h3>Secure Communications Infrastructure</h3><p>Resilient,
dependable communications infrastructure for sensitive environments.</p></div>
</div>
<div class="cards">
<div class="card"><h3>Facility &amp; Asset Management</h3><p>Lifecycle management for
critical facilities and physical assets.</p></div>
<div class="card"><h3>Technical Training Programs</h3><p>Hands-on technical training
tailored to operational requirements.</p></div>
</div>
</main>
${FOOT}
</body></html>
HTML

cat > /var/www/html/contact.html <<HTML
<!doctype html><html><head><title>Contact - Northgate Defense Systems</title>${HEAD}</head><body>
${NAV}
<div class="hero"><h1>Contact Us</h1><p>We'd like to hear from you</p></div>
<main>
<h2>Get in touch</h2>
<p>Northgate Defense Systems<br>
4200 Industrial Parkway, Suite 100<br>
Phone: +1 (555) 019-2834<br>
Email: info@northgate-defense.example</p>
<p>For program-specific inquiries, please contact your assigned account representative.</p>
</main>
${FOOT}
</body></html>
HTML

chown -R www-data:www-data /var/www/html/index.html /var/www/html/about.html \
    /var/www/html/services.html /var/www/html/contact.html /var/www/html/assets

systemctl enable apache2 >/dev/null
systemctl restart apache2
wait_for "Apache" 60 curl -fsS -o /dev/null http://localhost/legacy/login.php
# create the DVWA tables (idempotent: setup.php re-creates the database)
curl -fsS -o /dev/null -c /tmp/dvwa.cookie http://localhost/legacy/setup.php
TOKEN=$(curl -fsS -b /tmp/dvwa.cookie -c /tmp/dvwa.cookie http://localhost/legacy/setup.php | sed -n "s/.*user_token' value='\([^']*\)'.*/\1/p" | head -1)
curl -fsS -o /dev/null -b /tmp/dvwa.cookie -d "create_db=Create+/+Reset+Database&user_token=${TOKEN}" http://localhost/legacy/setup.php
rm -f /tmp/dvwa.cookie

# ---------------------------------------------------------------- vsftpd (locked down by default)
log "Configuring vsftpd (anonymous access disabled)"
cat > /etc/vsftpd.conf <<'EOF'
# Mini-SOC target: locked-down baseline for vsftpd.
# exercises/01-ftp-webshell/enable-vulnerability.sh flips anonymous_enable/anon_upload_enable
# on for that exercise; fix.sh restores this file.
# local_enable=NO: nothing in this lab needs system-account FTP login, and
# leaving it on would let anyone with a Linux account's password (e.g. the
# "vagrant" account every box has) log in over plaintext FTP - a real
# vulnerability found by Greenbone, unrelated to the intentional one.
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=NO
write_enable=NO
dirmessage_enable=YES
xferlog_enable=YES
xferlog_std_format=NO
vsftpd_log_file=/var/log/vsftpd.log
connect_from_port_20=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
EOF
touch /var/log/vsftpd.log
systemctl enable vsftpd >/dev/null
systemctl restart vsftpd

# ---------------------------------------------------------------- wazuh agent
install_wazuh_agent linux-servers

rm -rf /tmp/minisoc-target
log "Target ready: http://10.10.20.10/ (Northgate Defense Systems front; DVWA hidden at /legacy/, admin / password)"
