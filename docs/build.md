# Construction et publication

Ce document s'adresse aux responsables du cours.

## Principes

- Une appliance est construite sur un hôte de la même architecture.
- La cible AMD64 est la première cible à stabiliser.
- La cible ARM64 est construite uniquement sur macOS Apple Silicon pendant la phase de validation.
- Linux sur ARM n'est pas une plateforme de construction supportée.
- Les images OVA ne sont jamais commitées dans Git.
- Les appliances sont compressées avant leur téléversement dans une GitHub Release.
- Une release qui annonce ARM64 comme utilisable exige des images OCI LOG100 multi-architectures et une validation des six laboratoires sur ARM64.

## Outils de construction

- VirtualBox 7.2 ou plus récent;
- Packer 1.14 ou plus récent;
- plugin Packer VirtualBox 1.1.5;
- Bash;
- gzip;
- GitHub CLI `gh` uniquement pour la publication.

Le plugin VirtualBox 1.1.5 est épinglé dans la configuration Packer. Le support ARMv8 du plugin est récent et doit être considéré comme une cible à valider, pas comme une preuve de compatibilité fonctionnelle des laboratoires.

## Initialiser Packer

```bash
packer init packer
```

Le script `scripts/build.sh` effectue cette initialisation automatiquement avant la validation et la construction.

## Démarrage de l'installateur Ubuntu

La configuration Packer applique explicitement les paramètres suivants afin d'éviter le démarrage sur un disque vide :

- le lecteur DVD est le premier périphérique de démarrage;
- le disque virtuel est le second;
- l'ISO et le disque utilisent SATA;
- le contrôleur SATA expose deux ports afin d'accueillir le disque et l'ISO;
- EFI est activé par `VBoxManage`;
- Packer attend 20 secondes avant d'envoyer les commandes de démarrage;
- les groupes de touches sont espacés de 200 ms;
- la console VirtualBox reste visible avec `headless = false`;
- le serveur HTTP Packer écoute explicitement en IPv4;
- la commande de démarrage entre directement dans la console GRUB avec `c`, puis charge `/casper/vmlinuz` et `/casper/initrd`;
- le noyau reçoit `autoinstall` et la source NoCloud servie par Packer.

La ligne essentielle est :

```text
autoinstall ds="nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/"
```

Le serveur HTTP Packer est joint depuis le NAT VirtualBox par l'adresse fournie dans `{{ .HTTPIP }}`. Pour le builder VirtualBox, Packer utilise normalement la passerelle hôte `10.0.2.2`.

La console visible est intentionnelle pendant la stabilisation. Une fois les builds régulièrement validés sur les hôtes de référence, `headless` pourra être remis à `true`.

## Autoinstallation

Le fichier `packer/http/user-data` :

- sélectionne explicitement la source `ubuntu-server-minimal`;
- désactive la recherche de pilotes tiers pendant l'installation;
- crée l'utilisateur temporaire `packer`;
- installe OpenSSH;
- désactive explicitement la mise à jour automatique de l'installateur Subiquity pour réduire la variabilité du build;
- utilise le stockage direct sur le disque virtuel;
- active SSH pour permettre à Packer de provisionner la VM.

Le compte `packer` est verrouillé à la fin du build. Le compte étudiant final est `log100`.

## Construire AMD64

Sur un hôte x86_64 :

```bash
./scripts/build.sh amd64
```

Le résultat attendu est :

```text
output-amd64/log100-network-lab-vm-amd64.ova
```

## Construire ARM64

Uniquement sur macOS Apple Silicon, pour validation technique :

```bash
./scripts/build.sh arm64
```

Le résultat attendu est :

```text
output-arm64/log100-network-lab-vm-arm64.ova
```

Cette cible ne doit pas être annoncée aux étudiants avant la validation des images OCI multi-architectures et des six laboratoires.

## Diagnostic d'un build bloqué

Si Packer reste sur `Waiting for SSH to become available...`, observer d'abord la console VirtualBox.

