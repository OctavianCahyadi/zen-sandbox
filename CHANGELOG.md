# Changelog

## 0.1.0 — 2026-11-16

First public release.

- Shared Docker Compose stack `sandbox`: postgres, mysql, redis, rabbitmq, mongo,
  rustfs (S3), mailpit, plus custom services.
- `sbx` CLI: start/stop/remove services, per-project database / vhost / bucket,
  `.env` output for host and Docker apps.
- `sbx port`: show and change host ports, pick a free one with `auto`, and name the
  container, swarm service or process that holds a busy port.
- Claude Code plugin: session-start context with running services and real ports,
  and the `sandbox` skill.
- Experimental: `sbx scan` and `sbx import` (postgres, MinIO bucket) to migrate
  old per-project stacks into the sandbox.
