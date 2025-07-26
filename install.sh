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
# ## Tri automatique des photos Nextcloud
# Ajouté automatiquement le 2025-07-26 05:53:15
# ======================================================

# Script de tri des photos
cat << 'EOF' > /usr/local/bin/tri_photos.sh
#!/bin/bash
DEST="/srv/photos"
NCPATH="/mnt/data/nextcloud/data"

for PHOTOS_DIR in "$NCPATH"/*/files/Photos; do
  [ -d "$PHOTOS_DIR" ] || continue
  find "$PHOTOS_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" \) | while read file; do
    year=$(date -r "$file" +%Y)
    month=$(date -r "$file" +%m)
    mkdir -p "$DEST/$year/$year-$month"
    filename=$(basename "$file")
    cp -u "$file" "$DEST/$year/$year-$month/$filename"
  done
done
EOF

chmod +x /usr/local/bin/tri_photos.sh

# Ajout du cron (si absent)
( crontab -l 2>/dev/null | grep -v tri_photos ; echo "*/10 * * * * /usr/local/bin/tri_photos.sh" ) | crontab -
