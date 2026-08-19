# Implementation Plan

## Repository Purpose

- This repository is a repeatable FastAPI backend baseline generator and manual
  deployment runbook.
- A fresh clone should be able to run the shell scripts in order and reach a
  working backend on the internal development server and, after verification,
  the production-like `aws-demo` target.
- The initial app skeleton is intentionally small. Its baseline endpoints and
  content snippet table prove that FastAPI, environment configuration, async
  SQLAlchemy, Alembic, PostgreSQL, Docker networking, and deployment scripts are
  wired correctly.
- After this baseline works, users should add their own domain schemas,
  migrations, services, and API routes.

## Deployment Model

- Manage two Docker containers from this repository:
  - FastAPI/Uvicorn application container.
  - PostgreSQL database container.
- Keep their lifecycles separate.
- The application container is expected to change frequently.
- The PostgreSQL container is expected to be created rarely and preserved across
  application redeploys.
- Maintain target-specific deployment scripts for:
  - `aws-demo`
  - `dev-demo`
- Prefer explicit script names or target wrappers so the deployment destination
  is visible before execution.

## Local Build Clone

- Docker images are built from a separate local clone, not from this primary
  working tree.
- The local build clone root is `J:\deploy_remote_repo`.
- Shell scripts running from WSL should refer to that path as
  `/mnt/j/deploy_remote_repo`.
- The build clone root is user-local configuration. Store overrides in
  `scripts/env/dev-demo.env`, `scripts/env/aws-demo.env`, or the corresponding
  example-derived local env files:
  - `BUILD_CLONE_ROOT_WINDOWS=J:\\deploy_remote_repo`
  - `BUILD_CLONE_ROOT_WSL=/mnt/j/deploy_remote_repo`
- App deployment scripts may create, update, or reuse a repository clone under
  that build root.
- The build clone should use `git clone` for first setup and `git pull` or an
  equivalent explicit update for later builds.
- The build clone is for image creation and packaging only; runtime env files
  and credentials must not be copied into it.

## Manual Execution Order

- Check local and remote prerequisites before running setup:
  - `scripts/check-prereqs.sh`
- Each script should print the next script to run when it completes
  successfully, so a new operator can follow the sequence without reopening
  this plan after every step.
- Run local bootstrap scripts first when setting up a working clone:
  - `scripts/bootstrap/setup-local-venv.sh`
  - `scripts/bootstrap/create-app-skeleton.sh`
- Local bootstrap prepares source files and Python tooling only. It does not
  require or create a local database.
- Commit and push generated baseline files before building an image from the
  clean clone. The bootstrap scripts print this reminder, and
  `scripts/build/build-image-tar.sh` refuses to run with uncommitted or
  unpushed source changes.
- Prepare target environment files before creating PostgreSQL:
  - `scripts/dev-demo/setup-env.sh`
  - `scripts/aws-demo/setup-env.sh`
- Deploy or start PostgreSQL after target env files exist:
  - `scripts/dev-demo/deploy-postgres.sh`
  - `scripts/aws-demo/deploy-postgres.sh`
- Run migrations and seed data against `dev-demo` after its PostgreSQL
  container is ready:
  - `scripts/dev-demo/alembic.sh upgrade`
  - `scripts/dev-demo/seed-content-snippets.sh`
- Use the root `Dockerfile` after the app skeleton has generated
  `pyproject.toml`, `uv.lock`, `app/`, `alembic/`, and `alembic.ini`.
- Create the app deployment behavior after the health endpoint, snippet
  endpoint, migration/seed behavior, and image tag strategy are decided.
- Build the app image locally from the separate build clone, export it as a
  tarball, then deploy to `dev-demo` first:
  - `scripts/build/build-image-tar.sh`
  - `scripts/dev-demo/deploy-app.sh`
- When deploying from outside the trusted LAN, operators may skip the dev-demo
  path and proceed directly to the image build and aws-demo path.
- Verify the app on `dev-demo` through the deployed Docker container:
  - `GET /health`
  - `GET /api/v1/snippets/{key}`
