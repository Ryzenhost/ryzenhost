# RYZENNC Panel

Made by ryzennc

## Quick Automated Setup (Recommended)

Run the automated management script:

```bash
bash install.sh
```

Menu options:

1. **Initialize Main Panel** – installs Node.js, Docker, PM2, dependencies, builds & starts on port 6767
2. **Initialize Dev Panel** – developer mode on port 3000
3. **Update & Auto-Repair**
4. **Create / Reset Owner**
5. **System & Service Status**
6. **Cloudflare & Domain** – attach a domain to the panel (see below)
7. **Uninstall RYZENNC Panel**
0. **Exit**

Shortcuts: `bash install.sh main`, `bash install.sh dev`, `bash install.sh cloudflare`

---

## Cloudflare & Domain

`bash install.sh` → **[6] Cloudflare & Domain**

| Option | What it does |
| --- | --- |
| **Tunnel + Domain** (recommended) | Creates a Cloudflare Tunnel, ingress rule and proxied CNAME for your hostname, then runs `cloudflared` as a service (systemd, or PM2 fallback). No open ports or public IP needed, HTTPS is automatic. |
| **Nginx + Cloudflare DNS** | Installs Nginx as a reverse proxy (WebSocket-ready) and creates a proxied `A` record to your VPS IP. Optionally sets the zone SSL mode to Flexible. |
| **Quick Tunnel** | Temporary `*.trycloudflare.com` link, no domain/account required. |
| **Status / Remove** | Shows domain, tunnel and HTTPS state; stops services and optionally deletes DNS record + tunnel. |

You need a domain already added to Cloudflare and an **API Token** (https://dash.cloudflare.com/profile/api-tokens) with:

- Account → Cloudflare Tunnel → Edit *(Tunnel mode)*
- Zone → DNS → Edit
- Zone → Zone → Read

The token is only used during setup and is never written to disk. Local state is kept in `.cloudflare.env` (git-ignored).

---

## GitHub Build

`.github/workflows/build.yml` runs on every push / PR to `main`, on tags `v*`, and manually (Actions → *Build ryzennc* → *Run workflow*):

- installs dependencies, runs `npm run build`, verifies `dist/server.cjs` + `dist/index.html`
- uploads `ryzennc-dist.tar.gz` as an artifact
- on tag `v*` → publishes a GitHub Release with the archive
- on push → builds & pushes the Docker image to `ghcr.io/<owner>/<repo>`

Release example:

```bash
git tag v3.0.1 && git push origin v3.0.1
```

---

## Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/Ryzenhost/ryzenhost.git
   cd ryzennc
   ```
2. Install dependencies: `npm install`
3. Build: `npm run build`
4. Create an admin user: `npm run createuser`
5. Start (port 6767): `npm run start`

## Development

```bash
npm run dev   # port 3000
```
