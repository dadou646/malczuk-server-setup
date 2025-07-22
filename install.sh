#!/bin/bash

set -e

# =============================
# Malczuk Server - install.sh
# =============================
# Serveur personnel domotique sécurisé et automatisé
# Auteur : David Malczuk
# ================================================

# Vérification root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en tant que root (sudo)."
  exit 1
fi

# 1. Mises à jour de base
apt update && apt upgrade -y
apt install -y curl git sudo gnupg lsb-release ca-certificates software-properties-common

# 2. Installation de Docker + Docker Compose
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | bash
  usermod -aG docker $SUDO_USER
else
  echo "✅ Docker déjà installé"
fi

if ! command -v docker-compose &> /dev/null; then
  curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
else
  echo "✅ Docker Compose déjà installé"
fi

# 3. Yacht (interface Docker)
if [ ! $(docker ps -a --format '{{.Names}}' | grep -w yacht) ]; then
  docker volume create yacht
  curl -s https://get.yacht.sh | bash
else
  echo "✅ Yacht déjà installé"
fi

# 4. Avahi (résolution mDNS .local)
if ! systemctl is-active --quiet avahi-daemon; then
  curl -s https://raw.githubusercontent.com/dadou646/malczuk-server-setup/main/install-avahi.sh | bash
else
  echo "✅ Avahi déjà actif"
fi

# 5. WireGuard VPN (accès distant sécurisé)
if ! dpkg -l | grep -q wireguard; then
  apt install -y wireguard wireguard-tools
else
  echo "✅ WireGuard déjà installé"
fi
# Configuration manuelle recommandée après installation

# 6. Création des dossiers de données
mkdir -p /mnt/HDD /mnt/Malczuk_Backup /srv/photos /srv/medias /srv/jarvis
chown -R $SUDO_USER:$SUDO_USER /srv

# 7. Déploiement docker (sans YunoHost par défaut)
if [ ! -f /srv/.docker_setup_done ]; then
  curl -s https://raw.githubusercontent.com/dadou646/malczuk-server-setup/main/install-no-yunohost.sh | bash
  touch /srv/.docker_setup_done
else
  echo "✅ Déploiement docker déjà effectué"
fi

# 8. Assistant vocal IA - Jarvis
if [ ! -f /srv/jarvis/.installed ]; then
  curl -s https://malczuk-server.nohost.me/scripts/install-jarvis.sh | bash
  touch /srv/jarvis/.installed
else
  echo "✅ Jarvis déjà installé"
fi

# 9. Synchronisation iCloud + import disque externe
# (À venir : installation rclone + détection disques)

# 10. Fin de l'installation
clear
echo "✅ Installation terminée ! Redémarre le serveur si nécessaire."
echo "Tu peux accéder à Yacht via : http://malczuk.local:8000"
echo "Et bientôt piloter Jarvis depuis ton iPhone avec 'Jarvis' comme mot-clé."
