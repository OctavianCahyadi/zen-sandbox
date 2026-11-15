---
name: sandbox
description: Use for any local development that needs infrastructure (database, cache, queue, object storage, SMTP, or any other backing service) — starting a new project, wiring .env / application.yml / docker-compose, or adding, removing, inspecting, or resetting local services, or migrating / merging an existing project's own postgres, redis, rabbitmq, minio, etc. into the shared sandbox. Reuse the shared zen-sandbox stack via the sbx CLI instead of adding services to the project's own compose file.
---

# Local dev sandbox (zen-sandbox)

All local backing services run in ONE shared Docker Compose project named `sandbox`
on the Docker network `sandbox`. Projects connect to it; they do not run their own
copies of postgres, redis, rabbitmq, etc.

The session-start context already lists what is running. If it is missing or stale,
run `sbx context` (or `sbx list`).

## Rules

1. **Reuse first.** Before writing a docker-compose service for postgres / mysql /
   redis / rabbitmq / mongo / rustfs / mailpit, check `sbx list`. If it is in the
   catalog, use it (start it with `sbx up <svc>` if needed).
2. **One project = its own resources, not its own server.** Give each project its own
   database / vhost / bucket with `sbx project init <name>`. Never reuse another
   project's database.
3. **Destructive actions need the user's OK.** Ask before `sbx remove --purge`,
   `sbx db drop`, `sbx project drop`, `sbx delete`. `sbx stop` / `sbx remove`
   (without `--purge`) are safe — data stays in the `sbx-<svc>-data` volume.
4. **Missing service → add it to the sandbox,** not to the project:
   `sbx new <name>` → edit `~/.sandbox/services/<name>.yaml` → `sbx up <name>`.
5. Don't hardcode credentials from memory. Get them from `sbx info` / `sbx env`.
6. If `sbx` is not on PATH, use the CLI path printed in the session context, or run
   the repo's `install.sh`.

## New project workflow

```bash
sbx list                         # what exists, enabled, running
sbx up postgres redis            # start what the project needs (idempotent)
sbx project init myapp           # db+user myapp, vhost myapp, bucket myapp on running services
sbx env myapp >> .env            # app runs on the host (localhost ports)
sbx env myapp --docker           # app runs in a container on the `sandbox` network
```

App running in Docker → join the external network and use service hostnames
(`postgres:5432`, `redis:6379`, `rabbitmq:5672`, `mongo:27017`, `rustfs:9000`, `mailpit:1025`):

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

Spring Boot (`application-local.yml`) — prefer env vars from `sbx env`, which already
outputs `SPRING_DATASOURCE_*`, `SPRING_DATA_REDIS_*`, `SPRING_RABBITMQ_*`.

## Migrating an existing project

When the user asks to move / merge / migrate a project (or "the old projects") into the
sandbox, you do the whole job; the user only approves the cleanup at the end.
Migrate ONE project at a time and finish it before starting the next.

1. **Find it.** `sbx scan` lists infra containers and data volumes of other stacks
   (read-only). With no project named, show the list and ask which one to start with.
   A volume-only row means the stack was removed with `compose down` but its data is
   still there. If the folder column is `-`, find the project folder yourself (a compose
   file whose project name or folder name matches); ask the user if you cannot.
2. **Read the project.** Its compose file(s) and `.env`: which infra services it runs,
   images and versions, database names, users, buckets, and every place the app reads
   those values (env files, `application*.yml`, config code, CI files).
3. **Check it fits.** Compare versions with the sandbox (`sbx info`). `sbx import postgres`
   refuses a newer source version and any extension the sandbox image lacks (postgis,
   pgvector, timescale, ...). If it does not fit, tell the user and leave that service
   in the project; migrate the rest.
4. **Start the sandbox side.** `sbx up <services the project needs>`, then
   `sbx project init <name>`.
