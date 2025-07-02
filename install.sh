#!/bin/bash

set -e

echo "🔧 Mise à jour du système..."
apt update && apt upgrade -y

echo "📦 Installation des paquets nécessaires..."
apt install -y curl sudo git wget htop docker.io docker-compose openssh-server

echo "🧰 Installation de Yacht (interface Docker)..."
docker volume create yacht
docker run -d \
  -p 8000:8000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v yacht:/config \
  --restart=always \
  ghcr.io/selfhostedpro/yacht

echo "📂 Clonage du dépôt serveur..."
mkdir -p /opt/malczuk-server
cd /opt/malczuk-server
git clone https://github.com/dadou646/malczuk-server-setup .

echo "✅ Configuration initiale terminée."
echo "🖥️ Rendez-vous sur http://<IP-de-votre-serveur>:8000 pour accéder à Yacht."
