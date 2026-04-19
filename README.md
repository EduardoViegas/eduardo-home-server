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
| Heimdall | 80 / 443 | Application dashboard |

### Media
| Service | Port | Description |
|---------|------|-------------|
| Plex | host | Media server |
| Tautulli | 8181 | Plex analytics |
| Overseerr | 5055 | Media request manager |
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
