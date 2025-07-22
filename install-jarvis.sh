#!/bin/bash

set -e

# ==========================
# Malczuk Server - Jarvis + Automatisations
# Assistant vocal + iCloud, photos, iPad
# ==========================

# Vérification root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en tant que root."
  exit 1
fi

# === 1. Préparation système ===
echo "🔧 Installation des dépendances système..."
apt update
apt install -y git python3 python3-pip portaudio19-dev ffmpeg libffi-dev curl build-essential sox jq nmap inotify-tools rsync fuse unzip

mkdir -p /srv/jarvis && cd /srv/jarvis

# === 2. Installation Whisper (reconnaissance vocale) ===
echo "🎤 Installation de Whisper..."
pip install -U openai-whisper

# === 3. Installation d’Ollama + modèle Mistral ===
echo "🧠 Installation d’Ollama + Mistral..."
curl -fsSL https://ollama.com/install.sh | sh
systemctl enable ollama --now
ollama pull mistral

# === 4. Installation TTS (text-to-speech) ===
echo "🗣 Installation du moteur TTS..."
pip install TTS

# === 5. Script de reconnaissance vocale Jarvis ===
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
VOICE_PATH = "/srv/jarvis/voice_nathalia.wav"  # Voix de Nathalia (mère de Marie)

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

# === 6. Service Jarvis ===
echo "⚙️ Création du service systemd..."
cat << 'EOT' > /etc/systemd/system/jarvis.service
[Unit]
Description=Jarvis Voice Assistant
After=network.target

[Service]
ExecStart=/usr/bin/python3 /srv/jarvis/jarvis.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOT

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable jarvis.service --now

# === 7. Automatisation iCloud + tri IA photos ===
echo "📸 Configuration de la synchronisation iCloud et du tri IA..."
mkdir -p /mnt/photos_icloud /mnt/sources_hdd /mnt/Malczuk_Backup

# Exemple de montage iCloud avec icloudpd (à configurer avec ton compte)
# docker run -d --name icloudpd \
#   -v /mnt/photos_icloud:/data \
#   -e username='ton_compte@icloud.com' \
#   boredazfcuk/icloudpd

# Script de tri par date + suppression IA des doublons (à venir)
cat << 'EOF' > /usr/local/bin/tri_photos.sh
#!/bin/bash
SOURCE="/mnt/photos_icloud"
DEST="/srv/photos"

mkdir -p "$DEST"
find "$SOURCE" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.heic" \) | while read file; do
  year=$(date -r "$file" +%Y)
  month=$(date -r "$file" +%m)
  mkdir -p "$DEST/$year/$year-$month"
  filename=$(basename "$file")
  cp -u "$file" "$DEST/$year/$year-$month/$filename"
  # Suppression IA des doublons à ajouter ici
done
EOF
chmod +x /usr/local/bin/tri_photos.sh

# Cron (ou service inotify) à ajouter plus tard pour détection disque ou synchro périodique

# === Fin ===
echo "✅ Jarvis est opérationnel."
echo "🎙 Mot-clé : 'Jarvis' – écoute en continu via micro."
echo "🧠 IA locale : Mistral (Ollama) + Whisper pour la reconnaissance vocale."
echo "🗣 Synthèse vocale prête pour intégrer la voix de Nathalia (mère de Marie)."
echo "🔊 Contrôle automatique du volume Yamaha RX-V477 pendant les réponses."
echo "📷 Tri automatique des photos iCloud prêt – classement par année/mois, doublons à filtrer."
