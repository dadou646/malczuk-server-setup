#!/bin/bash

set -e

### Variables de configuration ###
SERVER_USER="$(whoami)"
EXTERNAL_DRIVE_LABEL="Malczuk_Backup"
INSTALL_DIR="/opt/malczuk-server"
REPO_URL="https://github.com/dadou646/malczuk-server-setup.git"

### Fonctions ###
log() {
    echo -e "[\e[34mINFO\e[0m] $1"
}

install_package() {
    if ! dpkg -s "$1" >/dev/null 2>&1; then
        log "Installation de $1..."
        apt-get install -y "$1"
    else
        log "$1 est déjà installé."
    fi
}

### Prérequis ###
log "Mise à jour du système..."
apt-get update && apt-get upgrade -y

log "Installation des dépendances..."
install_package curl
install_package git
install_package docker.io
install_package docker-compose
install_package avahi-daemon
install_package sudo
install_package libasound2
install_package wireguard

usermod -aG docker "$SERVER_USER"

### Clone du dépôt ###
if [ ! -d "$INSTALL_DIR" ]; then
    log "Clonage du dépôt..."
    git clone "$REPO_URL" "$INSTALL_DIR"
else
    log "Déjà cloné. Mise à jour du dépôt..."
    cd "$INSTALL_DIR" && git pull
fi

### Installation des composants via Docker ###
log "Lancement de Docker Compose (sans YunoHost)..."
cd "$INSTALL_DIR" && docker-compose -f docker-compose.no-yunohost.yml up -d

### Assistant vocal JARVIS ###
if [ ! -f "$INSTALL_DIR/scripts/install-jarvis.sh" ]; then
    log "Script Jarvis manquant !"
else
    bash "$INSTALL_DIR/scripts/install-jarvis.sh"
fi

### Synchronisation iCloud + Disque externe ###
log "Configuration de la synchronisation iCloud..."
if [ -f "$INSTALL_DIR/scripts/sync-icloud.sh" ]; then
    bash "$INSTALL_DIR/scripts/sync-icloud.sh"
fi

log "Vérification du disque externe pour sauvegarde automatique..."
if mount | grep "$EXTERNAL_DRIVE_LABEL" >/dev/null; then
    bash "$INSTALL_DIR/scripts/sync-external-disk.sh"
else
    log "Disque $EXTERNAL_DRIVE_LABEL non connecté. En attente de connexion future."
fi

log "Installation terminée. Tu peux accéder à Home Assistant, Nextcloud, etc. via le domaine : http://malczuk-server.nohost.me"
log "Redémarre ton serveur si tu viens d'ajouter un nouveau groupe (Docker, sudo...) pour appliquer les droits."
