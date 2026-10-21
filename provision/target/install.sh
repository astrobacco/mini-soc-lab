#!/usr/bin/env bash
# target VM: the practice server (the victim) on the SERVERS network.
# Apache + PHP + MariaDB. The site at / is a fake-but-realistic defense
# contractor front ("Northgate Defense Systems") - plain corporate filler,
# no hint of a training app. A small, hand-written PHP "Employee Portal" is
# installed underneath and fully functional, just not linked from anywhere:
# it sits at /legacy/, an old internal tool nobody decommissioned, the way
# a real engagement finds this kind of thing - through recon (nikto/
# gobuster), not by being handed the URL. Hand-written rather than a known
# training app (DVWA, used until 2026-10-21) on purpose: a single realistic
# login form that's vulnerable to both a classic SQL-injection auth bypass
# and weak-credential brute force, with no CSRF token to fight (DVWA's
# single-use token made every brute-force/sqlmap tool need a workaround -
# this one needs none, the way an actually-forgotten legacy tool wouldn't
# have modern CSRF protection either), plus a file upload once logged in
# for the webshell angle. It is deliberately insecure - it only ever lives
# on the isolated lab network. Apache logs and /var/www/html are watched by
# the Wazuh agent (agent group "linux-servers").
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

PORTAL_DIR=/var/www/html/legacy
DB_PASS="${LAB_PASSWORD}"

log "Installing Apache, PHP, MariaDB and vsftpd"
apt_install apache2 php php-mysqli php-gd libapache2-mod-php mariadb-server vsftpd

# Older builds of this lab put DVWA at /dvwa or ran it from /legacy - clean
# both up so nothing sits there as a leftover giveaway (or a stale git
# checkout) next to the hand-written portal that now lives at /legacy.
[ -d /var/www/html/dvwa ] && rm -rf /var/www/html/dvwa
[ -d "${PORTAL_DIR}/.git" ] && rm -rf "${PORTAL_DIR}"

systemctl enable --now mariadb >/dev/null
mysql -e "CREATE DATABASE IF NOT EXISTS portal;
          CREATE USER IF NOT EXISTS 'portal'@'localhost' IDENTIFIED BY '${DB_PASS}';
          ALTER USER 'portal'@'localhost' IDENTIFIED BY '${DB_PASS}';
          GRANT ALL ON portal.* TO 'portal'@'localhost'; FLUSH PRIVILEGES;
          USE portal;
          CREATE TABLE IF NOT EXISTS users (
            id INT AUTO_INCREMENT PRIMARY KEY,
            username VARCHAR(64) NOT NULL,
            password VARCHAR(64) NOT NULL
          );
          DELETE FROM users;
          INSERT INTO users (username, password) VALUES ('admin', 'Welcome1');"

# ---------------------------------------------------------------- the hidden portal: a hand-written legacy app
# Deliberately NOT a known training app: a small, realistic internal
# "Employee Portal" with exactly two bugs a real forgotten legacy tool
# plausibly has - a login query built by string concatenation (classic SQL
# injection auth bypass) and a weak, guessable password on top of it, plus
# an unrestricted file upload once logged in. No CSRF token on the login
# form on purpose - a tool nobody has touched in years wouldn't have one
# either, and it means hydra/curl need no workaround to attack it (unlike
# DVWA's single-use token, which fought every tool thrown at it).
log "Writing the Northgate Employee Portal (the hidden legacy app)"
install -d -m 755 "${PORTAL_DIR}" "${PORTAL_DIR}/uploads"

cat > "${PORTAL_DIR}/db.php" <<PHP
<?php
\$mysqli = new mysqli('localhost', 'portal', '${DB_PASS}', 'portal');
PHP

