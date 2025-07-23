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

# 5. WireGuard VPN ultra-sécurisé (malczuk-vpn)
if [ ! -f /etc/wireguard/malczuk-vpn.conf ]; then
  echo "🔐 Installation et configuration de WireGuard (malczuk-vpn)..."

  apt install -y wireguard ufw qrencode

  mkdir -p /srv/wireguard
  cd /srv/wireguard

  # Génération clés serveur et client
  wg genkey | tee server_private.key | wg pubkey > server_public.key
  wg genkey | tee client_private.key | wg pubkey > client_public.key

  SERVER_PRIV=$(cat server_private.key)
  SERVER_PUB=$(cat server_public.key)
  CLIENT_PRIV=$(cat client_private.key)
  CLIENT_PUB=$(cat client_public.key)

  SERVER_IP="192.168.1.31"
  VPN_SUBNET="10.8.0.0/24"

  # === Création conf serveur
  cat <<EOF > /etc/wireguard/malczuk-vpn.conf
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIV
SaveConfig = true

# Client autorisé
[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = 10.8.0.2/32
EOF

  chmod 600 /etc/wireguard/malczuk-vpn.conf

  systemctl enable wg-quick@malczuk-vpn
  systemctl start wg-quick@malczuk-vpn

  # === Génération client
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

  echo "✅ VPN WireGuard configuré sur interface : malczuk-vpn"
  echo "📁 Fichier client prêt : /srv/wireguard/malczuk-client.conf"

  # === UFW : pare-feu ultra-sécurisé
  echo "🔥 Configuration du pare-feu (UFW)..."
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 51820/udp comment 'WireGuard VPN'
  ufw allow in on lo
  ufw --force enable
else
  echo "✅ WireGuard déjà configuré (malczuk-vpn)"
fi


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
  echo "🔧 Installation de l’assistant vocal Jarvis..."

  apt install -y portaudio19-dev ffmpeg libffi-dev build-essential sox jq inotify-tools rsync fuse unzip python3 python3-pip

  # Installation des dépendances Python
  pip install -U openai-whisper TTS

  # Installation d’Ollama + Mistral
  curl -fsSL https://ollama.com/install.sh | sh
  systemctl enable ollama --now
  ollama pull mistral

  # Script Jarvis
  cat << 'EOF' > /srv/jarvis/jarvis.py
#!/usr/bin/env python3
import os, time, subprocess, requests
import speech_recognition as sr

TRIGGER = "jarvis"
LANG = "fr-FR"
HA_TOKEN = "YOUR_LONG_LIVED_ACCESS_TOKEN"
HA_URL = "http://localhost:8123/api/services/media_player/volume_set"
AMP_ENTITY = "media_player.yamaha_receiver"
DEFAULT_VOLUME = 0.4
RESPONSE_VOLUME = 0.7

def set_volume(vol):
    requests.post(HA_URL, headers={"Authorization": f"Bearer {HA_TOKEN}"}, json={
        "entity_id": AMP_ENTITY,
        "volume_level": vol
    })

r = sr.Recognizer()
with sr.Microphone() as source:
    print("🎧 Jarvis écoute...")
    while True:
        audio = r.listen(source)
        try:
            text = r.recognize_whisper(audio, language=LANG)
            if TRIGGER in text.lower():
                print("✅ Mot-clé détecté !")
                set_volume(RESPONSE_VOLUME)
                response = subprocess.check_output(["ollama", "run", "mistral", text], text=True)
                os.system(f"echo '{response}' | TTS --text - --out_path /srv/jarvis/response.wav && aplay /srv/jarvis/response.wav")
                set_volume(DEFAULT_VOLUME)
        except Exception as e:
            print("[Erreur]", e)
EOF

  chmod +x /srv/jarvis/jarvis.py

  # Service systemd
  cat << EOF > /etc/systemd/system/jarvis.service
[Unit]
Description=Jarvis Voice Assistant
After=network.target

[Service]
ExecStart=/usr/bin/python3 /srv/jarvis/jarvis.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable jarvis.service --now

  touch /srv/jarvis/.installed
else
  echo "✅ Jarvis déjà installé"
fi

# 9. iCloud + tri photos
if [ ! -f /usr/local/bin/tri_photos.sh ]; then
  echo "📸 Configuration de la synchro iCloud + tri photos..."

  mkdir -p /mnt/photos_icloud /mnt/sources_hdd /mnt/Malczuk_Backup /mnt/data/nextcloud/data/admin/files/Photos

  docker rm -f icloudpd || true
  docker run -d --name icloudpd \
    -v /mnt/photos_icloud:/data \
    -e username='davidmalczuk@icloud.com' \
    boredazfcuk/icloudpd

  cat << 'EOF' > /usr/local/bin/tri_photos.sh
#!/bin/bash
DEST="/srv/photos"
mkdir -p "$DEST"

for SOURCE in /mnt/photos_icloud /mnt/data/nextcloud/data/admin/files/Photos; do
  find "$SOURCE" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.heic" \) | while read file; do
    year=$(date -r "$file" +%Y)
    month=$(date -r "$file" +%m)
    mkdir -p "$DEST/$year/$year-$month"
    filename=$(basename "$file")
    cp -u "$file" "$DEST/$year/$year-$month/$filename"
    # Suppression IA des doublons à venir
  done
done
EOF
  chmod +x /usr/local/bin/tri_photos.sh
else
  echo "✅ Script de tri photo déjà présent"
fi

# 10. Home Assistant
if [ ! $(docker ps -a --format '{{.Names}}' | grep -w homeassistant) ]; then
  echo "🏠 Lancement de Home Assistant..."
  docker run -d \
    --name homeassistant \
    --restart unless-stopped \
    --privileged \
    -v /mnt/data/homeassistant:/config \
    -v /etc/localtime:/etc/localtime:ro \
    --device /dev/serial/by-id/usb-0658_0200-if00 \
    -p 8123:8123 \
    ghcr.io/home-assistant/home-assistant:stable
else
  echo "✅ Home Assistant déjà en cours"
fi

# 11. Fin
clear
echo "✅ Installation terminée !"
echo "🧠 Jarvis est actif avec IA Mistral (local) + reconnaissance vocale"
echo "🎙 Détection par mot-clé : Jarvis"
echo "🔊 Contrôle volume via Yamaha RX-V477"
echo "📷 Photos triées automatiquement par année/mois"
echo "🌐 Home Assistant dispo sur : http://malczuk.local:8123"
echo "📁 Interface Docker (Yacht) : http://malczuk.local:8000"
