#!/bin/bash
set -euo pipefail

HEALTH_FILE="/tmp/tunnel_healthy"

cleanup() {
  echo "Caught termination signal, shutting down..."

  # Kill autossh/ssh if running
  pkill -TERM autossh || true
  pkill -TERM ssh || true

  # Kill openvpn
  pkill -TERM openvpn || true

  rm -f "$HEALTH_FILE"

  exit 0
}

trap cleanup SIGTERM SIGINT

echo "==== Starting tunnel container ===="

# ----------------------------
# VPN setup
# ----------------------------
if [ -n "${VPN_CONFIG_B64:-}" ]; then
  echo "Decoding OpenVPN config"
  mkdir -p /vpn
  echo "$VPN_CONFIG_B64" | base64 -d > /vpn/config.ovpn
fi

if [ -n "${VPN_USERNAME:-}" ] && [ -n "${VPN_PASSWORD:-}" ]; then
  echo "Creating VPN auth file"
  cat > /tmp/vpn-auth.txt <<EOF
$VPN_USERNAME
$VPN_PASSWORD
EOF
  chmod 600 /tmp/vpn-auth.txt
fi

# ----------------------------
# SSH key setup
# ----------------------------
if [ -n "${SSH_KEY_B64:-}" ]; then
  echo "Setting up SSH key"
  mkdir -p ~/.ssh
  echo "$SSH_KEY_B64" | base64 -d > ~/.ssh/id_rsa
  chmod 600 ~/.ssh/id_rsa
fi

# ----------------------------
# Start OpenVPN
# ----------------------------
echo "Starting OpenVPN..."
openvpn --config /vpn/config.ovpn --auth-user-pass /tmp/vpn-auth.txt --daemon

echo "Waiting for VPN (tun0)..."
until ip link show tun0 >/dev/null 2>&1; do
  sleep 2
done

echo "VPN connected"

# ----------------------------
# Clean remote port BEFORE tunnel
# ----------------------------
echo "Cleaning remote port ${REMOTE_PORT} on ${SSH_HOST}..."

ssh -o StrictHostKeyChecking=no ${SSH_USER}@${SSH_HOST} <<EOF || true
echo "Checking for processes on port ${REMOTE_PORT}..."

if command -v lsof >/dev/null 2>&1; then
  PIDS=\$(lsof -ti tcp:${REMOTE_PORT})
elif command -v ss >/dev/null 2>&1; then
  PIDS=\$(ss -ltnp | grep ":${REMOTE_PORT} " | sed -E 's/.*pid=([0-9]+).*/\1/' | sort -u)
else
  PIDS=""
fi

if [ -n "\$PIDS" ]; then
  echo "Killing processes: \$PIDS"
  kill -9 \$PIDS || true
else
  echo "No process using port ${REMOTE_PORT}"
fi
EOF

# ----------------------------
# Start autossh with retry
# ----------------------------
echo "Starting SSH tunnel..."

while true; do
  autossh -M 0 -N \
    -o "StrictHostKeyChecking=no" \
    -o "ServerAliveInterval=30" \
    -o "ServerAliveCountMax=3" \
    -o "ExitOnForwardFailure=yes" \
    -R 0.0.0.0:${REMOTE_PORT}:${TARGET_HOST}:${TARGET_PORT} \
    ${SSH_USER}@${SSH_HOST}

  echo "SSH tunnel exited. Retrying in 5 seconds..."
  rm -f "$HEALTH_FILE"
  sleep 5
done &
AUTOSSH_PID=$!

# ----------------------------
# Health monitor loop
# ----------------------------
echo "Starting health monitor..."

while true; do
  if ip link show tun0 >/dev/null 2>&1 && pgrep -f autossh >/dev/null 2>&1; then
    touch "$HEALTH_FILE"
  else
    echo "Health check failed: VPN or SSH missing"
    rm -f "$HEALTH_FILE"
  fi
  sleep 5
done &

wait $AUTOSSH_PID
