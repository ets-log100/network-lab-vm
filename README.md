# network-lab-vm

Ce dépôt contient les fichiers reproductibles nécessaires pour construire et publier une machine virtuelle VirtualBox destinée aux laboratoires de réseautique de LOG100.

La machine virtuelle est une solution de repli pour les étudiants qui veulent exécuter les laboratoires sur leur ordinateur personnel lorsque l'installation locale de Podman est difficile. Les postes de laboratoire de l'ÉTS demeurent l'environnement de référence.

Les appliances OVA ne sont pas stockées dans Git. Elles sont publiées comme assets d'une GitHub Release.

## État de validation

La version de développement courante est `0.1.1`.

La cible AMD64 est la première cible à stabiliser. La cible de construction ARM64 est présente dans le dépôt, mais elle ne doit pas encore être annoncée comme disponible aux étudiants.

Avant d'annoncer ARM64 comme supportée, les conditions suivantes doivent être remplies :

- `network-lab-image` doit publier des images OCI multi-architectures pour `linux/amd64` et `linux/arm64`;
- les six laboratoires doivent être validés sur ARM64;
- le laboratoire 6 doit notamment être validé avec FRRouting et OSPF;
- l'appliance ARM64 doit être construite et testée sur macOS Apple Silicon.

## Environnement fourni

L'appliance contient notamment :

- Ubuntu Server 26.04 LTS;
- Podman en mode rootless;
- `netavark`, `aardvark-dns`, `passt`, `slirp4netns`, `fuse-overlayfs`, `uidmap`, `iptables` et `nftables` pour la pile réseau Podman/rootless;
- Git et OpenSSH;
- Python 3 avec `pip`, `venv`, `requests` et PyYAML;
- `iproute2`, `iputils-ping`, `dnsutils`, `traceroute`, `tcpdump`, `tshark`, `netcat-openbsd`, `socat`, `lsof`, `procps` et `psmisc` pour le diagnostic réseau et système;
- `curl`, `jq`, `zip`, `unzip`, `tar`, `gzip`, `xz-utils` et `zstd`;
- Nano, `vim-tiny` et `less`;
- un compte utilisateur `log100`.

Les images de conteneurs des laboratoires ne sont pas préinstallées. `./labctl up` doit récupérer les mêmes références immuables publiées sur GHCR que sur les machines de l'ÉTS.

Wireshark avec interface graphique n'est pas installé dans la VM. `tshark` est disponible en ligne de commande. Les fichiers `.pcap` et `.pcapng` peuvent aussi être ouverts avec Wireshark sur le système hôte.

## Ressources de la VM

- 2 vCPU;
- 4 Go de mémoire;
- disque dynamique de 24 Go;
- adaptateur réseau VirtualBox en mode NAT.

Le port SSH de l'invité est exposé uniquement sur la boucle locale du système hôte :

```text
127.0.0.1:2222 -> VM:22
```

Connexion :

```bash
ssh -p 2222 log100@localhost
```

Le mot de passe initial est `log100`. Il est recommandé de le modifier avec `passwd` après la première connexion. L'authentification par mot de passe et par clé publique est permise. Le service OpenSSH est activé au démarrage de la VM.

## Politique de support visée

Une fois la validation ARM64 terminée, la politique visée est la suivante.

### Supportées

- Windows 10/11 sur Intel ou AMD;
- Ubuntu x86_64 récent;
- macOS sur Intel;
- macOS sur Apple Silicon.

### Meilleur effort

- Windows 11 sur ARM.

### Non supportées

- Linux sur ARM;
- les hyperviseurs autres que VirtualBox;
- les architectures inhabituelles;
- l'émulation d'une architecture différente de celle du système hôte.

Tant que la validation ARM64 décrite plus haut n'est pas terminée, seule la cible AMD64 doit être considérée pour une diffusion étudiante.

## Utilisation par un étudiant

### Linux x86_64 ou macOS Intel

Télécharger `scripts/setup-vm.sh`, puis utiliser la dernière release stable :

```bash
chmod +x setup-vm.sh
./setup-vm.sh
```

Pour installer une release précise, y compris une préversion :

```bash
./setup-vm.sh --version v0.1.1
```

### Windows Intel ou AMD

Télécharger `scripts/setup-vm.ps1`, puis utiliser la dernière release stable :

```powershell
PowerShell -ExecutionPolicy Bypass -File .\setup-vm.ps1
```

Pour installer une release précise, y compris une préversion :

```powershell
PowerShell -ExecutionPolicy Bypass -File .\setup-vm.ps1 -Version v0.1.1
```

Sans version explicite, les scripts téléchargent l'asset correspondant depuis la dernière release stable. Avec une version explicite, ils téléchargent directement les assets du tag demandé. Dans les deux cas, ils détectent l'architecture du système hôte, vérifient le SHA-256, importent la VM, configurent la redirection SSH et démarrent la VM.

Sur un système ARM64, ne pas utiliser une appliance ARM64 avant qu'une release indique explicitement que la validation ARM64 des laboratoires est terminée.

Voir [docs/student-setup.md](docs/student-setup.md) pour les détails.

## Construction

La construction se fait avec Packer et VirtualBox sur un hôte de la même architecture que l'appliance produite. Pendant la stabilisation, la console VirtualBox reste visible afin de diagnostiquer le démarrage de l'installateur et l'autoinstallation.

L'installation utilise la source Ubuntu Server minimale. Avant l'export OVA, le build supprime les caches, journaux et données temporaires, puis exécute TRIM sur le disque virtuel dynamique. Cette étape est importante pour maintenir l'asset de release sous la limite de taille.

AMD64 :

```bash
./scripts/build.sh amd64
./scripts/package.sh amd64
```

ARM64, uniquement pour validation technique sur macOS Apple Silicon :

```bash
./scripts/build.sh arm64
./scripts/package.sh arm64
```

Voir [docs/build.md](docs/build.md).

## Publication d'une release

Les notes de release sont conservées dans `release-notes/` et versionnées avec le dépôt. Pour la version courante, le fichier par défaut est `release-notes/v0.1.1.md`.

Une préversion AMD64 peut être publiée avant que l'appliance ARM64 soit prête. Après avoir construit et testé AMD64, placé l'appliance compressée et son SHA-256 dans `release/`, puis créé et poussé le tag correspondant à `VERSION` :

```bash
./scripts/release.sh --prerelease
```

Ce mode publie uniquement les assets AMD64, marque la GitHub Release comme préversion, ne la marque pas comme dernière release stable et utilise automatiquement `release-notes/v$(cat VERSION).md`.

Un autre fichier de notes peut être sélectionné explicitement :

```bash
./scripts/release.sh --prerelease --notes release-notes/v0.1.1.md
```

La publication stable exige les assets AMD64 et ARM64 ainsi qu'une validation explicite d'ARM64 :

```bash
LOG100_ARM64_VALIDATED=1 ./scripts/release.sh
```

Ne définir `LOG100_ARM64_VALIDATED=1` qu'après la validation des images OCI multi-architectures et des six laboratoires sur ARM64. Une future version incluant ARM64 doit utiliser une nouvelle version et un nouveau fichier dans `release-notes/`, plutôt que de réécrire les notes historiques de `v0.1.1`.

## Validation locale du dépôt

```bash
./scripts/validate.sh
```

Les fichiers Markdown sont en français. Les noms de dépôts, répertoires, scripts, variables et identifiants techniques utilisent l'anglais lorsque cela est pratique.
