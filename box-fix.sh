#!/bin/sh
# One-shot fix so the Enclave dev box accepts the alexis@omp key.
# Rewrites root's authorized_keys cleanly, fixes permissions, ensures sshd
# allows key login, and reloads sshd. Safe to run repeatedly. Touches nothing
# but /root/.ssh and one sshd drop-in — your services and data are untouched.

KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBuxm141aMa5hQNwGI8Jr5PUhj3D8zLITSRRqrRHHa+6 alexis@omp'

mkdir -p /root/.ssh
# clean write: strips any stray carriage returns / duplicate mangled keys
printf '%s\n' "$KEY" > /root/.ssh/authorized_keys
chown -R root:root /root/.ssh 2>/dev/null

chmod 700 /root
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

mkdir -p /etc/ssh/sshd_config.d
printf '%s\n' 'PubkeyAuthentication yes' 'PermitRootLogin prohibit-password' \
  > /etc/ssh/sshd_config.d/00-enclave.conf

# reload sshd under whatever name/init it uses (reload = existing sessions kept)
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || \
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || \
service ssh reload 2>/dev/null || service sshd reload 2>/dev/null || true

echo
echo "==== ENCLAVE-FIX DONE ===="
echo "authorized_keys:"; cat /root/.ssh/authorized_keys
echo "perms:"; ls -ld /root /root/.ssh /root/.ssh/authorized_keys
