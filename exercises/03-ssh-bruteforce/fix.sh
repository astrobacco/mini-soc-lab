#!/usr/bin/env bash
# Run this ON target (vagrant ssh target) to remediate exercise 03:
# removes the per-account SSH password-auth override and locks the
# "service" account's password, the same "disable, don't just patch
# around it" pattern used for the lab-wide vagrant:vagrant fix in
# base.sh. Re-run exercises/03-ssh-bruteforce/README.md's Step 2 hydra
# command afterwards to confirm it can no longer log in.
set -euo pipefail
[ "$(id -u)" = 0 ] || exec sudo "$0" "$@"

rm -f /etc/ssh/sshd_config.d/60-minisoc-weak-ssh-account.conf
systemctl restart ssh

passwd -l service >/dev/null 2>&1 || true

echo "Fixed: the 'service' account is locked and SSH password auth for it is gone on $(hostname)."
echo "The lab-wide key-only default (provision/common/base.sh) applies to it like everyone else now."
