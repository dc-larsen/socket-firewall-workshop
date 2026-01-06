# Socket Firewall Service Mode Demo

A Docker-based demo of Socket Firewall running in service mode, intercepting and blocking malicious packages from npm and PyPI registries.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  node-client    │     │    firewall     │     │  npm/pypi       │
│  (npm install)  │────▶│  (proxy:8080)   │────▶│  registries     │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
┌─────────────────┐              │
│  python-client  │              ▼
│  (pip install)  │────▶   Socket API
└─────────────────┘        (block/allow)
```

## Quick Start

### 1. Generate CA Certificates

```bash
mkdir -p certs && cd certs

openssl genrsa -out socketFirewallCa.key 2048

openssl req -x509 -new -nodes \
  -key socketFirewallCa.key \
  -sha256 -days 365 \
  -out socketFirewallCa.crt \
  -subj "/CN=Socket Security CA/O=Socket Security/C=US"

cd ..
```

### 2. Configure API Key

```bash
echo "SOCKET_API_KEY=sktsec_YOUR_API_KEY_HERE" > .env.secrets
```

Get your API key from [socket.dev/dashboard](https://socket.dev/dashboard). Required scopes: `packages`, `entitlements:list`.

### 3. Start Containers

```bash
docker compose up -d
```

### 4. Run Demo

```bash
./demo.sh
```

## Manual Testing

### Test Allowed Package

```bash
docker exec sfw-node-client npm install lodash
docker exec sfw-python-client pip install requests
```

### Test Blocked Packages

```bash
# npm - known malware
docker exec sfw-node-client npm install form-data@2.3.3

# pypi - vulnerable version
docker exec sfw-python-client pip install urllib3==1.16
```

### View Firewall Logs

```bash
docker logs -f socket-firewall
```

## Example Blocked Packages

| Package | Ecosystem | Reason |
|---------|-----------|--------|
| `form-data@2.3.3` | npm | Known malware |
| `urllib3@1.16` | pypi | Critical vulnerabilities |
| `event-stream@3.3.6` | npm | Malicious code injection |
| `crossenv` | npm | Typosquat of cross-env |
| `python3-dateutil` | pypi | Typosquat of python-dateutil |

## Files

```
├── docker-compose.yml    # 3-container setup
├── Dockerfile.sfw        # Socket Firewall image (ARM64)
├── .env.secrets          # API key (not committed)
├── certs/
│   ├── socketFirewallCa.crt
│   └── socketFirewallCa.key
└── demo.sh               # Demo script
```

## Commands Reference

```bash
# Start
docker compose up -d

# Stop
docker compose down

# Rebuild after changes
docker compose up -d --build

# View logs
docker logs -f socket-firewall

# Shell into client
docker exec -it sfw-node-client sh
docker exec -it sfw-python-client bash
```

## Configuration

### Environment Variables (Firewall)

| Variable | Description |
|----------|-------------|
| `SOCKET_API_KEY` | Socket API key |
| `SFW_HOSTNAME` | Proxy hostname |
| `SFW_CA_CERT_PATH` | Path to CA certificate |
| `SFW_CA_KEY_PATH` | Path to CA private key |
| `SFW_HTTP_PORT` | HTTP proxy port (default: 8080) |
| `SFW_HTTPS_PORT` | HTTPS proxy port (default: 8443) |
| `SFW_DEBUG` | Enable debug logging |

### Client Configuration

Clients route traffic through the firewall using:

- `HTTPS_PROXY=http://firewall:8080`
- `NODE_EXTRA_CA_CERTS=/certs/ca.crt` (Node.js)
- `PIP_CERT=/certs/ca.crt` (Python)

## Troubleshooting

**Containers not starting?**
```bash
docker compose logs firewall
```

**SSL errors?**
- Ensure CA cert is mounted correctly
- Check `NODE_EXTRA_CA_CERTS` / `PIP_CERT` env vars

**Packages not being blocked?**
- Verify `SOCKET_API_KEY` is valid
- Check org policy settings at socket.dev/dashboard

## Resources

- [Socket Firewall Wiki](https://github.com/SocketDev/firewall-release/wiki)
- [Socket Dashboard](https://socket.dev/dashboard)
