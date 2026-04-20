# Home Server

Docker Compose stack for my home server. Copy `.env.example` to `.env` and adjust values before starting.

```bash
cp .env.example .env
docker compose up -d
```

## Services

### Monitoring
| Service | Port | Description |
|---------|------|-------------|
| Dozzle | 9999 | Docker log viewer |
| WUD | 3001 | Image update tracker |
| Beszel (hub) | 8090 | Host + container metrics with history |
| Beszel (agent) | 45876 | Metrics agent (host network) |
| Uptime Kuma | 3011 | Service availability pings + alerts |

### Dashboard
| Service | Port | Description |
|---------|------|-------------|
| Traefik | 80 / 443 | Reverse proxy + TLS termination for all services |
| Homepage | internal | Service dashboard with live widgets (reachable at `https://home.lan`) |
| Docker Socket Proxy | internal | Read-only Docker API for Homepage auto-discovery |

### Hostnames (via Traefik + AdGuard DNS rewrite for `*.home.lan`)
`home.lan` · `plex.home.lan` · `tautulli.home.lan` · `radarr.home.lan` · `sonarr.home.lan` · `bazarr.home.lan` · `prowlarr.home.lan` · `qbit.home.lan` · `ha.home.lan` · `z2m.home.lan` · `adguard.home.lan` · `beszel.home.lan` · `kuma.home.lan` · `dozzle.home.lan` · `wud.home.lan` · `traefik.home.lan`

TLS by mkcert — install `rootCA.pem` from `/root/mkcert-ca/` on any client that needs the green padlock. Works over Tailscale via split-DNS for `.home.lan` → `192.168.68.253`.

### Media
| Service | Port | Description |
|---------|------|-------------|
| Plex | host | Media server |
| Tautulli | 8181 | Plex analytics |
| Radarr | 7878 | Movie manager |
| Sonarr | 8989 | TV show manager |
| Bazarr | 6767 | Subtitle manager |
| qBittorrent | 8088 | Torrent client |
| Prowlarr | 9696 | Indexer manager |
| FlareSolverr | 8191 | Cloudflare bypass proxy |

### Home Automation
| Service | Port | Description |
|---------|------|-------------|
| Home Assistant | host | Home automation platform |
| Mosquitto | 1883 / 9001 | MQTT broker |
| Zigbee2MQTT | host | Zigbee bridge |

### Network
| Service | Port | Description |
|---------|------|-------------|
| AdGuard Home | 53 / 3000 / 8080 | DNS-level ad blocking |
