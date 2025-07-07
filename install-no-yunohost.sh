#!/bin/bash
set -e

echo "🔄 Mise à jour de Debian..."
sudo apt update && sudo apt upgrade -y

echo "🐳 Installation de Docker + Yacht..."
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
sudo systemctl enable docker
sudo systemctl start docker

echo "📦 Installation de Docker Compose + utilitaires..."
sudo apt install -y docker-compose curl git

echo "🚢 Lancement de Yacht (interface de gestion Docker)..."
docker volume create yacht
docker run -d \
  -p 8000:8000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v yacht:/config \
  --restart=always \
  selfhostedpro/yacht

echo "📁 Clonage du dépôt et préparation du docker-compose..."
git clone https://github.com/dadou646/malczuk-server-setup.git ~/malczuk-server
cd ~/malczuk-server

echo "⚙️ Lancement des services (sans YunoHost)..."
docker-compose -f docker-compose.no-yunohost.yml up -d

echo "✅ Installation terminée ! Accède à Yacht sur : http://<ip_debian>:8000"