- Deploy to `aws-demo` only after `dev-demo` verification succeeds:
  - `scripts/aws-demo/alembic.sh upgrade`
  - `scripts/aws-demo/seed-content-snippets.sh`
  - `scripts/aws-demo/deploy-app.sh`
- Run backup, restore, or reset scripts only as explicit database operations.

## App Deployment Script Responsibilities

- `scripts/dev-demo/deploy-app.sh` should deploy a prebuilt image tarball,
  replace only the dev app container, verify `/health`, and print curl commands.
- `scripts/aws-demo/deploy-app.sh` should deploy a prebuilt image tarball with
  sudo Docker, replace only the aws app container, verify `/health`, and print
  SSH-based localhost curl commands.
- Future app deployment scripts should require an already-built local image
  tarball.
- Future app deployment scripts should transfer that tarball to the target
  host.
- Future app deployment scripts should run `docker load` on the target host.
- Future app deployment scripts should require the target `app.env` file to
  exist before running the container.
- Future app deployment scripts should ensure the target Docker network exists.
- Future app deployment scripts should stop and remove only the FastAPI/Uvicorn
  app container.
- Future app deployment scripts should start the new app container attached to
  the existing target Docker network.
- Future app deployment scripts should verify a health or readiness endpoint.
- Successful app deployment scripts should print follow-up `curl` commands for
  `/health` and `/api/v1/snippets/home.hero`.

## App Deployment Script Boundaries

- App deployment scripts must not build Docker images on `aws-demo` or
  `dev-demo`.
- App deployment scripts must not build Docker images from the primary working
  tree.
- App deployment scripts must not generate production-like secrets.
- App deployment scripts must not stop, remove, recreate, reset, or migrate the
  PostgreSQL container unless a future migration step is explicitly designed
  and documented.
- App deployment scripts must not delete database data directories or env files.

## Python And Dependency Management

- Use Python 3.12.
- Use `uv` for dependency and virtual environment management.
- Local development uses a repository-local `.venv`.
- Commit `pyproject.toml` and `uv.lock`.
- Docker images install dependencies from `uv.lock` into the container
  environment.
- Runtime hosts such as `aws-demo` and `dev-demo` should not manage Python
  dependencies directly.
- Because FastAPI does not provide an official `create-next-app`-style starter,
  bootstrap scripts should encode repeatable backend defaults.
- The bootstrap defaults are both setup automation and an architectural
  decision record.

## Prerequisites

- The local machine must have Git, OpenSSH, a POSIX shell, `uv`, and Python
  3.12 available to `uv`.
- Windows users should run the shell scripts from WSL or another Linux-like
  shell environment.
- Local script target overrides may be stored in ignored files copied from:
  - `scripts/env/dev-demo.local.env.example`
  - `scripts/env/aws-demo.local.env.example`
- `ssh yoga` must reach the internal `dev-demo` host by default. Callers can
  override this with `DEV_DEMO_HOST`, `scripts/env/dev-demo.env`, or
  `scripts/env/dev-demo.local.env`.
- `ssh aws-demo` must reach the production-like host by default. Callers can
  override this with `AWS_DEMO_HOST`, `scripts/env/aws-demo.env`, or
  `scripts/env/aws-demo.local.env`.
- `dev-demo` must have Docker installed, running, and usable by the SSH user
  without sudo.
- The default trusted LAN IP for `dev-demo` is `192.168.0.104`. Callers can
  override this with `DEV_DEMO_LAN_IP`, `scripts/env/dev-demo.env`, or
  `scripts/env/dev-demo.local.env`.
- `aws-demo` must have Docker installed and usable through sudo.
- Run `scripts/check-prereqs.sh` before the bootstrap and deployment scripts to
  verify these assumptions without changing local or remote state.

## Default Backend Stack

- Use FastAPI and Uvicorn for the API runtime.
- Use Pydantic Settings for environment-driven configuration.
- Use PostgreSQL as the default database.
- Use SQLAlchemy async as the default ORM/database layer.
- Use asyncpg as the PostgreSQL driver.
- Use Alembic for database migrations.
- Use pytest, pytest-asyncio, and httpx for tests.
- Use Ruff for linting and formatting.

