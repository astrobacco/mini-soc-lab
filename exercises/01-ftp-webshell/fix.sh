#!/usr/bin/env bash
# Run this ON target (vagrant ssh target) to remediate exercise 01: disables
# anonymous FTP again, restores the web root permissions, and removes any
# web shell(s) the attack dropped. This is the "quick update" that closes
# the incident - re-run exercises/01-ftp-webshell/ 's Greenbone scan
# afterwards to confirm the finding is gone.
set -euo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"

echo "Removing any planted web shells and the vulnerable uploads folder..."
find /var/www/html -maxdepth 2 -iname 'minisoc_shell_*.php' -print -delete
rm -rf /var/www/html/uploads

echo "Restoring the locked-down vsftpd configuration..."
cat > /etc/vsftpd.conf <<'EOF'
# Mini-SOC target: locked-down baseline for vsftpd (exercise 01 fixed).
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
systemctl restart vsftpd

echo "Restoring web root permissions..."
chown -R www-data:www-data /var/www/html
chmod 755 /var/www/html

echo "Fixed: anonymous FTP is disabled again and the web shell is gone."