- Si l'installateur Ubuntu ne démarre pas, vérifier que l'ISO est montée, que le lecteur DVD existe et qu'il est le premier périphérique de démarrage.
- Si le menu GRUB reste affiché, vérifier que la commande `c` ouvre bien la console GRUB et que les commandes `linux`, `initrd` et `boot` sont reçues sans caractères manquants.
- Si l'installateur interactif apparaît, vérifier la ligne `autoinstall` et l'accès à la source NoCloud.
- Si l'installateur ne peut pas joindre NoCloud, vérifier l'accès à `10.0.2.2` depuis le NAT VirtualBox et le pare-feu du système hôte.
- Si l'écran de connexion Ubuntu apparaît, l'installation est terminée et le diagnostic doit se concentrer sur SSH et la redirection NAT temporaire créée par Packer.

Le délai `ssh_timeout` reste fixé à 45 minutes afin de ne pas interrompre une installation légitimement lente.

## Provisionnement

Le provisionnement installe les paquets additionnels avec `--no-install-recommends` afin de limiter les dépendances facultatives. Il installe explicitement :

- Podman, `netavark`, `aardvark-dns`, `passt`, `slirp4netns`, `fuse-overlayfs`, `uidmap`, `iptables`, `nftables`, `dbus-user-session` et `catatonit`;
- Git et OpenSSH;
- Python 3, `pip`, `venv`, `requests` et PyYAML;
- `iproute2`, `iputils-ping`, `procps`, `psmisc`, `lsof`, `socat`, `dnsutils`, `traceroute`, `tcpdump`, `tshark` et `netcat-openbsd`;
- `ca-certificates`, `curl`, `jq`, `zip`, `unzip`, `tar`, `gzip`, `xz-utils` et `zstd`;
- Nano, `vim-tiny` et `less`.

`tshark` est installé sans autoriser la capture non privilégiée via `dumpcap`. Les étudiants peuvent l'utiliser pour analyser des captures en ligne de commande; les captures nécessitant des privilèges peuvent continuer à être réalisées avec les mécanismes prévus par les laboratoires. L'interface graphique Wireshark n'est pas installée.

Ubuntu 26.04 utilise l'activation d'OpenSSH par socket par défaut. L'appliance désactive explicitement `ssh.socket` et le générateur `sshd-socket-generator`, puis active `ssh.service` en mode classique. Ce choix rend le service SSH disponible de façon prévisible dès le démarrage. Le service de premier démarrage est ordonné avant `ssh.service` afin de régénérer les clés hôte avant la première connexion étudiante.

Aucune image de laboratoire n'est préchargée.

## Nettoyage et compactage avant export

Le disque virtuel reste configuré à 24 Go dynamiques. Sa capacité maximale n'est donc pas la taille attendue de l'asset. Ce qui compte est le nombre de blocs réellement alloués et leur contenu au moment de l'export.

Le builder Packer active `hard_drive_discard = true` et `hard_drive_nonrotational = true`. Le script `packer/scripts/cleanup.sh` est exécuté après le provisionnement et effectue notamment :

- `apt-get autoremove --purge`;
- `apt-get clean` et la suppression des listes APT;
- le nettoyage du cache de snapd, des journaux d'installation, des crash dumps, de `/tmp`, de `/var/tmp`, des historiques et des caches utilisateur;
- `cloud-init clean` puis la désactivation de cloud-init pour l'appliance finale;
- la rotation et la réduction du journal systemd;
- la remise à zéro des journaux texte;
- `fstrim -av` pour libérer les blocs inutilisés du VDI dynamique.

Le script est installé comme `/usr/local/sbin/log100-cleanup-build`. La commande d'arrêt supprime ensuite les clés SSH temporaires, remet à zéro l'identité machine et exécute une seconde passe TRIM juste avant l'extinction.

Si TRIM n'est pas disponible, le script utilise un remplissage de secours avec des zéros sur l'espace libre de la partition racine, en conservant une marge de 512 Mio. Ce chemin de secours est plus lent et ne devrait normalement pas être utilisé avec la configuration VirtualBox courante.

Il ne faut pas ajouter un remplissage systématique de tout le disque avec `dd` lorsque TRIM fonctionne : cela écrirait inutilement plusieurs gigaoctets dans le disque dynamique avant de les libérer.

## Paqueter

Pour chaque architecture :

```bash
./scripts/package.sh amd64
./scripts/package.sh arm64
```

Les fichiers `.ova.gz` et `.sha256` sont placés dans `release/`. Le script affiche la taille de l'OVA source et celle de l'asset compressé.

