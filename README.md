<div align="center">

# tModLoader Server

<p><i>Run a persistent Terraria tModLoader 1.4.4 server in Docker, including ARM64 hosts.</i></p>

<p>
  <a href="https://github.com/tModLoader/tModLoader">tModLoader 1.4.4</a> ·
  <a href="https://www.terraria.org/">Terraria</a> ·
  <a href="https://www.docker.com/">Docker</a>
</p>

</div>

## What is this?

This repository is an ARM-focused fork of [hexlo/terraria-tmodloader-server](https://github.com/hexlo/terraria-tmodloader-server). It packages a dedicated [tModLoader](https://github.com/tModLoader/tModLoader) server for Docker and keeps the server data in a bind-mounted directory so worlds, mods, and configuration survive rebuilds.

The image is based on an ARM64 SteamCMD image and uses its FEX/Ubuntu runtime to provide the compatibility layer required by the x86 tModLoader server binaries. The image can be built for ARM64 hosts such as Ampere and other aarch64 systems.

## Requirements

### Host

- Docker Engine
- Docker Compose v2 (`docker compose`)
- An ARM64/aarch64 host for the ARM build

### Client

- Terraria 1.4.4 or newer
- tModLoader 1.4.4 or newer
- The same mods enabled as the server

## Quick start

Clone the repository and create a Compose file from the example:

```sh
git clone https://github.com/forcebyte/terraria-tmodloader-server.git
cd terraria-tmodloader-server
cp docker-compose-example.yml docker-compose.yml
```

Edit `docker-compose.yml`, then build and start the server:

```sh
docker compose build
docker compose up -d
```

The example publishes host port `7785` to the server's container port `7777`. Change the host-side port if needed.

The server data is stored in `./tModLoader` and mounted at `/home/tml/.local/share/Terraria/tModLoader` in the container. The container runs as the UID and GID supplied through the Docker build arguments, which should match the owner of the mounted directory.

### Published image

A rolling image is published to the [GitHub Container Registry package](https://github.com/Forcebyte/terraria-tmodloader-server/pkgs/container/terraria-tmodloader-server). Use the published image when you do not want to build locally:

```yaml
image: ghcr.io/forcebyte/terraria-tmodloader-server:latest
```

The published image currently follows a rolling release model. If stable semantic version tags are needed, open a [GitHub issue](https://github.com/Forcebyte/terraria-tmodloader-server/issues) to request semantic versioning support.

### ARM64 build

On an ARM64 host, the default build is sufficient:

```sh
docker compose build --no-cache
```

To build explicitly for ARM64 with Buildx:

```sh
docker buildx build --platform linux/arm64 -t terraria-tmodloader-server:arm64 .
```

## Docker Compose configuration

The smallest useful configuration points Docker at the persistent data directory and supplies a world-generation configuration:

```yaml
services:
  tml:
    container_name: tml
    restart: unless-stopped
    build:
      context: .
      args:
        UID: 1000
        GID: 1000
    tty: true
    stdin_open: true
    ports:
      - "7785:7777"
    volumes:
      - ./tModLoader:/home/tml/.local/share/Terraria/tModLoader
    environment:
      - AUTOCREATE=1
      - WORLDNAME=tmlWorld.wld
      - DIFFICULTY=1
      - PASSWORD=change-me
      - MOTD=Welcome to my tModLoader server
```

For Kubernetes or k3s, run the container with the same numeric identity used during the image build and make the mounted volume group-writable:

```yaml
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  fsGroupChangePolicy: OnRootMismatch
```

Without an appropriate `fsGroup` or init-container ownership fix, a PVC initialized as root can prevent tModLoader from writing `Mods/enabled.json`.

### Kubernetes example

A complete Calamity deployment is available in [`examples/kubernetes/terraria-calamity`](examples/kubernetes/terraria-calamity). It includes:

- A 20 GiB `PersistentVolumeClaim` for worlds and server data
- A `ConfigMap` for `Mods/install.txt` and `Mods/enabled.json`
- An init container that copies the mod configuration and fixes volume ownership
- A non-root tModLoader Deployment and internal TCP Service
- A NetworkPolicy allowing Terraria traffic and required outbound access

Before applying it, update the image reference and replace the placeholder password in [`secret.yaml`](examples/kubernetes/terraria-calamity/secret.yaml). The example assumes a cluster StorageClass can provision a `ReadWriteOnce` volume:

```sh
kubectl apply -k examples/kubernetes/terraria-calamity
```

The included `ingressroute-tcp.yaml` is optional and is not enabled by default. If Traefik TCP passthrough is installed, add it to the Kustomization resources and configure the `terraria` entrypoint on your Traefik instance.

### Regenerate a world

The Kubernetes example starts in persistent-world mode. To deliberately discard `Calamity.wld` and generate a fresh large expert world, run the following from the repository root:

```sh
NS=terraria-calamity
DEPLOY=terraria-calamity

# Stop the server before touching the PVC.
kubectl scale deployment "$DEPLOY" -n "$NS" --replicas=0
kubectl wait --for=delete pod -l app=terraria-calamity -n "$NS" --timeout=180s

# Permanently delete the current world files from the PVC.
kubectl run terraria-world-cleaner -n "$NS" \
  --image=alpine:3.20 \
  --restart=Never \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "cleaner",
        "image": "alpine:3.20",
        "command": ["sh", "-c", "rm -f /data/Worlds/Calamity.wld /data/Worlds/Calamity.twld"],
        "volumeMounts": [{"name": "data", "mountPath": "/data"}]
      }],
      "volumes": [{
        "name": "data",
        "persistentVolumeClaim": {"claimName": "terraria-calamity-data"}
      }]
    }
  }'

kubectl wait --for=jsonpath='{.status.phase}'=Succeeded \
  pod/terraria-world-cleaner -n "$NS" --timeout=120s
kubectl delete pod terraria-world-cleaner -n "$NS"

# Enable world generation and start the server.
kubectl set env deployment/"$DEPLOY" -n "$NS" \
  WORLD- AUTOCREATE=3 WORLDNAME=Calamity.wld DIFFICULTY=1
kubectl scale deployment "$DEPLOY" -n "$NS" --replicas=1
kubectl rollout status deployment/"$DEPLOY" -n "$NS"
```

Wait until the server has finished generating the world, then switch back to persistent-world mode:

```sh
kubectl scale deployment "$DEPLOY" -n "$NS" --replicas=0
kubectl wait --for=delete pod -l app=terraria-calamity -n "$NS" --timeout=180s

kubectl set env deployment/"$DEPLOY" -n "$NS" \
  WORLD=/home/tml/.local/share/Terraria/tModLoader/Worlds/Calamity.wld \
  AUTOCREATE- WORLDNAME- DIFFICULTY-
kubectl scale deployment "$DEPLOY" -n "$NS" --replicas=1
kubectl rollout status deployment/"$DEPLOY" -n "$NS"
```

The cleaner command permanently deletes the existing `.wld` and `.twld` files. Confirm the PVC and filenames before running it, and take a backup if the old world may be needed later.

## Worlds

### Create a world automatically

Set these environment variables in `docker-compose.yml`:

```yaml
environment:
  - AUTOCREATE=1
  - WORLDNAME=tmlWorld.wld
  - DIFFICULTY=1
```

`DIFFICULTY` accepts `0` for normal, `1` for expert, `2` for master, and `3` for journey. Set `SEED` to choose a specific world seed.

### Use an existing world

Set `WORLD` to the full path inside the container:

```yaml
environment:
  - WORLD=/home/tml/.local/share/Terraria/tModLoader/Worlds/tmlWorld.wld
  - PASSWORD=change-me
```

Worlds consist of matching `.wld` and `.twld` files. Place both files in `tModLoader/Worlds` before starting the container.

### Create a world interactively

Remove the automatic world variables, start the container, and use the included `inject` helper:

```sh
docker compose up -d
docker exec tml inject "help"
```

Follow the server prompts. The world is saved in the mounted `Worlds` directory and can be selected later using `WORLD`.

## Mods

Mods are managed in `tModLoader/Mods`:

- `install.txt` contains one Steam Workshop ID per line.
- `enabled.json` contains the exact mod names to enable.

Example `install.txt`:

```text
2824688072
2824688266
2909886416
```

Example `enabled.json`:

```json
[
  "CalamityMod",
  "CalamityModMusic",
  "BossChecklist"
]
```

Mod names are case-sensitive and must match the names provided by tModLoader. The server and every client must use compatible versions of the enabled mods.

## Environment variables

Variable names are case-sensitive.

| Variable | Default | Description |
| --- | --- | --- |
| `WORLD` | empty | Full path to an existing world inside the container. |
| `AUTOCREATE` | `1` | World size when creating a world: `1` small, `2` medium, `3` large. |
| `SEED` | empty | Seed used with automatic world creation. |
| `WORLDNAME` | `tmlWorld.wld` | World filename used with automatic creation. |
| `DIFFICULTY` | `1` | `0` normal, `1` expert, `2` master, `3` journey. |
| `MAXPLAYERS` | `16` | Maximum number of connected players. |
| `PORT` | `7777` | Internal server port. Keep this aligned with the container port mapping. |
| `PASSWORD` | empty | Server password. |
| `MOTD` | empty | Message shown when players join. |
| `WORLDPATH` | `/home/tml/.local/share/Terraria/tModLoader/Worlds/` | Directory for world files. |
| `BANLIST` | `banlist.txt` | Ban list path. |
| `SECURE` | `0` | Set to `1` to prevent cheats. |
| `LANGUAGE` | `en/US` | Server language code. |
| `UPNP` | `1` | Enable or disable UPnP. |
| `NPCSTREAM` | `1` | NPC stream setting; higher values reduce skipping at the cost of bandwidth. |
| `PRIORITY` | empty | Server process priority. |
| `USE_CONFIG_FILE` | unset | Set to `1` to use the mounted `serverconfig.txt` instead of generated settings. |

> [!IMPORTANT]
> The generated configuration is written to `tModLoader/serverconfig.txt` on startup. If `WORLD` is empty, the server creates or selects a world using `AUTOCREATE`, `WORLDNAME`, `DIFFICULTY`, and `SEED`.

## Server commands

Send commands to a running server without attaching to its console:

```sh
docker exec tml inject "say Hello everyone!"
docker exec tml inject "save"
docker exec tml inject "playing"
```

Useful commands include `help`, `playing`, `save`, `kick <player>`, `ban <player>`, `password <value>`, `motd <message>`, `time`, and `exit`.

## Updating

Rebuild the image to update the tModLoader installation and installed mods:

```sh
docker compose build --no-cache
docker compose up -d
```

The `tModLoader` directory is mounted separately, so your worlds and server data remain outside the image.

## Project layout

```text
.
├── Dockerfile                    # ARM64-compatible server image
├── docker-compose-example.yml    # Example deployment
├── manage-tModLoaderServer.sh    # tModLoader installation and server utility
├── examples/                     # Kubernetes deployment examples
└── tModLoader/
    ├── Mods/                     # Mod installation and enablement files
    ├── Scripts/                  # Container startup and configuration scripts
    └── Worlds/                   # Persistent world files
```

## Credits

This project is based on [hexlo/terraria-tmodloader-server](https://github.com/hexlo/terraria-tmodloader-server), with ARM64 and extended Ubuntu compatibility work for ARM-based deployments.