## Authentication And Logging

- Prefer bearer-token authentication as the default API authentication shape.
- Keep the exact identity provider, OAuth flow, JWT issuer, or session strategy
  configurable until the sibling applications require a specific integration.
- Include authentication dependencies only when the first protected endpoint or
  token validation path is implemented.
- Start with standard-library `logging`.
- Prefer structured, request-aware application logs that include fields such as
  timestamp, level, request id, route, status code, and elapsed time.
- Defer heavier logging frameworks until there is a concrete need.

## Local Development Database

- The default local path does not use a database.
- Local scripts prepare source files, dependency metadata, and test scaffolding.
- Do not run a persistent local Uvicorn server as the normal validation path.
- Use `dev-demo` as the development server target and validate the app through
  its Docker container.
- A separate local PostgreSQL instance may still be used only as disposable
  development infrastructure when explicitly needed.
- Local PostgreSQL data must live outside this repository, and local
  credentials or env files must not be committed or included in Docker images.

## Baseline API And Database

- `GET /health` is the canonical health endpoint.
- Health checks are infrastructure-facing and should stay outside versioned API
  prefixes.
- `GET /api/v1/snippets/{key}` is the baseline content endpoint used to prove
  that the app container can read seeded data from PostgreSQL.
- The initial `content_snippets` table is a deployment verification fixture, not
  a final domain model.
- Users should add real domain tables, migrations, service functions, schemas,
  and routes after the baseline deploy succeeds.

## Remote Database On aws-demo

- The `aws-demo` PostgreSQL container should be managed separately from app
  deployment.
- Use a dedicated root-level host directory for PostgreSQL data.
- Use remote-only env files or mounted secret files.
- `aws-demo/setup-env.sh` prepares directories and example env files, but does
  not generate production-like secrets.
- `aws-demo` env files must be created or edited manually on the remote host.
- Do not publish the PostgreSQL host port on `aws-demo`; app containers should
  reach PostgreSQL through the Docker network.
- App redeploy scripts must not stop, remove, or recreate the PostgreSQL
  container.
- Database backup and restore should be handled by explicit database scripts.

## Remote Database On dev-demo

- The `dev-demo` PostgreSQL container should use its own data directories,
  env files, volumes, container names, and Docker network names.
- `dev-demo` currently maps to the SSH alias `yoga`, which resolves to
  `hchjeong@192.168.0.104` on the trusted LAN.
- Unlike `aws-demo`, `dev-demo` exposes PostgreSQL to the trusted LAN for local
  development tools and sibling development machines.
- Bind PostgreSQL to the known LAN IP, `192.168.0.104`, rather than `0.0.0.0`
  when possible.
- `dev-demo/setup-env.sh` may create development-only env files and generated
  database passwords, while preserving existing files.
- `dev-demo` may support development-only reset or recreate scripts.
- `dev-demo` scripts must never reference `aws-demo` credentials, directories,
  volumes, or SSH host aliases.
- Keep `dev-demo` close enough to `aws-demo` to test deployment behavior, while
  allowing controlled destructive workflows that would be unsafe on `aws-demo`.

## Initial Script Shape

- `scripts/check-prereqs.sh`
- `scripts/env/dev-demo.local.env.example`
- `scripts/env/aws-demo.local.env.example`
- `Dockerfile`
- `.dockerignore`
- `scripts/build/build-image-tar.sh`
- `scripts/bootstrap/setup-local-venv.sh`
- `scripts/bootstrap/create-app-skeleton.sh`
- `scripts/dev-demo/setup-env.sh`
- `scripts/dev-demo/deploy-postgres.sh`
- `scripts/dev-demo/alembic.sh`
- `scripts/dev-demo/seed-content-snippets.sh`
- `scripts/dev-demo/deploy-app.sh`
- `scripts/aws-demo/setup-env.sh`
- `scripts/aws-demo/deploy-postgres.sh`
- `scripts/aws-demo/alembic.sh`
- `scripts/aws-demo/seed-content-snippets.sh`
- `scripts/aws-demo/deploy-app.sh`
