#!/usr/bin/env bash
# target VM: the practice server (the victim) on the SERVERS network.
# Apache + PHP + MariaDB running DVWA (Damn Vulnerable Web Application), a
# well-known training app. It is deliberately insecure - it only ever lives on
# the isolated lab network. Apache logs and /var/www/html are watched by the
# Wazuh agent (agent group "linux-servers").
#
# Also installs vsftpd for the "01-ftp-webshell" blue-team exercise
# (see exercises/01-ftp-webshell/). It ships locked down (no anonymous
# access) - the exercise's own enable-vulnerability.sh turns the
# misconfiguration on and fix.sh turns it back off.
set -euo pipefail
source /opt/minisoc/lib.sh

DVWA_DIR=/var/www/html/dvwa
DB_PASS="${LAB_PASSWORD}"

log "Installing Apache, PHP, MariaDB and vsftpd"
apt_install apache2 php php-mysqli php-gd libapache2-mod-php mariadb-server git vsftpd

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

# landing page points to the app
cat > /var/www/html/index.html <<'HTML'
<!doctype html><title>Mini-SOC target</title>
<h1>Mini-SOC practice server</h1>
<p>Deliberately vulnerable. <a href="/dvwa/">DVWA</a> (login admin / password)</p>
HTML

systemctl enable apache2 >/dev/null
systemctl restart apache2
wait_for "Apache" 60 curl -fsS -o /dev/null http://localhost/dvwa/login.php
# create the DVWA tables (idempotent: setup.php re-creates the database)
curl -fsS -o /dev/null -c /tmp/dvwa.cookie http://localhost/dvwa/setup.php
TOKEN=$(curl -fsS -b /tmp/dvwa.cookie -c /tmp/dvwa.cookie http://localhost/dvwa/setup.php | sed -n "s/.*user_token' value='\([^']*\)'.*/\1/p" | head -1)
curl -fsS -o /dev/null -b /tmp/dvwa.cookie -d "create_db=Create+/+Reset+Database&user_token=${TOKEN}" http://localhost/dvwa/setup.php
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
log "Target ready: http://10.10.20.10/dvwa/ (admin / password)"
