#!/bin/bash
set -e

# =============================
# Malczuk Server - install.sh
# =============================
# Serveur personnel domotique sécurisé, intelligent et automatisé
# Auteur : David Malczuk
# ================================================

# Vérification root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en tant que root (sudo)."
  exit 1
fi

# === Définition des variables ===
DATA_DISK="/mnt/data"

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

# 5. WireGuard VPN ultra-sécurisé (malczuk-vpn)
if [ ! -f /etc/wireguard/malczuk-vpn.conf ]; then
  echo "🔐 Installation et configuration de WireGuard (malczuk-vpn)..."

  apt install -y wireguard ufw qrencode

  mkdir -p /srv/wireguard
  cd /srv/wireguard

  wg genkey | tee server_private.key | wg pubkey > server_public.key
  wg genkey | tee client_private.key | wg pubkey > client_public.key

  SERVER_PRIV=$(cat server_private.key)
  SERVER_PUB=$(cat server_public.key)
  CLIENT_PRIV=$(cat client_private.key)
  CLIENT_PUB=$(cat client_public.key)

  SERVER_IP="192.168.1.31"

  cat <<EOF > /etc/wireguard/malczuk-vpn.conf
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIV
SaveConfig = true

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = 10.8.0.2/32
EOF

  chmod 600 /etc/wireguard/malczuk-vpn.conf

  systemctl enable wg-quick@malczuk-vpn
  systemctl start wg-quick@malczuk-vpn

  cat <<EOF > /srv/wireguard/malczuk-client.conf
[Interface]
PrivateKey = $CLIENT_PRIV
Address = 10.8.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = ${SERVER_IP}:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

  chmod 600 /srv/wireguard/malczuk-client.conf

  qrencode -t ansiutf8 < /srv/wireguard/malczuk-client.conf

  echo "✅ VPN WireGuard configuré"
  echo "📁 Fichier client : /srv/wireguard/malczuk-client.conf"

  echo "🔥 Configuration pare-feu (ufw)"
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 51820/udp comment 'WireGuard VPN'
  ufw allow in on lo
  ufw --force enable
else
  echo "✅ WireGuard déjà configuré"
fi

# 6. Préparation des répertoires
mkdir -p $DATA_DISK/nextcloud $DATA_DISK/homeassistant /mnt/Malczuk_Backup
chown -R $SUDO_USER:$SUDO_USER $DATA_DISK

# 7. Recréation propre de Nextcloud (sur HDD)
docker rm -f nextcloud || true
docker run -d \
  --name nextcloud \
  --restart unless-stopped \
  -v $DATA_DISK/nextcloud:/var/www/html \
  -p 8080:80 \
  nextcloud

# 8. Recréation propre de Home Assistant (sur HDD)
docker rm -f homeassistant || true
docker run -d \
  --name homeassistant \
  --restart unless-stopped \
  --privileged \
  -v $DATA_DISK/homeassistant:/config \
  -v /etc/localtime:/etc/localtime:ro \
  --device /dev/serial/by-id/usb-0658_0200-if00 \
  -p 8123:8123 \
  ghcr.io/home-assistant/home-assistant:stable

# 9. Fin
clear
echo "✅ Serveur Malczuk installé et sécurisé !"
echo "🌐 Nextcloud : http://malczuk.local:8080"
echo "🏠 Home Assistant : http://malczuk.local:8123"
echo "🔐 Accès distant via VPN (WireGuard uniquement)"

# ======================================================
# ## Tri automatique des photos iCloud + Nextcloud
# Ajouté automatiquement le 2025-07-26
# ======================================================

cat << 'EOF' > /usr/local/bin/tri_photos.sh
#!/bin/bash
DEST="/srv/photos"
ICLOUD_SOURCE="/mnt/photos_icloud"
NC_BASE="/mnt/data/nextcloud/data"

# Fonction pour traiter un dossier source
process_photos() {
  SOURCE="$1"
  [ -d "$SOURCE" ] || return

  find "$SOURCE" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" \) | while read file; do
    year=$(date -r "$file" +%Y)
    month=$(date -r "$file" +%m)
    mkdir -p "$DEST/$year/$year-$month"
    filename=$(basename "$file")
    cp -u "$file" "$DEST/$year/$year-$month/$filename"
  done
}

# 🔁 Traiter iCloud
process_photos "$ICLOUD_SOURCE"

# 🔁 Traiter tous les utilisateurs Nextcloud
for PHOTOS_DIR in "$NC_BASE"/*/files/Photos; do
  process_photos "$PHOTOS_DIR"
done
EOF

chmod +x /usr/local/bin/tri_photos.sh

# Ajout du cron (si absent)
( crontab -l 2>/dev/null | grep -v tri_photos ; echo "*/10 * * * * /usr/local/bin/tri_photos.sh" ) | crontab -

