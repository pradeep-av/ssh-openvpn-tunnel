# ssh-openvpn-tunnel

Run a Docker container that:

1. Connects to OpenVPN using a base64-encoded `.ovpn` config and username/password.
2. Establishes a reverse SSH tunnel with `autossh`.

This is useful when a target host is reachable only over VPN, but you need to expose it through an SSH server.

## Prerequisites

- Docker installed and running
- OpenVPN client config file (for example `~/myvpn.ovpn`)
- SSH private key with access to the SSH jump host
- Linux host with `/dev/net/tun` available

## Build image

```bash
docker build -t ssh-openvpn-tunnel:latest .
```

## Required environment variables

| Variable | Description |
|---|---|
| `VPN_CONFIG_B64` | Base64 of OpenVPN config file (`.ovpn`) |
| `VPN_USERNAME` | OpenVPN username |
| `VPN_PASSWORD` | OpenVPN password |
| `SSH_KEY_B64` | Base64 of SSH private key (for `SSH_USER`) |
| `SSH_HOST` | SSH server used for reverse tunnel |
| `SSH_USER` | SSH username |
| `REMOTE_PORT` | Port opened on SSH server |
| `TARGET_HOST` | Host you want to expose, must be reachable from the container |
| `TARGET_PORT` | Port on target host to expose |

## Example run

```bash
export VPN_USERNAME="<vpn-username>"
export VPN_PASSWORD="<vpn-password>"
export VPN_CONFIG_B64=$(base64 -w 0 ~/myvpn.ovpn)
export SSH_KEY_B64=$(base64 -w 0 ~/.ssh/id_rsa)
export SSH_HOST="<ssh-host>"
export SSH_USER="<ssh-user>"
export REMOTE_PORT=8080
export TARGET_HOST="192.168.64.6"
export TARGET_PORT=80

docker run -d \
	--name lab-tunnel \
	--cap-add=NET_ADMIN \
	--device /dev/net/tun \
	-e VPN_CONFIG_B64="$VPN_CONFIG_B64" \
	-e VPN_USERNAME="$VPN_USERNAME" \
	-e VPN_PASSWORD="$VPN_PASSWORD" \
	-e SSH_KEY_B64="$SSH_KEY_B64" \
	-e SSH_HOST="$SSH_HOST" \
	-e SSH_USER="$SSH_USER" \
	-e REMOTE_PORT="$REMOTE_PORT" \
	-e TARGET_HOST="$TARGET_HOST" \
	-e TARGET_PORT="$TARGET_PORT" \
	ghcr.io/pradeep-av/ssh-openvpn-tunnel:main
```

## Verify

```bash
docker logs -f lab-tunnel
```

Expected log sequence:

- `Starting OpenVPN...`
- `VPN connected`

Then test by connecting to the webservice forwarded through the SSH server:

```bash
curl http://localhost:8080
```

## Stop and cleanup

```bash
docker rm -f lab-tunnel
```

## Kubernetes sample

A sample Kubernetes manifest is available at `k8s/deployment.yaml`.

It includes:

- A `Secret` holding all required environment variables
- A single-replica `Deployment` using `ghcr.io/pradeep-av/ssh-openvpn-tunnel:main`
- `NET_ADMIN` capability and host `/dev/net/tun` mount

Apply it:

```bash
kubectl apply -f k8s/deployment.yaml
```

Check status/logs:

```bash
kubectl get pods -l app=ssh-openvpn-tunnel
kubectl logs -f deploy/ssh-openvpn-tunnel
```

## Notes

- `StrictHostKeyChecking=no` is currently set in `autossh` options by the container entrypoint.
- Keep secrets out of git. Do not commit real usernames, passwords, keys, or VPN files.