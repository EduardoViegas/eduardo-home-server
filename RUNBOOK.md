# Disaster Recovery Runbook

> *"Nihil accidere bono viro mali potest."*
> — Seneca, *De Providentia*
> *"Nothing evil can happen to a good man."* The Stoic doesn't dodge misfortune — he rehearses it. A backup you haven't restored is hope, not a plan. Run the drill.

---

## Scope

This runbook assumes the **SSD has failed** (or the OS is unbootable) but the **two HDDs in the MergerFS pool survived**. That is the exact disaster the nightly `restic` job protects against: the `/docker/appdata` backup lives on the HDD pool, and so does the restic password.

If the HDDs *also* died (fire, theft, double-disk failure) — restic doesn't save you. Offsite backup was deliberately skipped. You'd be rebuilding media libraries and Home Assistant from scratch.

Target recovery time: **~2 hours** to a running stack, assuming hardware is replaced.

---

## Hardware / host inventory (as of 2026-04-17)

| Item | Value |
|---|---|
| OS | Ubuntu 22.04 (jammy), kernel 5.15.0-174, x86_64 |
| Hostname | `eduardo-ubuntu-server` |
| Docker | 20.10.17 (build 100c701) |
| docker-compose-plugin | 2.40.3 (required for `include:` directive — do NOT install older) |
| nvidia-container-toolkit | 1.17.5-1 (Plex GPU transcoding) |
| mergerfs | 2.33.3-1 |
| User/UID | `eduardoviegas` / 1000:1000 |
| Timezone | `America/Sao_Paulo` |

### Drive layout

| Mount | Device | UUID | FS |
|---|---|---|---|
| `/` | LVM (`ubuntu-vg/ubuntu-lv`) | `LVM-VREh2GJdfylzUqBmP6d8dZRgg7kVm7hcudsHLqH1Z4FfflcQqFSUUJA8za6Mdv9k` | ext4 |
| `/boot` | — | `4fa16b86-e31e-4584-a695-2484d43e6411` | ext4 |
| `/boot/efi` | — | `1077-8754` | vfat |
| `/mnt/media1` | 3.6T HDD | `ac30f02a-1662-4399-a7d2-a4efcb935864` | ext4 |
| `/mnt/media2` | 3.6T HDD | `481eeb06-17b2-4199-af89-2bdd093a3c85` | ext4 |
| `/mnt/storage` | mergerfs of `/mnt/media*` | — | fuse.mergerfs |
| swap | `/swap.img` | — | — |

---

## Recovery — step by step

### Step 0: Physical

1. Replace the failed SSD.
2. Leave the two 3.6T HDDs **untouched**. Do not reformat. Do not let the installer touch them.
3. Boot the Ubuntu 22.04 Server installer from USB.

### Step 1: Fresh Ubuntu install

- Install target: the new SSD **only**. At the disk step, select "Custom storage layout" and leave both 3.6T HDDs unmounted.
- Create user `eduardoviegas` (UID 1000, GID 1000 — the installer does this by default for the first user).
- Enable SSH server during install.
- Set hostname: `eduardo-ubuntu-server`.
- Reboot, remove USB, log in over SSH.

### Step 2: Base system

```bash
sudo apt update && sudo apt upgrade -y
sudo timedatectl set-timezone America/Sao_Paulo
sudo apt install -y git curl ca-certificates gnupg lsb-release
```

Restore SSH keys if you had any — `~/.ssh/authorized_keys` is *not* in restic (it's on the SSD). If you don't have a separate backup, re-add public keys manually from the laptop/desktop that needs access.

### Step 3: Install Docker + compose plugin

Official APT repo (compose-plugin 2.40.3 or newer is **required** for the `include:` directive used by this stack):

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker   # or log out & back in

docker --version             # expect >= 20.10.17
docker compose version       # expect >= 2.40.3
```

### Step 4: Docker daemon config (log rotation + live-restore)

```bash
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  }
}
EOF
sudo systemctl restart docker
```

(The `nvidia` runtime stanza is added again in step 5 — merging now avoids a second restart.)

### Step 5: NVIDIA container toolkit (Plex GPU)

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
sudo apt install -y nvidia-driver-550 nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

nvidia-smi                                          # confirm GPU visible to host
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi  # visible to containers
```

### Step 6: MergerFS + mount HDDs