# ======================================================
# ## Amélioration IA des photos (netteté, redressement)
# Ajouté automatiquement le 2025-07-26 06:44:50
# ======================================================

apt install -y python3 python3-pip || true
pip3 install --upgrade pip || true
pip3 install pillow opencv-python-headless || true

cat << 'EOF' > /usr/local/bin/amelioration_photos.sh
#!/usr/bin/env python3
import cv2
import os
from PIL import Image
from pathlib import Path
from datetime import datetime

log_file = "/var/log/tri_ia_photo.log"
photo_root = Path("/srv/photos")

def is_blurry(image, threshold=100):
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    return cv2.Laplacian(gray, cv2.CV_64F).var() < threshold

def correct_rotation(image):
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 50, 150)
    lines = cv2.HoughLines(edges, 1, 3.14/180, 200)
    angle = 0.0
    if lines is not None:
        angles = [(theta * 180 / 3.14) for rho, theta in lines[:, 0]]
        angle = sum(angles) / len(angles) - 90
    (h, w) = image.shape[:2]
    M = cv2.getRotationMatrix2D((w//2, h//2), angle, 1.0)
    return cv2.warpAffine(image, M, (w, h))

def enhance(path):
    try:
        image = cv2.imread(str(path))
        if image is None:
            return
        modified = False
        if is_blurry(image):
            image = cv2.detailEnhance(image, sigma_s=10, sigma_r=0.15)
            modified = True
        image = correct_rotation(image)
        modified = True
        if modified:
            cv2.imwrite(str(path), image)
            with open(log_file, "a") as log:
                log.write("[{}] ✅ Amélioré : {}\n".format(datetime.now().isoformat(), path))
    except Exception as e:
        with open(log_file, "a") as log:
            log.write("[{}] ❌ Erreur : {} -> {}\n".format(datetime.now().isoformat(), path, e))

for ext in ("*.jpg", "*.jpeg", "*.png", "*.heic"):
    for photo in photo_root.rglob(ext):
        enhance(photo)
EOF

chmod +x /usr/local/bin/amelioration_photos.sh

# Exécution immédiate
/usr/local/bin/amelioration_photos.sh || true

# Ajout cron mensuel (1er du mois à 3h)
( crontab -l 2>/dev/null | grep -v amelioration_photos ; echo "0 3 1 * * /usr/local/bin/amelioration_photos.sh" ) | crontab -

#!/bin/bash

BACKUP_DIR="/mnt/Malczuk_Backup/homeassistant"
SOURCE="/mnt/data/homeassistant"
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
DEST="$BACKUP_DIR/$TIMESTAMP"

mkdir -p "$DEST"
rsync -a --delete "$SOURCE/" "$DEST/"

# Supprimer les plus anciennes sauvegardes (garder les 10 dernières)
cd "$BACKUP_DIR"
ls -dt */ | tail -n +11 | xargs rm -rf

echo "✅ Sauvegarde Home Assistant terminée : $TIMESTAMP"

# ======================================================
# ## Sauvegarde automatique de Home Assistant
# Ajouté automatiquement le 2025-07-26 07:26
# ======================================================

cat << 'EOF' > /usr/local/bin/backup_homeassistant.sh
#!/bin/bash
SOURCE="/mnt/data/homeassistant"
DEST_BASE="/mnt/Malczuk_Backup/homeassistant"
TIMESTAMP=$(date +"%Y-%m-%d_%H%M%S")
DEST="$DEST_BASE/$TIMESTAMP"

mkdir -p "$DEST"
rsync -a --delete "$SOURCE/" "$DEST/"

# Garder les 10 dernières sauvegardes uniquement
cd "$DEST_BASE"
ls -dt */ | tail -n +11 | xargs rm -rf

echo "✅ Sauvegarde terminée à $TIMESTAMP"
EOF

chmod +x /usr/local/bin/backup_homeassistant.sh

# Ajout au cron quotidien à 2h
( crontab -l 2>/dev/null | grep -v backup_homeassistant ; echo "0 2 * * * /usr/local/bin/backup_homeassistant.sh" ) | crontab -

# 🔒 Protection contre perte de configuration
if [ -d /mnt/data/homeassistant ]; then
  echo "✅ Dossier Home Assistant détecté, pas de suppression."
else
  echo "⚠️ Dossier /mnt/data/homeassistant manquant, initialisation..."
  mkdir -p /mnt/data/homeassistant
  chown -R $SUDO_USER:$SUDO_USER /mnt/data/homeassistant
fi