5. **Copy the data.** The source container must be running, so start only the OLD infra
   service from the project folder (`docker compose up -d <db-service>`), then:
   - Postgres: `sbx import postgres <old-container> <name> [--db <db>] [--user <user>]`.
     It compares table counts; read the log it names if errors are reported.
   - MinIO → RustFS: `sbx import bucket <old-container>` lists buckets, then
     `sbx import bucket <old-container> <bucket> [<target>]` for each one.
     The `minio/minio` image is gone from Docker Hub. If the old one cannot be pulled,
     start it with `pgsty/minio` on the same volume just to read the data.
   - MySQL / Mongo: no import command yet. Dump from the old container and restore into
     the sandbox one by hand (`mysqldump | mysql`, `mongodump --archive | mongorestore`).
   - Redis, Mailpit: do not copy. RabbitMQ: `sbx project init` already made the vhost;
     queues are re-declared by the app.
   The source is only read. Never delete or overwrite old data in this step.
6. **Rewire the project.** Remove the infra services (and their volumes, `depends_on`,
   healthcheck waits) from the project's compose file. If the app runs in Docker, join
   the external `sandbox` network (snippet above) and use `sbx env <name> --docker`;
   if it runs on the host use `sbx env <name>`. Map those values onto the variable names
   the project already uses — do not rename the project's variables. Keep app-only
   services (the app itself, workers, caddy, mosquitto, ...) as they are.
7. **Verify.** Stop the old infra containers, start the app, and prove it works on the
   sandbox: migrations/health check pass, a real read from the database, a file in the
   bucket. Run the project's tests if it has them.
8. **Report, then ask.** Tell the user what moved, what was left behind and why. Ask
   before removing old containers, and ask separately before deleting old volumes —
   they are the only backup. Do not commit the project's changes unless asked.

If any step fails, stop and report; the old stack still works because nothing in it
was changed.

## Command reference

| Need | Command |
|---|---|
| Catalog + state | `sbx list` |
| Start / enable | `sbx up <svc...>` (no args = all enabled) |
| Stop (keep enabled) | `sbx stop [svc...]` |
| Disable (keep data) | `sbx remove <svc>` |
| Disable + delete data | `sbx remove <svc> --purge` (ask first) |
| Endpoints + creds | `sbx info [svc]` |
| Show / change host ports | `sbx port`, `sbx port <svc> auto`, `sbx port <svc> <port> [ui-port]` |
| Container status | `sbx status` |
| Logs | `sbx logs <svc> [-f]` |
| SQL / CLI shell | `sbx shell postgres myapp`, `sbx shell redis` |
| Database | `sbx db create|drop|list <name> [--engine postgres|mysql|mongo]` |
| RabbitMQ vhost | `sbx vhost create|drop <name>` |
| RustFS bucket | `sbx bucket create|drop <name>` |
| Everything for a project | `sbx project init|drop <name>` |
| Env vars | `sbx env <name> [--docker]` |
| Resources created so far | `sbx resources` |
| Find old per-project stacks | `sbx scan` (read-only) |
| Copy old data in | `sbx import postgres <container> <name>`, `sbx import bucket <container> [<bucket>]` |
| Custom service | `sbx new <name>`, then `sbx up <name>`; `sbx delete <name>` |
| Raw compose | `sbx compose <args>` |

Built-in catalog: postgres, mysql, redis, rabbitmq, mongo, rustfs, mailpit.
Default credentials: `sandbox` / `sandbox123` (change in `~/.sandbox/.env`).
Ports bind to 127.0.0.1 by default. If `sbx up` fails because a port is already in use,
run `sbx port <svc> auto` (picks the next free port and saves it in `~/.sandbox/.env`),
then `sbx up <svc>` again. `sbx port` lists every port and names who holds a busy one
(container, swarm service or process). Do not stop the other program that owns the port.
Host ports can differ from the defaults: always take them from `sbx context`,
`sbx info` or `sbx env <name>`, never assume 5432 / 9000 / etc. Ports inside the
`sandbox` network never change.

## Custom service checklist

When writing `~/.sandbox/services/<name>.yaml` (template from `sbx new`):
- service key, `profiles: [<name>]`, and `container_name: sbx-<name>` must all match the file name
- `networks: [sandbox]`, label `sbx.managed: "true"`
- ports as `"${SBX_BIND:-127.0.0.1}:<host>:<container>"`, pick a host port that is free
- named volume `sbx-<name>-data` declared under top-level `volumes:`
- reuse `${SBX_USER}` / `${SBX_PASSWORD}` for credentials
- validate with `sbx compose config --quiet`, then `sbx up <name>`
