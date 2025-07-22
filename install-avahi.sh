#!/bin/bash

# S'arrête dès qu'une commande échoue
set -e

echo "🔧 Installation de Avahi et configuration réseau..."

# Vérifie si le script est exécuté en tant que root
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en tant que root (sudo)."
  exit 1
fi

# Mettre à jour les paquets
apt update

# Installer Avahi
apt install -y avahi-daemon avahi-utils libnss-mdns

# Activer et démarrer le service Avahi
systemctl enable avahi-daemon --now

# Vérification
echo "✅ Avahi installé et activé !"
echo "🔁 Redémarrage du service pour appliquer les modifications..."
systemctl restart avahi-daemon

# Afficher l'état
echo "🔍 État du service Avahi :"
systemctl status avahi-daemon --no-pager

# Fin
echo "🎉 Configuration terminée. Tu peux maintenant accéder à ce serveur via : malczuk.local"
