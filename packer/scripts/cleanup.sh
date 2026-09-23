#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
mode=${1:-normal}

log() {
  printf 'INFO : %s\n' "$*"
}

zero_fill_root_free_space() {
  local available_kib reserve_kib count_mib zero_file
  reserve_kib=524288
  zero_file=/var/tmp/log100-zero-fill
  available_kib=$(df -Pk / | awk 'NR == 2 {print $4}')

  if [[ ! "$available_kib" =~ ^[0-9]+$ ]] || (( available_kib <= reserve_kib )); then
    log "espace libre insuffisant pour le remplissage de secours avec des zéros"
    return 0
  fi

  count_mib=$(( (available_kib - reserve_kib) / 1024 ))
  if (( count_mib <= 0 )); then
    return 0
  fi

  log "TRIM indisponible; remplissage de secours de ${count_mib} Mio avec des zéros"
  rm -f "$zero_file"
  dd if=/dev/zero of="$zero_file" bs=1M count="$count_mib" status=none || true
  sync
  rm -f "$zero_file"
  sync
}

if [[ "$mode" != "--final" ]]; then
  install -m 0755 "$0" /usr/local/sbin/log100-cleanup-build

  log "suppression des paquets devenus inutiles"
  apt-get autoremove --purge -y

  log "nettoyage des caches de paquets"
  apt-get clean
  rm -rf /var/lib/apt/lists/*
  rm -rf /var/cache/apt/archives/*
  rm -rf /var/lib/snapd/cache/*

  log "nettoyage des données temporaires du build"
  rm -rf /var/log/installer/*
  rm -rf /var/crash/*
  rm -rf /var/cache/man/*
  rm -rf /root/.cache /home/log100/.cache /home/packer/.cache
  rm -f /root/.bash_history /home/log100/.bash_history /home/packer/.bash_history

  if command -v cloud-init >/dev/null 2>&1; then
    cloud-init clean --logs --seed || true
    touch /etc/cloud/cloud-init.disabled
  fi

log "configuration du réseau de l'appliance"
install -d -m 0755 /etc/netplan

cat > /etc/netplan/01-log100.yaml <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    primary:
      match:
        name: "en*"
      dhcp4: true
      dhcp6: false
      optional: true
EOF

chmod 0600 /etc/netplan/01-log100.yaml
netplan generate

  if command -v journalctl >/dev/null 2>&1; then
    journalctl --rotate || true
    journalctl --vacuum-time=1s || true
  fi

  find /var/log -type f ! -path '/var/log/journal/*' -exec truncate -s 0 {} +
else
  find /tmp /var/tmp -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
fi

sync

log "libération des blocs inutilisés du disque virtuel"
if command -v fstrim >/dev/null 2>&1 && fstrim -av; then
  log "TRIM terminé"
else
  zero_fill_root_free_space
fi

sync
df -h /