```bash
sudo apt install -y mergerfs

# Create mount points
sudo mkdir -p /mnt/media1 /mnt/media2 /mnt/storage

# Append to /etc/fstab — EXACT lines, UUIDs must match the physical drives:
sudo tee -a /etc/fstab > /dev/null <<'EOF'

# --- HDD pool (restored from original server) ---
UUID=ac30f02a-1662-4399-a7d2-a4efcb935864  /mnt/media1  ext4  defaults,nofail,x-systemd.device-timeout=30  0  2
UUID=481eeb06-17b2-4199-af89-2bdd093a3c85  /mnt/media2  ext4  defaults,nofail,x-systemd.device-timeout=30  0  2
/mnt/media*  /mnt/storage  fuse.mergerfs  defaults,allow_other,nonempty,use_ino,moveonenospc=true,dropcacheonclose=true,category.create=mspmfs,fsname=mergerfs,nofail,x-systemd.automount  0  0
EOF

sudo systemctl daemon-reload
sudo mount -a

# Verify
df -h /mnt/media1 /mnt/media2 /mnt/storage
ls /mnt/storage/data/media   # should show movies/ series/ from original server
ls /mnt/storage/backups      # should show restic-appdata/ — this is how we recover
```

**STOP and verify** you can `ls /mnt/storage/backups/restic-appdata` before proceeding. If that directory is missing, the HDDs are not the original pool — do not continue.

### Step 7: Clone the stack repo

```bash
cd ~
git clone https://github.com/EduardoViegas/eduardo-home-server.git docker-compose
cd docker-compose
cp .env.example .env
# .env should already contain correct values — verify:
cat .env
# PUID=1000
# PGID=1000
# TZ=America/Sao_Paulo
# PORT=8191
```

If `.env` needs secrets (none currently — just the four above), re-add them now.

### Step 8: Restore `/docker/appdata` from restic

Password is stored **on the HDD pool** so you don't need to remember it. Fallback password (also in your password manager):
**`c8uw8NkkDt7hG119Ckm7X6S7+xcIWQMi`** — rotate after recovery.

```bash
sudo apt install -y restic
sudo mkdir -p /docker
sudo chown $USER:$USER /docker

# Verify repo is readable
sudo restic -r /mnt/storage/backups/restic-appdata \
  --password-file /mnt/storage/backups/.restic-password \
  snapshots

# Restore latest snapshot to /
sudo restic -r /mnt/storage/backups/restic-appdata \
  --password-file /mnt/storage/backups/.restic-password \
  restore latest --target /

# Verify — /docker/appdata should now contain 16 service directories
ls /docker/appdata
du -sh /docker/appdata   # ~6-8 GB expected
```

If the password file on the HDD is lost/corrupt, use the fallback password above:
`sudo restic -r /mnt/storage/backups/restic-appdata restore latest --target /` and type the password.

### Step 9: Bring up the stack

```bash
cd ~/docker-compose
docker compose pull          # pulls the exact digests pinned in compose files
docker compose up -d
docker compose ps            # expect 16 containers, all "Up" or "healthy"
```

Watch logs for any container that fails to start:
```bash
docker compose logs -f <service-name>
```

### Step 10: Reinstall the restic backup timer

The backup script and systemd units are NOT in restic (they live under `/usr/local/bin` and `/etc/systemd/system`, not `/docker/appdata`). Recreate them:

```bash
# 1. Backup script
sudo tee /usr/local/bin/restic-backup-appdata.sh > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
export RESTIC_REPOSITORY=/mnt/storage/backups/restic-appdata
export RESTIC_PASSWORD_FILE=/mnt/storage/backups/.restic-password

restic backup \
  --exclude '/docker/appdata/plex/Library/Application Support/Plex Media Server/Cache' \
  --exclude '/docker/appdata/plex/Library/Application Support/Plex Media Server/Logs' \
  --exclude '/docker/appdata/plex/Library/Application Support/Plex Media Server/Crash Reports' \
  --exclude '/docker/appdata/plex/Library/Application Support/Plex Media Server/Diagnostics' \
  --tag appdata \
  /docker/appdata

restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --tag appdata --prune
EOF
sudo chmod +x /usr/local/bin/restic-backup-appdata.sh

# 2. systemd service
sudo tee /etc/systemd/system/restic-backup-appdata.service > /dev/null <<'EOF'
[Unit]
Description=Restic backup of /docker/appdata
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/restic-backup-appdata.sh
Nice=10
IOSchedulingClass=idle
EOF

# 3. systemd timer
sudo tee /etc/systemd/system/restic-backup-appdata.timer > /dev/null <<'EOF'
[Unit]
Description=Nightly restic backup of /docker/appdata

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now restic-backup-appdata.timer
systemctl list-timers restic-backup-appdata.timer   # verify "Next" shows tomorrow 03:00
```

---

## Per-service verification checklist

After `docker compose up -d`, walk through each service. Order matters: network → automation → media.

### AdGuard Home (`:3000` admin, `:53` DNS)
- [ ] Admin UI loads at `http://<server-ip>:3000` (or your Heimdall tile)
- [ ] `dig @<server-ip> google.com` resolves
- [ ] Router still points DNS to server IP (check router config, not the server)

