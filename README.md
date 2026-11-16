# zen-sandbox

[![ci](https://github.com/OctavianCahyadi/zen-sandbox/actions/workflows/ci.yml/badge.svg)](https://github.com/OctavianCahyadi/zen-sandbox/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

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

Needs bash, Docker and Docker Compose v2.20+.

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

### Update

```bash
git -C ~/.zen-sandbox pull                     # the sbx CLI and compose file
claude plugin marketplace update zenbytes      # refresh the plugin catalog
claude plugin update zen-sandbox@zenbytes      # pull the new plugin version
```

Start a new Claude Code session afterwards. Updates are not automatic unless you turn
on auto-update for the `zenbytes` marketplace (`/plugin` → Marketplaces in a terminal
session). A marketplace added from a local path needs only the `git pull`. Your data
and `~/.sandbox` are not touched by an update.

### Uninstall

```bash
sbx remove <service...>            # stop + disable; add --purge to also delete its data volume
claude plugin uninstall zen-sandbox@zenbytes
claude plugin marketplace remove zenbytes
sbx claude uninstall               # only if you used `sbx claude install`
```

Then delete the `~/.local/bin/sbx` symlink, the `~/.sandbox` folder and the cloned repo.
Data volumes (`sbx-<service>-data`) stay until you remove them with `--purge` or
`docker volume rm`.

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

### Migrate old projects (experimental)

Already have projects that each run their own postgres / redis / minio? Tell Claude
"migrate this project to the sandbox" and it follows the playbook in the skill:
find the old stack, copy the data, rewire the project's compose and `.env`, test,
and ask you before any old container or volume is removed.

```bash
sbx scan                                        # old infra containers and data volumes (read-only)
sbx import postgres myapp-db-1 myapp            # dump old container -> sandbox database "myapp"
sbx import bucket myapp-minio-1                 # list buckets in an old MinIO
sbx import bucket myapp-minio-1 uploads myapp   # copy bucket "uploads" -> RustFS bucket "myapp"
```

The source is only read, so the old stack keeps working if a migration fails.
`import postgres` refuses a newer source version, a non-empty target, and extensions
the sandbox image does not have, and compares table counts after the copy. Bucket
copies run through a throwaway `rclone/rclone` container. MySQL and Mongo have no
import command yet. This part is new: keep the old volumes until you have checked
the migrated project yourself.

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

- Tested on macOS with Docker Desktop and on Linux (CI). It should also work with
  OrbStack and colima, but those are not tested.
- `sbx` is plain bash (3.2 compatible), no other dependencies.
- S3 storage is RustFS (pinned to `rustfs/rustfs:1.0.5`), since MinIO no longer ships
  community images. Override with `RUSTFS_IMAGE=` in `~/.sandbox/.env`. Console:
  `http://localhost:9001/rustfs/console/` (use the UI port from `sbx info rustfs` if you
  changed it).
- Image versions are pinned and can be changed in `~/.sandbox/.env`: `POSTGRES_VERSION`,
  `MYSQL_VERSION`, `REDIS_VERSION`, `RABBITMQ_VERSION`, `MONGO_VERSION`, `MAILPIT_VERSION`,
  `RUSTFS_IMAGE`.
- If you run Portainer, the stack shows up as a "Limited" compose stack named `sandbox`.

## Security

This is a tool for local development only. The default login (`sandbox` / `sandbox123`)
is public, and every project shares the same servers. Ports bind to `127.0.0.1` by
default; do not set `SBX_BIND=0.0.0.0` on an untrusted network, and never use this
stack for production or for real customer data.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)
