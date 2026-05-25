# NetProbe

A hands-on networking project. Nginx proxies traffic to PulseStack over HTTPS, and a diagnostic script (`netprobe.sh`) checks that DNS, ports, TLS, and HTTP are all healthy in one run.

---

## Architecture

```
Browser → https://pulsestack.local:443 → Nginx (TLS termination)
                                              ├── /metrics  → PulseStack Exporter (round-robin :8000/:8001)
                                              ├── /grafana  → Grafana (:3000)
                                              └── /health   → {"status":"ok"}

Local DNS:  /etc/hosts → pulsestack.local → 127.0.0.1
TLS:        mkcert-generated certificate (local CA)
```

---

## How It Works

| Component | Role |
|---|---|
| **Nginx** | TLS reverse proxy — terminates HTTPS, routes traffic, injects request headers |
| **mkcert** | Generates a locally-trusted TLS certificate for `pulsestack.local` |
| **Docker Compose** | Runs Nginx and Grafana as containers |
| **netprobe.sh** | Bash diagnostic script — DNS, ports, TLS, HTTP timing, open ports |

---

## Project Structure

```
NetProbe/
├── nginx/
│   ├── nginx.conf            # Reverse proxy config — upstream, TLS, location blocks, security headers
│   └── certs/                # mkcert-generated cert + key (gitignored)
├── captures/                 # tcpdump .pcap files (gitignored)
├── docker-compose.yml        # Runs Nginx + Grafana
├── netprobe.sh               # Network diagnostic script
├── Makefile                  # Shortcuts for common operations
└── README.md
```

---

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running
- [`mkcert`](https://github.com/FiloSottile/mkcert) installed (`brew install mkcert`)
- `dig`, `openssl`, `nc`, and `curl` available (pre-installed on macOS)
- Python 3.10+ (for PulseStack)

---

## Full Setup

NetProbe sits in front of PulseStack, so PulseStack must be running first.

### Step 1 — Start PulseStack

In the PulseStack directory:

```bash
cd ../PulseStack

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

python main.py
```

The agent exposes metrics at `http://localhost:8000/metrics`. Leave this terminal running.

### Step 2 — Add the local DNS entry

Back in the NetProbe directory, add `pulsestack.local` to your hosts file:

```bash
echo "127.0.0.1 pulsestack.local" | sudo tee -a /etc/hosts
```

Verify it resolves:

```bash
dscacheutil -q host -a name pulsestack.local
# Should return ip_address: 127.0.0.1
```

> **Note:** Use `dscacheutil` instead of `dig` to verify `/etc/hosts` entries on macOS. `dig` queries DNS servers directly and will not see hosts-file entries.

### Step 3 — Generate a local TLS certificate

```bash
mkcert -install
mkcert -key-file nginx/certs/pulsestack.key -cert-file nginx/certs/pulsestack.crt pulsestack.local
```

`mkcert -install` only needs to run once — it installs the local CA into your system trust store so your browser and `curl` trust the cert without `-k`.

### Step 4 — Start the proxy

```bash
make proxy-up
```

This starts Nginx (TLS on :443) and Grafana (:3000) via Docker Compose.

---

## Testing the Full Stack

Run through each check below in order. Everything should pass before moving on.

### 1. Health endpoint

```bash
curl https://pulsestack.local/health
```

Expected: `{"status":"ok"}` — confirms DNS, TLS, and Nginx are all working.

### 2. Metrics via the proxy

```bash
curl https://pulsestack.local/metrics | head -20
```

Expected: Prometheus-formatted metrics from PulseStack. If this returns a 502, PulseStack is not running on port 8000.

### 3. Security headers

```bash
curl -I https://pulsestack.local/health
```

Expected headers in the response:

```
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
Strict-Transport-Security: max-age=31536000
```

### 4. TLS certificate

```bash
make cert-check
```

Expected: `notAfter` date is in the future. If it is expired or missing, regenerate with `mkcert`.

### 5. Full diagnostic script

```bash
make netprobe
```

Expected output (green = healthy):

```
=== DNS Resolution ===
google.com -> 142.250.x.x
github.com -> 140.82.x.x
pulsestack.local -> 127.0.0.1

=== Port Connectivity ===
google.com:443 -> OK
github.com:443 -> OK
localhost:8000 -> OK

=== TLS Cert Expiry ===
...

=== HTTP Timing ===
...

=== Listening Ports ===
...
```

Any red `FAILED` lines indicate a broken DNS entry, closed port, or expired cert.

### 6. Grafana via the proxy

Open `https://pulsestack.local/grafana` in your browser. You should reach the Grafana login page served through Nginx over TLS.

---

## Running the Diagnostic Script

```bash
make netprobe
```

Or directly:

```bash
bash netprobe.sh
```

The script runs five checks and prints colour-coded results:

| Check | What it does |
|---|---|
| DNS Resolution | Resolves domains via `dscacheutil` (respects `/etc/hosts`) with `dig` as fallback |
| Port Connectivity | Tests host:port pairs with `nc -z` |
| TLS Cert Expiry | Reads `notAfter` from each HTTPS endpoint via `openssl` |
| HTTP Timing | Reports `time_total` for each URL via `curl -w` |
| Listening Ports | Lists all TCP ports in LISTEN state via `netstat` |

---

## Make Commands

| Command | What it does |
|---|---|
| `make proxy-up` | Start Nginx + Grafana via Docker Compose |
| `make proxy-down` | Stop and remove containers |
| `make netprobe` | Run the full diagnostic script |
| `make cert-check` | Print the TLS cert expiry date for `pulsestack.local` |

---

## Stopping

```bash
make proxy-down
```

---

## Troubleshooting

**`curl: (6) Could not resolve host: pulsestack.local`**
- The `/etc/hosts` entry is missing — re-run step 1 of setup

**`curl: (35) SSL handshake failed`**
- The mkcert CA is not installed — run `mkcert -install` and regenerate the cert
- Check the cert and key are in `nginx/certs/`

**Nginx container exits immediately**
- Run `docker compose logs nginx` to see the error
- Common causes:
  - `nginx/certs/` is empty or the filenames don't match `nginx.conf`
  - `nginx.conf` is missing the required `events {}` block or the `http {}` wrapper — all `upstream` and `server` blocks must be nested inside `http {}`
  - `host.docker.internal` not resolving inside the container — ensure `extra_hosts: host.docker.internal:host-gateway` is set in `docker-compose.yml`

**`/metrics` returns a 502**
- PulseStack is not running on port 8000 — start it first (`python main.py` in the PulseStack directory)

**Check what the cert says**
```bash
make cert-check
```
