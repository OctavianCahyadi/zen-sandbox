# zen-sandbox

One shared local Docker stack for all your dev projects, plus a Claude Code plugin so
every Claude session knows what is running and how to use it.

Stop creating a new postgres/redis/rabbitmq stack for every project. Start the services
once, then give each project its own database / vhost / bucket on the shared servers.

```
┌──────────── docker project "sandbox" (network: sandbox) ────────────┐
│ sbx-postgres  sbx-redis  sbx-rabbitmq  sbx-rustfs  ...  sbx-<custom> │
└───────────────▲──────────────────▲────────────────────▲─────────────┘
          project-a db       project-b db         project-c vhost
```

## What's inside

| Part | Path | Purpose |
|---|---|---|
| Stack | `compose.yaml` | postgres, mysql, redis, rabbitmq, mongo, rustfs, mailpit (each behind a profile) |
| CLI | `bin/sbx` | start/stop/add/remove services, change ports, create per-project resources, print env |
| Claude skill | `skills/sandbox/SKILL.md` | tells Claude to reuse the sandbox and how to use `sbx` |
| Claude hook | `hooks/` | SessionStart: injects `sbx context` (running services, ports, resources) |
| Plugin manifest | `.claude-plugin/` | makes this repo installable as a Claude Code plugin marketplace |

State lives in `~/.sandbox/` (`.env`, `enabled`, `resources.tsv`, `services/*.yaml`).
Data lives in Docker volumes `sbx-<service>-data`, so updating the repo never touches data.

## Install

```bash
git clone https://github.com/OctavianCahyadi/zen-sandbox ~/.zen-sandbox
~/.zen-sandbox/install.sh          # symlinks sbx into ~/.local/bin
sbx up postgres redis              # start what you need
```

### Claude Code (plugin — recommended)

```bash
claude plugin marketplace add OctavianCahyadi/zen-sandbox     # or a local path: ~/.zen-sandbox
claude plugin install zen-sandbox@zenbytes
claude plugin list                                  # zen-sandbox@zenbytes should be "enabled"
```

Inside a Claude Code terminal session the same commands are `/plugin marketplace add ...`
and `/plugin install zen-sandbox@zenbytes`. Start a new session after installing.
A marketplace added from a local path is read in place, so edits to the repo apply
without reinstalling.

Every new session now gets a short "Local dev sandbox" block (what is running, ports,
creds, existing project resources), and the `sandbox` skill loads when you work on
infra or start a new project.

### Claude Code (without plugin)

```bash
sbx claude install     # writes a managed block into ~/.claude/CLAUDE.md
sbx claude uninstall   # removes it
```

## Usage

```bash
sbx list                          # catalog + enabled/running
sbx up postgres redis rabbitmq    # enable + start
sbx info                          # endpoints, creds, connection strings
sbx port                          # host ports, and who holds a busy one
sbx port rustfs auto auto         # port already in use? pick the next free ones
sbx project init myapp            # db+user / vhost / bucket "myapp" on running services
sbx env myapp >> .env             # env for an app running on the host
sbx env myapp --docker            # env for an app running in docker on network "sandbox"
sbx shell postgres myapp          # psql
sbx stop                          # stop everything (keeps enabled list)
sbx remove rabbitmq               # disable, keep data
sbx remove rabbitmq --purge       # disable + delete data
```

App in a container → join the shared network:

```yaml
services:
  app:
    build: .
    env_file: .env
    networks: [sandbox]
networks:
  sandbox:
    external: true
```

### Ports

Other stacks on the machine are never touched and never listed, but they can hold a
port the sandbox wants. `sbx port` shows every host port and names the owner of a busy
one (container, swarm service or local process):

```text
postgres   POSTGRES_PORT      5432
redis      REDIS_PORT         6379   IN USE by swarm service services_redis
rustfs     RUSTFS_PORT        9000   IN USE by container other-minio-1
rustfs     RUSTFS_UI_PORT     9001   IN USE by container other-minio-1
```

```bash
sbx port rustfs auto auto      # next free port for the main port and the UI port
sbx port rustfs 19000 19001    # or set them yourself
sbx port postgres 5433         # services with one port take one value
sbx up rustfs
```

The new port is saved in `~/.sandbox/.env`; a running service is restarted on it.
A failed `sbx up` prints the busy port, its owner and the fix. `sbx context` (the
session hook), `sbx info` and `sbx env` always print the real host ports, so Claude
never has to guess. Ports inside the `sandbox` network do not change (`rustfs:9000`,
`postgres:5432`, ...). `sbx port` covers built-in services; for a custom service edit
its yaml.

### Custom services

```bash
sbx new elasticsearch          # creates ~/.sandbox/services/elasticsearch.yaml from template
$EDITOR ~/.sandbox/services/elasticsearch.yaml
sbx compose config --quiet     # validate
sbx up elasticsearch
```

### Config

Edit `~/.sandbox/.env` for credentials, bind address and versions, then `sbx up`.
Change ports with `sbx port` (it writes the same file).
Defaults: user `sandbox`, password `sandbox123`, ports bound to `127.0.0.1`.

## Notes

- Works with Docker Desktop, OrbStack, colima, Linux Docker. Needs Docker Compose v2.20+.
- `sbx` is plain bash (3.2 compatible), no other dependencies.
- S3 storage is RustFS (`rustfs/rustfs:latest`), since MinIO no longer ships community
  images. Override with `RUSTFS_IMAGE=` in `~/.sandbox/.env`. Console: `http://localhost:9001/rustfs/console/`
  (use the UI port from `sbx info rustfs` if you changed it).
- If you run Portainer, the stack shows up as a "Limited" compose stack named `sandbox`.