cat > "${PORTAL_DIR}/style.css" <<'CSS'
body { margin:0; font-family: Arial, Helvetica, sans-serif; background:#d9dce0; color:#222; }
.topbar { background:#1c2733; color:#cfd8e3; padding:10px 20px; font-size:0.9em; border-bottom:3px solid #0f2238; }
.box { max-width:360px; margin:70px auto; background:#fff; border:1px solid #9aa4ad; padding:28px 32px; box-shadow:1px 1px 3px rgba(0,0,0,0.2); }
.box h1 { font-size:1.2em; margin:0 0 4px; color:#1c2733; }
.box p.sub { margin:0 0 20px; color:#666; font-size:0.85em; }
label { display:block; margin-top:12px; font-size:0.85em; color:#444; }
input[type=text], input[type=password], input[type=file] { width:100%; box-sizing:border-box; padding:7px; margin-top:4px; border:1px solid #9aa4ad; }
input[type=submit] { margin-top:18px; padding:8px 18px; background:#1c2733; color:#fff; border:none; cursor:pointer; }
input[type=submit]:hover { background:#0f2238; }
.msg { margin-top:14px; padding:8px; background:#fde2e1; border:1px solid #c0392b; color:#842a24; font-size:0.85em; }
.dash { max-width:560px; margin:50px auto; background:#fff; border:1px solid #9aa4ad; padding:28px 32px; }
CSS

cat > "${PORTAL_DIR}/login.php" <<'PHP'
<?php
session_start();
require __DIR__ . '/db.php';
$error = '';
if (isset($_REQUEST['username'])) {
    // Accepts GET as well as POST - an old enough app that nobody ever
    // tightened this up, and it means a bookmarked "quick login" link
    // with credentials in the URL still works, for better or worse.
    $u = $_REQUEST['username'] ?? '';
    $p = $_REQUEST['password'] ?? '';
    // Legacy query - built by string concatenation, never parameterised.
    $sql = "SELECT * FROM users WHERE username='$u' AND password='$p'";
    $result = $mysqli->query($sql);
    if ($result && $result->num_rows > 0) {
        $row = $result->fetch_assoc();
        $_SESSION['user'] = $row['username'];
        header('Location: dashboard.php');
        exit;
    }
    $error = 'Login failed.';
}
?>
<!doctype html><html><head><title>Northgate Employee Portal</title>
<link rel="stylesheet" href="style.css"></head><body>
<div class="topbar">Northgate Defense Systems &mdash; Employee Portal (legacy)</div>
<div class="box">
<h1>Employee Sign In</h1>
<p class="sub">Internal use only. Contact IT if you've forgotten your login.</p>
<form method="post">
<label>Username</label><input type="text" name="username">
<label>Password</label><input type="password" name="password">
<input type="submit" value="Sign in">
</form>
<?php if ($error): ?><div class="msg"><?= htmlspecialchars($error) ?></div><?php endif; ?>
</div>
</body></html>
PHP

cat > "${PORTAL_DIR}/dashboard.php" <<'PHP'
<?php
session_start();
if (!isset($_SESSION['user'])) { header('Location: login.php'); exit; }
$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['document'])) {
    $name = basename($_FILES['document']['name']);
    $dest = __DIR__ . '/uploads/' . $name;
    // No file type or extension check - whatever gets uploaded lands as-is.
    if (move_uploaded_file($_FILES['document']['tmp_name'], $dest)) {
        $msg = "Uploaded: $name";
    }
}
?>
<!doctype html><html><head><title>Dashboard - Northgate Employee Portal</title>
<link rel="stylesheet" href="style.css"></head><body>
<div class="topbar">Northgate Defense Systems &mdash; Employee Portal (legacy)</div>
<div class="dash">
<h1>Welcome, <?= htmlspecialchars($_SESSION['user']) ?></h1>
<p><a href="logout.php">Log out</a></p>
<h2 style="font-size:1em;">Submit a document</h2>
<form method="post" enctype="multipart/form-data">
<input type="file" name="document">
<input type="submit" value="Upload">
</form>
<?php if ($msg): ?><p><?= htmlspecialchars($msg) ?></p><?php endif; ?>
</div>
</body></html>
PHP

cat > "${PORTAL_DIR}/logout.php" <<'PHP'
<?php
session_start();
session_destroy();
header('Location: login.php');
PHP

chown -R www-data:www-data "${PORTAL_DIR}"
chmod 777 "${PORTAL_DIR}/uploads"

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
log "Target ready: http://10.10.20.10/ (Northgate Defense Systems front; Employee Portal hidden at /legacy/, admin / Welcome1)"
