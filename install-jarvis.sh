#!/bin/bash

set -e

# ==========================
# Malczuk Server - Jarvis
# Assistant vocal local IA
# ==========================

# Vérification root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en tant que root."
  exit 1
fi

# === 1. Préparation système ===
echo "🔧 Installation des dépendances système..."
apt update
apt install -y git python3 python3-pip portaudio19-dev ffmpeg libffi-dev curl build-essential sox jq nmap

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
VOICE_PATH = "/srv/jarvis/voice_maman_marina.wav"  # Voix de la mère de Marie (à cloner plus tard)


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

# === Fin ===
echo "✅ Jarvis est en place. Mot-clé : 'Jarvis'. Écoute en permanence."
echo "🔊 Volume Yamaha ajusté dynamiquement pendant la réponse."
echo "🧠 IA locale via Mistral (Ollama) + reconnaissance vocale Whisper."
echo "🗣 Synthèse vocale prête pour intégrer la voix de la mère de Marie."
