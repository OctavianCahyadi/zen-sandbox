# Contributing

Issues and pull requests are welcome.

## Ground rules

- `bin/sbx` is plain bash and must keep working on bash 3.2 (the macOS default).
  No associative arrays, no `mapfile`, no `${var,,}`.
- No dependencies beyond bash and Docker (Compose v2.20+).
- Commands that delete data must stay explicit (`--purge`, `drop`) and never be a default.
- Anything that reads another stack's data (`scan`, `import`) must only read it.

## Check your change

```bash
docker run --rm -v "$PWD:/mnt:ro" koalaman/shellcheck:stable -S warning bin/sbx install.sh hooks/session-start.sh tests/smoke.sh
```

`tests/smoke.sh` starts real containers and deletes the `sbx-*` test volumes when it
finishes, so it refuses to run on a machine that already has a sandbox. CI runs it on
every push. To run it locally without touching your own sandbox, use an isolated
Docker daemon:

```bash
docker run -d --privileged --name sbx-dind -v "$PWD:/repo:ro" docker:dind
docker exec sbx-dind sh -c 'apk add -q bash curl && bash /repo/tests/smoke.sh'
docker stop sbx-dind
```

## Adding a built-in service

1. Add the service to `compose.yaml` behind a profile with the same name, container
   name `sbx-<name>`, volume `sbx-<name>-data`, and a healthcheck.
2. Add it to `BUILTIN`, `svc_desc`, `svc_endpoint`, `port_vars` and the default
   `.env` block in `bin/sbx`.
3. Document it in `README.md` and `skills/sandbox/SKILL.md`.
4. Add a line to `CHANGELOG.md`.
