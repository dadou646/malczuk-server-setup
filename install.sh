#!/bin/bash

# ======================================
# malczuk-server - Installation automatique
# Auteur : ChatGPT pour David Malczuk
# ======================================

set -e

### CONFIGURATION DE BASE ###
SERVER_NAME="malczuk-server"
DOMAIN="malczuk-server.nohost.me"
VPN_PORT="51820"
USER=$(logname)
BACKUP_DISK="Malczuk_Backup"
INTERFACE=$(ip route | grep default | awk '{print $5}')

clear

### 1. MISE A JOUR DU SYSTEME ###
echo "🧼 Mise à jour de Debian..."
apt update && apt upgrade -y

### 2. INSTALLATION DES DEPENDANCES ###
echo "🔧 Installation des paquets nécessaires..."
apt install -y sudo curl git ufw net-tools htop rsync ca-certificates gnupg lsb-release unzip fail2ban

### 3. CONFIGURATION DU RÉSEAU STATIQUE (optionnel) ###
# echo "🔌 Configuration IP statique..." (désactivée pour compatibilité)

### 4. INSTALLATION DE DOCKER + YACHT ###
echo "🐳 Installation de Docker + Yacht..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker $USER

# Yacht
docker volume create yacht
docker run -d --name=yacht \
  -p 8000:8000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v yacht:/config \
  --restart=always \
  selfhostedpro/yacht

### 5. INSTALLATION DES CONTAINERS DOCKER ###
echo "📦 Installation des services en containers..."
mkdir -p /opt/malczuk-server
cd /opt/malczuk-server

cat <<EOF > docker-compose.yml
version: '3.8'
services:
  homeassistant:
    image: ghcr.io/home-assistant/home-assistant:stable
    container_name: homeassistant
    network_mode: host
    restart: unless-stopped
    volumes:
      - ./homeassistant:/config
      - /etc/localtime:/etc/localtime:ro

  pihole:
    image: pihole/pihole:latest
    container_name: pihole
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "8080:80"
    environment:
      - TZ=Europe/Paris
      - WEBPASSWORD=admin
    volumes:
      - ./pihole/etc-pihole:/etc/pihole
      - ./pihole/etc-dnsmasq.d:/etc/dnsmasq.d
    restart: unless-stopped

  nextcloud:
    image: nextcloud
    container_name: nextcloud
    ports:
      - "8081:80"
    volumes:
      - ./nextcloud:/var/www/html
    restart: always

  yunohost:
    image: yunohost/yunohost
    container_name: yunohost
    ports:
      - "8082:80"
      - "443:443"
    volumes:
      - ./yunohost:/data
    restart: always

  wireguard:
    image: linuxserver/wireguard
    container_name: wireguard
    ports:
      - "$VPN_PORT:$VPN_PORT/udp"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Paris
    volumes:
      - ./wireguard:/config
      - /lib/modules:/lib/modules
    restart: unless-stopped

EOF

docker compose up -d

### 6. BACKUP AUTOMATIQUE ###
echo "💾 Installation de la sauvegarde auto..."
cat <<'EOF' > /usr/local/bin/auto_backup.sh
#!/bin/bash
BACKUP_DISK="Malczuk_Backup"
MOUNT_POINT="/mnt/backup"
SRC_DIRS="/opt/malczuk-server"
if lsblk | grep -q "$BACKUP_DISK"; then
  mkdir -p $MOUNT_POINT
  mount /dev/disk/by-label/$BACKUP_DISK $MOUNT_POINT
  rsync -av --delete $SRC_DIRS $MOUNT_POINT/
  umount $MOUNT_POINT
fi
EOF
chmod +x /usr/local/bin/auto_backup.sh

echo 'ACTION=="add", KERNEL=="sd*", ENV{ID_FS_LABEL}=="Malczuk_Backup", RUN+="/usr/local/bin/auto_backup.sh"' > /etc/udev/rules.d/99-backup.rules
udevadm control --reload

### 7. INSTALLATION OLLAMA + MISTRAL (IA) ###
echo "🧠 Installation IA locale (Ollama + Mistral)"
curl -fsSL https://ollama.com/install.sh | sh
su - $USER -c "ollama pull mistral"

### 8. AJOUT HOME ASSISTANT CUSTOM DASHBOARD + THEME FUTURISTE ###
echo "🎛️ Préparation du dashboard futuriste..."
mkdir -p /opt/malczuk-server/homeassistant/themes
curl -sSL https://raw.githubusercontent.com/malczuk-server/dashboard/main/custom_theme.yaml -o /opt/malczuk-server/homeassistant/themes/custom_theme.yaml
# Ajout automatique dans configuration.yaml (manuel possible)

### 9. AJOUT SÉCURITÉ IPS/IDS (fail2ban + Snort) ###
echo "🛡️ Sécurité IPS/IDS..."
apt install -y snort
systemctl enable snort

### ✅ FIN DE L'INSTALLATION ###
echo "✅ Installation complète ! Pensez à redémarrer pour activer tous les services."
echo "Tableau de bord : http://malczuk-server.local:8000 (Yacht)"
echo "Accès Home Assistant : http://malczuk-server.local:8123"
echo "Nextcloud : http://malczuk-server.local:8081"
echo "YunoHost Admin : https://malczuk-server.nohost.me/yunohost/admin"
echo "VPN WireGuard prêt sur port $VPN_PORT"

# Fin
