# Socket Firewall Demo

See Socket Firewall block malicious packages in real-time. This demo runs entirely on your laptop using Docker.

## What This Does

When developers install packages (like `npm install` or `pip install`), Socket Firewall intercepts the request, checks if the package is safe, and blocks known malware.

**You'll see:**
- Safe packages install normally
- Malicious packages get blocked with a 403 error

---

## Prerequisites

You need **Docker Desktop** installed. If you don't have it:

1. Go to [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/)
2. Download and install Docker Desktop for your computer
3. Open Docker Desktop and wait for it to start (you'll see a green "Running" status)

---

## Setup (5 minutes)

### Step 1: Open Terminal

- **Mac**: Press `Cmd + Space`, type "Terminal", press Enter
- **Windows**: Press `Win + R`, type "cmd", press Enter

### Step 2: Download This Project

Copy and paste this command, then press Enter:

```bash
git clone https://github.com/dc-larsen/socket-firewall-workshop.git
```

Then go into the folder:

```bash
cd socket-firewall-workshop
```

### Step 3: Create Your Security Certificate

This creates a certificate that lets the firewall inspect package downloads. Copy and paste these commands one at a time:

```bash
mkdir -p certs
```

```bash
openssl genrsa -out certs/socketFirewallCa.key 2048
```

```bash
openssl req -x509 -new -nodes -key certs/socketFirewallCa.key -sha256 -days 365 -out certs/socketFirewallCa.crt -subj "/CN=Socket Security CA/O=Socket Security/C=US"
```

### Step 4: Add Your Socket API Key

Get your API key from [socket.dev/dashboard](https://socket.dev/dashboard), then run this command (replace `YOUR_KEY_HERE` with your actual key):

```bash
echo "SOCKET_API_KEY=YOUR_KEY_HERE" > .env.secrets
```

### Step 5: Start the Demo

```bash
docker compose up -d
```

Wait about 30 seconds for everything to start. You'll see messages about containers being created.

---

## Run the Demo

### Option A: Use the Demo Script

```bash
./demo.sh
```

This automatically tests both allowed and blocked packages.

### Option B: Test Manually

**Install a safe package (will succeed):**

```bash
docker exec sfw-node-client npm install lodash
```

**Install a malicious package (will be blocked):**

```bash
docker exec sfw-node-client npm install form-data@2.3.3
```

You should see: `403 Forbidden` - the firewall blocked it!

**Watch the firewall logs:**

```bash
docker logs socket-firewall
```

Look for `packageAllowed` and `packageBlocked` in the output.

---

## Example Packages to Test

| Command | What Happens |
|---------|--------------|
| `docker exec sfw-node-client npm install lodash` | Allowed (safe) |
| `docker exec sfw-node-client npm install form-data@2.3.3` | **Blocked** (malware) |
| `docker exec sfw-python-client pip install requests` | Allowed (safe) |
| `docker exec sfw-python-client pip install urllib3==1.16` | **Blocked** (vulnerable) |

---

## Stop the Demo

When you're done:

```bash
docker compose down
```

---

## Start It Again Later

```bash
cd socket-firewall-workshop
docker compose up -d
./demo.sh
```

---

## Troubleshooting

**"command not found: docker"**
- Make sure Docker Desktop is installed and running

**"command not found: git"**
- Mac: Run `xcode-select --install` and try again
- Windows: Download Git from [git-scm.com](https://git-scm.com/)

**Containers won't start**
- Make sure Docker Desktop shows "Running" (green icon)
- Try: `docker compose down` then `docker compose up -d`

**Packages aren't being blocked**
- Check your API key is correct in `.env.secrets`
- Make sure your Socket org has blocking policies configured

---

## How It Works

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Your install   │     │    Firewall     │     │    Package      │
│  command        │────▶│    (checks      │────▶│    Registry     │
│                 │     │    with Socket) │     │                 │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
                                 ▼
                           Socket API
                         (allow/block)
```

The demo runs 3 containers:
- **socket-firewall**: The proxy that checks packages
- **sfw-node-client**: Simulates npm installs
- **sfw-python-client**: Simulates pip installs

---

## Technical Reference

<details>
<summary>Click to expand advanced options</summary>

### Platform Support

The Dockerfile defaults to ARM64 (Apple Silicon Macs). For Intel Macs or Windows:

Edit `Dockerfile.sfw` and change:
```
sfw-linux-arm64
```
to:
```
sfw-linux-x86_64
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `SOCKET_API_KEY` | Your Socket API key |
| `SFW_DEBUG` | Enable debug logging |

### Files

```
├── docker-compose.yml    # Container configuration
├── Dockerfile.sfw        # Firewall image
├── .env.secrets          # Your API key (not shared)
├── certs/                # Security certificates
├── demo.sh               # Demo script
└── k8s/                  # Kubernetes configs (optional)
```

### Useful Commands

```bash
# View live logs
docker logs -f socket-firewall

# Shell into node client
docker exec -it sfw-node-client sh

# Shell into python client
docker exec -it sfw-python-client bash

# Rebuild after changes
docker compose up -d --build
```

</details>

---

## Resources

- [Socket Firewall Docs](https://github.com/SocketDev/firewall-release/wiki)
- [Socket Dashboard](https://socket.dev/dashboard)
