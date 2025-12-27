
# Setup script for Proxmox container with SpotDL
# Run this script inside your LXC container after creating it
#!/bin/bash
set -euo pipefail

APP_DIR="/opt/spotdl-web"
SERVICE_NAME="spotdl-web"
MUSIC_DIR="/music"

SPOTDL_TOKEN="${SPOTDL_TOKEN:-your-secret-token-here}"

echo "=========================================="
echo "SpotDL Container/Server Setup"
echo "=========================================="

echo "[1/7] System update + dependencies..."
apt-get update
apt-get upgrade -y
apt-get install -y python3 python3-pip python3-full ffmpeg curl rsync

echo "[2/7] Installing Python packages globally..."
pip3 install --upgrade pip --break-system-packages
pip3 install flask spotdl --break-system-packages

echo "[3/7] Validating source directory..."
if [ ! -f "./app.py" ]; then
  echo "ERROR: app.py not found. Run this script from the extracted ZIP repo root."
  exit 1
fi

if [ ! -f "./templates/index.html" ] || [ ! -f "./templates/login.html" ]; then
  echo "ERROR: templates/index.html and/or templates/login.html not found."
  echo "Expected: ./templates/index.html and ./templates/login.html"
  exit 1
fi

echo "[4/7] Creating target directories..."
mkdir -p "$APP_DIR" "$MUSIC_DIR"
chmod 755 "$MUSIC_DIR"

echo "[5/7] Deploying application to ${APP_DIR}..."
rsync -a --delete \
  --exclude ".git" \
  --exclude "__pycache__" \
  --exclude "*.pyc" \
  ./ "$APP_DIR/"

echo "[6/7] Creating systemd service..."
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=SpotDL Web Interface
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
Environment="SPOTDL_TOKEN=${SPOTDL_TOKEN}"
Environment="SPOTDL_PATH=/usr/local/bin/spotdl"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/usr/bin/python3 ${APP_DIR}/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "[7/7] Enabling and starting service..."
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}.service"
systemctl restart "${SERVICE_NAME}.service"



echo ""
echo "=========================================="
echo "✅ Setup complete!"
echo "=========================================="
echo ""
echo "IMPORTANT: Change the access token/password!"
echo "1. Edit: nano /etc/systemd/system/spotdl-web.service"
echo "2. Replace 'your-secret-token-here' with your own token"
echo "3. Run:"
echo "   systemctl daemon-reload"
echo "   systemctl restart spotdl-web"
echo ""
echo "Application running at: http://CONTAINER_IP:5000"
echo "Music downloads to: /music"
echo ""
echo "Service status: systemctl status spotdl-web"
echo "Logs: journalctl -u spotdl-web -f"
echo "=========================================="

