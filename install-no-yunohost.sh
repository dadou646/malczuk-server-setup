#!/bin/bash
set -e

echo "🔄 Mise à jour de Debian..."
sudo apt update && sudo apt upgrade -y

echo "🐳 Installation de Docker..."
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
sudo systemctl enable docker
sudo systemctl start docker

echo "📦 Installation de Docker Compose, Git et Curl..."
sudo apt install -y docker-compose git curl

echo "🚢 Lancement de Yacht (interface Docker)..."
docker volume create yacht
docker run -d \
  -p 8000:8000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v yacht:/config \
  --restart unless-stopped \
  selfhostedpro/yacht

echo "📁 Clonage du dépôt du serveur..."
git clone https://github.com/dadou646/malczuk-server-setup.git /opt/malczuk-server-setup
cd /opt/malczuk-server-setup

if [ ! -f docker-compose.no-yunohost.yml ]; then
  echo "❌ Le fichier docker-compose.no-yunohost.yml est introuvable. Vérifie ton dépôt GitHub."
  exit 1
fi

echo "⚙️ Lancement des services (sans YunoHost)..."
docker compose -f docker-compose.no-yunohost.yml up -d

echo ""
echo "✅ Installation terminée !"
echo "📍 Accède à Yacht sur : http://$(hostname -I | awk '{print $1}'):8000"
echo "ℹ️ Déconnecte-toi ou redémarre pour que les droits Docker soient appliqués (groupe docker)."