### Home Assistant (host network, `:8123`)
- [ ] UI loads, login works
- [ ] Zigbee2MQTT integration shows as connected
- [ ] Automations list populated (check **Settings → Automations**)
- [ ] Re-pair USB serial adapter if needed: `ls /dev/ttyUSB0` — confirm device exists, restart HA container if not detected
- [ ] Rotate long-lived access tokens (Profile → Security) — old ones are in the backup

### Mosquitto (`:1883`)
- [ ] `docker logs mosquitto` shows no auth errors
- [ ] Z2M connects (see Z2M check below)

### Zigbee2MQTT (host network, `:8081` UI)
- [ ] UI loads
- [ ] Devices list populated; most should reconnect within 2 min (coordinator backup handles this automatically since v2.0)
- [ ] If devices don't rejoin: check `/dev/ttyUSB0` is mapped, restart container

### Plex (host network, `:32400`)
- [ ] UI loads at `http://<server-ip>:32400/web`
- [ ] Server shows as "claimed" — if not, re-claim via plex.tv/claim
- [ ] Libraries visible (movies / series)
- [ ] Hardware transcoding works: start a transcode, check `nvidia-smi` shows Plex process
- [ ] Router port-forward for remote access: verify 32400 still forwarded
- [ ] **Rotate Plex token** on plex.tv/account/security — the old one is in the backup

### Tautulli (`:8181`), Overseerr (`:5055`)
- [ ] UIs load
- [ ] Both show Plex as connected

### Sonarr (`:8989`), Radarr (`:7878`), Bazarr (`:6767`), Prowlarr (`:9696`)
- [ ] UIs load
- [ ] Indexers show green in Prowlarr → sync to Sonarr/Radarr
- [ ] Download client (qBit) shows green
- [ ] Existing queue resumes

### qBittorrent (`:8088` WebUI, `:6881` peer)
- [ ] UI loads
- [ ] Existing torrents resume
- [ ] **Rotate WebUI password** (old is in backup)
- [ ] Router port-forward 6881 still present

### FlareSolverr (`:8191`)
- [ ] `curl http://localhost:8191/` returns JSON status

### Heimdall (`:80` / `:443`)
- [ ] Dashboard loads, tiles reach their services

### Glances / Dozzle / WUD (monitoring)
- [ ] All three UIs load
- [ ] WUD dashboard shows all pinned containers with current digests

---

## Secret rotation (post-recovery)

Anything in `/docker/appdata` was in the backup. Assume the backup is compromised if the drives were stolen. Rotate:

- Plex token (`plex.tv/account/security`)
- Home Assistant long-lived access tokens (Profile → Security → Long-lived)
- qBittorrent WebUI password
- Mosquitto password file (`/docker/appdata/mosquitto/passwd`)
- AdGuard admin password
- Any API keys inside Sonarr / Radarr / Bazarr / Prowlarr (Settings → General → API Key → Reset)
- Overseerr API key

Restic password itself (`/mnt/storage/backups/.restic-password`) — rotate with `restic -r ... key passwd`, then update the password file and your password manager entry.

---

## Drill cadence

**A backup you haven't restored is hope, not a plan.** Run a partial restore drill monthly:

```bash
sudo restic -r /mnt/storage/backups/restic-appdata \
  --password-file /mnt/storage/backups/.restic-password \
  restore latest --target /tmp/restic-drill \
  --include /docker/appdata/homeassistant/configuration.yaml

diff /docker/appdata/homeassistant/configuration.yaml \
     /tmp/restic-drill/docker/appdata/homeassistant/configuration.yaml
# Should be empty (file matches current state — backup is intact)

sudo rm -rf /tmp/restic-drill
```

Run a **full** dry-run drill every 6 months to validate this runbook end-to-end. Set a calendar reminder.

---

## Things *not* covered by this runbook

- **Router config** — DHCP reservations, port forwards, DNS pointing to server. Take a screenshot of your router admin panel and store it with this repo.
- **Physical HDD replacement** — if one of the two 3.6T drives dies, the MergerFS pool degrades but doesn't lose data (each drive holds half the files). Replace the drive, format ext4, re-add to pool. Media libraries on the dead drive are gone — re-download via *arr.
- **SSD + both HDDs lost** — restic isn't enough. You'd rebuild media via *arr, re-pair Zigbee devices, re-configure HA from scratch. Consider adding offsite backup (B2/S3) before worrying about this scenario.
- **`~/.ssh/authorized_keys`** — lives on the SSD, NOT in restic. Keep a copy elsewhere.
- **Router / switch / AP configs** — out of scope.

---

*Last updated: 2026-04-17. Validate against reality every 6 months or after major changes.*
