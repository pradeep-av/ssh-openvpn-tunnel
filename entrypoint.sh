#!/bin/bash
set -e

if [ -n "$VPN_CONFIG_B64" ]; then
  echo "Decoding and saving OpenVPN configuration"

  mkdir -p /vpn
  echo "$VPN_CONFIG_B64" | base64 -d > /vpn/config.ovpn
fi

if [ -n "$VPN_USERNAME" ] && [ -n "$VPN_PASSWORD" ]; then
  echo "Creating OpenVPN credentials file"

  cat > /tmp/vpn-auth.txt <<EOF
$VPN_USERNAME
$VPN_PASSWORD
EOF

  chmod 600 /tmp/vpn-auth.txt
fi

if [ -n "$SSH_KEY_B64" ]; then
  echo "Setting up SSH key"

  mkdir -p ~/.ssh
  echo "$SSH_KEY_B64" | base64 -d > ~/.ssh/id_rsa
  chmod 600 ~/.ssh/id_rsa
fi

echo "Starting OpenVPN..."

openvpn --config /vpn/config.ovpn --auth-user-pass /tmp/vpn-auth.txt --daemon

echo "Waiting for VPN..."

while ! ip route | grep -q tun; do
  sleep 2
done

echo "VPN connected"

autossh -M 0 -N \
  -o "StrictHostKeyChecking=no" \
  -o "ServerAliveInterval=30" \
  -o "ServerAliveCountMax=3" \
  -R ${REMOTE_PORT}:${TARGET_HOST}:${TARGET_PORT} \
  ${SSH_USER}@${SSH_HOST}