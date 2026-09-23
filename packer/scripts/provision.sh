#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get -o DPkg::Lock::Timeout=600 update

for attempt in $(seq 1 60); do
    if printf '%s\n' \
        'wireshark-common wireshark-common/install-setuid boolean false' \
        | debconf-set-selections; then
        break
    fi

    if [ "$attempt" -eq 60 ]; then
        echo "ERREUR : debconf est resté verrouillé trop longtemps." >&2
        exit 1
    fi

    sleep 5
done

apt-get -o DPkg::Lock::Timeout=600 install -y --no-install-recommends \
  aardvark-dns \
  ca-certificates \
  catatonit \
  curl \
  dbus-user-session \
  dnsutils \
  fuse-overlayfs \
  git \
  gzip \
  iproute2 \
  iptables \
  iputils-ping \
  jq \
  less \
  lsof \
  nano \
  netavark \
  netcat-openbsd \
  nftables \
  openssh-server \
  passt \
  podman \
  procps \
  psmisc \
  python3 \
  python3-pip \
  python3-requests \
  python3-venv \
  python3-yaml \
  slirp4netns \
  socat \
  tar \
  tcpdump \
  traceroute \
  tshark \
  uidmap \
  unzip \
  vim-tiny \
  xz-utils \
  zip \
  zstd

# Conserver explicitement la pile réseau Podman pendant le nettoyage final.
apt-mark manual podman netavark aardvark-dns passt slirp4netns fuse-overlayfs uidmap iptables nftables >/dev/null

if ! id log100 >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --groups sudo log100
fi

echo 'log100:log100' | chpasswd

if ! grep -q '^log100:' /etc/subuid; then
  echo 'log100:200000:65536' >> /etc/subuid
fi
if ! grep -q '^log100:' /etc/subgid; then
  echo 'log100:200000:65536' >> /etc/subgid
fi

install -d -m 0755 /etc/ssh/sshd_config.d
rm -f /etc/ssh/sshd_config.d/60-log100.conf
cat > /etc/ssh/sshd_config.d/10-log100.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication no
AllowUsers log100 packer
EOF

# Ubuntu 26.04 active OpenSSH par socket par défaut. Pour cette appliance,
# utiliser le service classique afin que SSH soit disponible dès le démarrage.
systemctl disable ssh.socket || true
install -d -m 0755 /etc/systemd/system-generators
ln -sf /dev/null /etc/systemd/system-generators/sshd-socket-generator
systemctl daemon-reload
systemctl unmask ssh.service || true
systemctl enable ssh.service

cat > /etc/sysctl.d/60-log100-rootless.conf <<'EOF'
kernel.apparmor_restrict_unprivileged_userns=0
EOF
sysctl --system >/dev/null

install -d -o log100 -g log100 -m 0755 \
  /home/log100/.config \
  /home/log100/.config/containers

test "$(stat -c '%U:%G' /home/log100/.config)" = "log100:log100"
test "$(stat -c '%U:%G' /home/log100/.config/containers)" = "log100:log100"

cat > /home/log100/README.txt <<'EOF'
LOG100 - Machine virtuelle pour les laboratoires de réseautique

Connexion depuis le système hôte :
  ssh -p 2222 log100@localhost

Mot de passe initial : log100
Il est recommandé de le modifier avec : passwd

Après avoir obtenu l'accès GitHub au laboratoire :
  git clone <adresse-du-depot>
  cd <depot>
  ./labctl doctor
  ./labctl up
EOF
chown log100:log100 /home/log100/README.txt

cat > /etc/motd <<'EOF'
LOG100 - Environnement des laboratoires de réseautique
Consultez ~/README.txt pour les commandes de départ.
EOF

install -d -m 0755 /var/lib/log100
: > /var/lib/log100/first-boot.pending

cat > /usr/local/sbin/log100-first-boot <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
marker=/var/lib/log100/first-boot.pending
if [[ ! -f "$marker" ]]; then
  exit 0
fi
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A
rm -f "$marker"
EOF
chmod 0755 /usr/local/sbin/log100-first-boot

cat > /etc/systemd/system/log100-first-boot.service <<'EOF'
[Unit]
Description=Initialiser la VM LOG100 après importation
After=local-fs.target
Before=ssh.service
ConditionPathExists=/var/lib/log100/first-boot.pending

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/log100-first-boot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable log100-first-boot.service

cat > /usr/local/sbin/log100-finalize-build <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

passwd -l packer || true
usermod --shell /usr/sbin/nologin packer || true
rm -rf /home/packer/.ssh /home/packer/.cache
rm -f /etc/ssh/ssh_host_*
rm -f /var/lib/systemd/random-seed
truncate -s 0 /etc/machine-id
if [[ -e /var/lib/dbus/machine-id || -L /var/lib/dbus/machine-id ]]; then
  rm -f /var/lib/dbus/machine-id
  ln -s /etc/machine-id /var/lib/dbus/machine-id
fi

if [[ -x /usr/local/sbin/log100-cleanup-build ]]; then
  /usr/local/sbin/log100-cleanup-build --final
fi

sync
shutdown -P now
EOF
chmod 0755 /usr/local/sbin/log100-finalize-build

test -x /usr/lib/podman/netavark
test -x /usr/lib/podman/aardvark-dns
command -v iptables >/dev/null
command -v nft >/dev/null
command -v pasta >/dev/null
command -v slirp4netns >/dev/null
command -v fuse-overlayfs >/dev/null
command -v tshark >/dev/null
/usr/lib/podman/netavark --version
iptables --version
nft --version
podman --version
git --version
python3 --version
tshark --version >/dev/null
vi --version >/dev/null
sshd -t
systemctl is-enabled --quiet ssh.service
if systemctl is-enabled --quiet ssh.socket; then
  echo "ERREUR : ssh.socket ne doit pas être activé dans l'appliance finale." >&2
  exit 1
fi