Si l'asset compressé atteint 2 Gio ou plus, `package.sh` échoue volontairement. Il ne peut pas compacter rétroactivement un disque déjà exporté dans une OVA : il faut reconstruire l'appliance afin que le nettoyage et TRIM soient exécutés avant l'export.

## Validation fonctionnelle AMD64

Avant toute première release, importer l'appliance AMD64 sur une plateforme représentative et vérifier au minimum :

```bash
ssh -p 2222 log100@localhost
podman info
git --version
```

Vérifier dans `podman info` le fonctionnement rootless et le backend réseau effectivement utilisé.

Puis exécuter les six laboratoires :

```bash
./labctl doctor
./labctl up
./labctl check
./labctl down
```

Le laboratoire 6 doit aussi confirmer le fonctionnement de FRRouting et d'OSPF.

## Validation fonctionnelle ARM64

Avant d'annoncer ARM64 comme utilisable :

1. publier les images OCI LOG100 pour `linux/amd64` et `linux/arm64`;
2. construire l'appliance ARM64 sur macOS Apple Silicon;
3. vérifier SSH et Podman rootless;
4. exécuter les six laboratoires;
5. valider explicitement FRRouting et OSPF dans le laboratoire 6.

## Publication

Les notes de chaque release sont conservées dans `release-notes/`. Le nom par défaut est dérivé de `VERSION` :

```text
release-notes/v<version>.md
```

Par exemple, `VERSION=0.1.1` utilise `release-notes/v0.1.1.md`. Ces fichiers sont versionnés dans Git et constituent l'historique des notes publiées. Il n'est pas nécessaire de maintenir un `CHANGELOG.md`.

1. Mettre `VERSION` à jour.
2. Créer ou réviser `release-notes/v<version>.md`.
3. Valider le dépôt :

```bash
./scripts/validate.sh
```

4. Construire, importer et tester les architectures annoncées.
5. Regrouper les assets requis dans `release/`.
6. Commiter les sources et les notes de release.
7. Créer et pousser un tag annoté :

```bash
git tag -a "v$(cat VERSION)" -m "Version $(cat VERSION)"
git push origin "v$(cat VERSION)"
```

### Préversion AMD64

Tant qu'ARM64 n'est pas validée, une préversion peut être publiée avec uniquement l'appliance AMD64 et son fichier SHA-256 :

```bash
./scripts/release.sh --prerelease
```

Ce mode :

- exige uniquement `log100-network-lab-vm-amd64.ova.gz` et son SHA-256;
- ne demande pas `LOG100_ARM64_VALIDATED=1`;
- crée une GitHub Release marquée comme préversion;
- utilise `--latest=false` afin de ne pas remplacer la dernière release stable;
- utilise automatiquement `release-notes/v$(cat VERSION).md` comme notes de release.

Le chemin des notes peut être remplacé explicitement :

```bash
./scripts/release.sh --prerelease --notes release-notes/v0.1.1.md
```

Un chemin relatif est résolu depuis la racine du dépôt. Un chemin absolu peut également être fourni. Le script refuse la publication si le fichier sélectionné n'existe pas.

Les étudiants ou testeurs qui veulent installer cette préversion doivent sélectionner explicitement son tag :

```bash
./setup-vm.sh --version v0.1.1
```

ou, sous Windows :

```powershell
PowerShell -ExecutionPolicy Bypass -File .\setup-vm.ps1 -Version v0.1.1
```

### Release stable

Après la validation ARM64 complète, une nouvelle version doit être créée avec son propre fichier `release-notes/v<version>.md`. Les notes historiques de `v0.1.1` ne doivent pas être réécrites pour transformer cette préversion AMD64 en release ARM64.

Lorsque les assets AMD64 et ARM64 de la nouvelle version sont présents :

```bash
LOG100_ARM64_VALIDATED=1 ./scripts/release.sh
```

Le mode stable refuse une release incomplète, un asset de 2 Gio ou plus, une publication sans fichier de notes, ou une publication sans l'acquittement explicite de la validation ARM64.

## Politique de versions

Le dépôt suit SemVer.

- PATCH : correction de construction, de documentation ou de compatibilité sans changement important de l'environnement étudiant.
- MINOR : ajout ou modification compatible de l'environnement de la VM.
- MAJOR : changement incompatible du flux d'installation, de l'OS invité ou des exigences principales.

La version des appliances est indépendante de la version des laboratoires et des images de conteneurs.
